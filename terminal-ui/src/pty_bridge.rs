use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::RwLock;
use tokio_tungstenite::{connect_async, WebSocketStream, MaybeTlsStream};
use tokio::net::TcpStream;
use futures_util::{SinkExt, StreamExt};

#[derive(Debug)]
pub struct PTYBridge {
    url: String,
    connection: Arc<RwLock<Option<PTYConnection>>>,
    latency_history: Arc<RwLock<Vec<f64>>>,
    connected: Arc<RwLock<bool>>,
}

#[derive(Debug)]
pub struct PTYConnection {
    websocket: WebSocketStream<MaybeTlsStream<TcpStream>>,
    session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PTYMessage {
    pub message_type: PTYMessageType,
    pub session_id: String,
    pub data: String,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PTYMessageType {
    Input,
    Output,
    Resize,
    Connect,
    Disconnect,
    Ping,
    Pong,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PTYResizeData {
    pub cols: u16,
    pub rows: u16,
}

impl PTYBridge {
    pub async fn new(url: &str) -> Result<Self> {
        Ok(Self {
            url: url.to_string(),
            connection: Arc::new(RwLock::new(None)),
            latency_history: Arc::new(RwLock::new(Vec::new())),
            connected: Arc::new(RwLock::new(false)),
        })
    }

    pub async fn connect(&self) -> Result<()> {
        println!("🔌 Connecting to PTY bridge: {}", self.url);

        let (ws_stream, _) = connect_async(&self.url).await?;
        let session_id = uuid::Uuid::new_v4().to_string();

        // Send connection message
        let connect_msg = PTYMessage {
            message_type: PTYMessageType::Connect,
            session_id: session_id.clone(),
            data: "devys-terminal".to_string(),
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)?
                .as_millis() as u64,
        };

        let mut connection = self.connection.write().await;
        *connection = Some(PTYConnection {
            websocket: ws_stream,
            session_id: session_id.clone(),
        });

        // Send connection message
        if let Some(ref mut conn) = connection.as_mut() {
            let msg = tokio_tungstenite::tungstenite::Message::Text(
                serde_json::to_string(&connect_msg)?
            );
            conn.websocket.send(msg).await?;
        }

        *self.connected.write().await = true;

        // Start message handling loop
        self.start_message_handler().await?;

        println!("✅ Connected to PTY bridge with session: {}", session_id);
        Ok(())
    }

    pub async fn disconnect(&self) -> Result<()> {
        if let Some(mut conn) = self.connection.write().await.take() {
            let disconnect_msg = PTYMessage {
                message_type: PTYMessageType::Disconnect,
                session_id: conn.session_id.clone(),
                data: String::new(),
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_millis() as u64,
            };

            let msg = tokio_tungstenite::tungstenite::Message::Text(
                serde_json::to_string(&disconnect_msg)?
            );
            conn.websocket.send(msg).await?;
            conn.websocket.close(None).await?;
        }

        *self.connected.write().await = false;
        println!("🔌 Disconnected from PTY bridge");
        Ok(())
    }

    pub async fn send_input(&self, input: &str) -> Result<()> {
        if let Some(ref mut conn) = self.connection.write().await.as_mut() {
            let input_msg = PTYMessage {
                message_type: PTYMessageType::Input,
                session_id: conn.session_id.clone(),
                data: input.to_string(),
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_millis() as u64,
            };

            let msg = tokio_tungstenite::tungstenite::Message::Text(
                serde_json::to_string(&input_msg)?
            );
            conn.websocket.send(msg).await?;
        }
        Ok(())
    }

    pub async fn resize_pty(&self, cols: u16, rows: u16) -> Result<()> {
        if let Some(ref mut conn) = self.connection.write().await.as_mut() {
            let resize_data = PTYResizeData { cols, rows };
            let resize_msg = PTYMessage {
                message_type: PTYMessageType::Resize,
                session_id: conn.session_id.clone(),
                data: serde_json::to_string(&resize_data)?,
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_millis() as u64,
            };

            let msg = tokio_tungstenite::tungstenite::Message::Text(
                serde_json::to_string(&resize_msg)?
            );
            conn.websocket.send(msg).await?;
        }
        Ok(())
    }

    pub async fn measure_latency(&self) -> Result<f64> {
        let start = Instant::now();
        
        if let Some(ref mut conn) = self.connection.write().await.as_mut() {
            let ping_msg = PTYMessage {
                message_type: PTYMessageType::Ping,
                session_id: conn.session_id.clone(),
                data: start.elapsed().as_nanos().to_string(),
                timestamp: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_millis() as u64,
            };

            let msg = tokio_tungstenite::tungstenite::Message::Text(
                serde_json::to_string(&ping_msg)?
            );
            conn.websocket.send(msg).await?;

            // Wait for pong response (simplified - in real implementation we'd track this)
            let latency = start.elapsed().as_millis() as f64;
            
            // Update latency history
            let mut history = self.latency_history.write().await;
            history.push(latency);
            
            // Keep only last 100 measurements
            if history.len() > 100 {
                history.remove(0);
            }

            return Ok(latency);
        }

        Err(anyhow::anyhow!("Not connected to PTY bridge"))
    }

    pub async fn get_average_latency(&self) -> f64 {
        let history = self.latency_history.read().await;
        if history.is_empty() {
            0.0
        } else {
            history.iter().sum::<f64>() / history.len() as f64
        }
    }

    pub async fn is_connected(&self) -> bool {
        *self.connected.read().await
    }

    pub async fn get_connection_status(&self) -> PTYBridgeStatus {
        let connected = self.is_connected().await;
        let avg_latency = self.get_average_latency().await;
        let session_id = if let Some(ref conn) = *self.connection.read().await {
            Some(conn.session_id.clone())
        } else {
            None
        };

        PTYBridgeStatus {
            connected,
            session_id,
            average_latency_ms: avg_latency,
            url: self.url.clone(),
        }
    }

    async fn start_message_handler(&self) -> Result<()> {
        // Clone necessary data for the handler task
        let connection = self.connection.clone();
        let latency_history = self.latency_history.clone();
        let connected = self.connected.clone();

        tokio::spawn(async move {
            loop {
                // Check if we're still connected
                if !*connected.read().await {
                    break;
                }

                // Handle incoming messages
                if let Some(ref mut conn) = connection.write().await.as_mut() {
                    if let Some(message) = conn.websocket.next().await {
                        match message {
                            Ok(msg) => {
                                if let Err(e) = Self::handle_message(msg, &latency_history).await {
                                    eprintln!("Error handling PTY message: {}", e);
                                }
                            }
                            Err(e) => {
                                eprintln!("WebSocket error: {}", e);
                                *connected.write().await = false;
                                break;
                            }
                        }
                    }
                } else {
                    // No connection, wait a bit and check again
                    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
                }
            }
        });

        Ok(())
    }

    async fn handle_message(
        message: tokio_tungstenite::tungstenite::Message,
        latency_history: &Arc<RwLock<Vec<f64>>>,
    ) -> Result<()> {
        match message {
            tokio_tungstenite::tungstenite::Message::Text(text) => {
                let pty_msg: PTYMessage = serde_json::from_str(&text)?;
                
                match pty_msg.message_type {
                    PTYMessageType::Output => {
                        // Handle terminal output (would normally send to terminal display)
                        // For now, we'll just log debug info
                        tracing::debug!("PTY output: {}", pty_msg.data);
                    }
                    PTYMessageType::Pong => {
                        // Calculate latency from ping timestamp
                        if let Ok(ping_time) = pty_msg.data.parse::<u128>() {
                            let now = std::time::SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)?
                                .as_nanos();
                            let latency = (now - ping_time) as f64 / 1_000_000.0; // Convert to ms
                            
                            let mut history = latency_history.write().await;
                            history.push(latency);
                            if history.len() > 100 {
                                history.remove(0);
                            }
                        }
                    }
                    _ => {
                        // Handle other message types
                        tracing::debug!("PTY message: {:?}", pty_msg);
                    }
                }
            }
            tokio_tungstenite::tungstenite::Message::Binary(_) => {
                // Handle binary data if needed
            }
            tokio_tungstenite::tungstenite::Message::Ping(data) => {
                // Respond to ping
                tracing::debug!("Received ping, sending pong");
            }
            tokio_tungstenite::tungstenite::Message::Pong(_) => {
                // Handle pong
                tracing::debug!("Received pong");
            }
            tokio_tungstenite::tungstenite::Message::Close(_) => {
                // Connection closed
                tracing::info!("PTY bridge connection closed");
            }
            tokio_tungstenite::tungstenite::Message::Frame(_) => {
                // Raw frame - normally shouldn't see this
            }
        }

        Ok(())
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PTYBridgeStatus {
    pub connected: bool,
    pub session_id: Option<String>,
    pub average_latency_ms: f64,
    pub url: String,
}

impl std::fmt::Display for PTYBridgeStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "PTY Bridge: {} | Session: {} | Latency: {:.1}ms | URL: {}",
            if self.connected { "Connected" } else { "Disconnected" },
            self.session_id.as_deref().unwrap_or("None"),
            self.average_latency_ms,
            self.url
        )
    }
}