// pty-sidecar/src/main_complex.rs
// Phase 1: Complete PTY Sidecar Implementation with Session Management
// Features: Multi-session support, metrics tracking, latency monitoring

use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use futures_util::{StreamExt, SinkExt};
use portable_pty::{native_pty_system, CommandBuilder, PtySize, PtyPair, MasterPty};
use serde::{Deserialize, Serialize};
use tracing::{info, error, warn, debug};
use anyhow::Result;
use std::sync::Arc;
use std::io::Write;
use dashmap::DashMap;
use uuid::Uuid;
use std::time::Instant;

// Session tracking
type SessionId = Uuid;
type Sessions = Arc<DashMap<SessionId, SessionState>>;

struct SessionState {
    id: SessionId,
    pty_pair: Box<PtyPair>,
    created_at: Instant,
    last_activity: Instant,
}

// Control message protocol definition
#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "cmd")]
enum ControlMessage {
    #[serde(rename = "resize")]
    Resize { rows: u16, cols: u16 },
    #[serde(rename = "ping")]
    Ping,
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "session")]
    Session { id: String },
    #[serde(rename = "error")]
    Error { message: String },
    #[serde(rename = "metrics")]
    Metrics,
}

#[derive(Debug, Serialize)]
struct MetricsResponse {
    latency_us: u64,
    sessions_active: usize,
    uptime_secs: u64,
}

// Latency tracking
struct LatencyTracker {
    measurements: Vec<std::time::Duration>,
    high_latency_count: usize,
}

impl LatencyTracker {
    fn new() -> Self {
        Self {
            measurements: Vec::with_capacity(1000),
            high_latency_count: 0,
        }
    }
    
    fn record(&mut self, duration: std::time::Duration) {
        if self.measurements.len() < 1000 {
            self.measurements.push(duration);
        }
        if duration.as_millis() > 50 {
            self.high_latency_count += 1;
        }
    }
    
    fn report(&self) {
        if self.measurements.is_empty() {
            return;
        }
        
        let total: std::time::Duration = self.measurements.iter().sum();
        let avg = total / self.measurements.len() as u32;
        let max = self.measurements.iter().max().unwrap();
        let min = self.measurements.iter().min().unwrap();
        
        info!(
            "Latency stats - Avg: {}ms, Min: {}ms, Max: {}ms, High(>50ms): {}",
            avg.as_millis(),
            min.as_millis(),
            max.as_millis(),
            self.high_latency_count
        );
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();
    
    let addr = "127.0.0.1:8081";
    let listener = TcpListener::bind(&addr).await?;
    info!("PTY WebSocket server running on ws://{}", addr);
    
    let sessions: Sessions = Arc::new(DashMap::new());
    let start_time = Instant::now();
    
    // Spawn metrics collector
    let sessions_clone = sessions.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(tokio::time::Duration::from_secs(60));
        loop {
            interval.tick().await;
            cleanup_stale_sessions(&sessions_clone);
        }
    });
    
    while let Ok((stream, addr)) = listener.accept().await {
        info!("New connection from: {}", addr);
        let sessions = sessions.clone();
        tokio::spawn(handle_connection(stream, sessions, start_time));
    }
    
    Ok(())
}

async fn handle_connection(
    stream: TcpStream,
    sessions: Sessions,
    start_time: Instant,
) -> Result<()> {
    
    let ws_stream = accept_async(stream).await?;
    
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // Create PTY session
    let session_id = Uuid::new_v4();
    let mut pty_session = match PtySession::new(session_id) {
        Ok(session) => {
            info!("PTY session {} created with Zellij", session_id);
            session
        }
        Err(e) => {
            error!("Failed to create PTY session: {}", e);
            let error_msg = serde_json::to_string(&ControlMessage::Error {
                message: format!("Failed to create PTY: {}", e),
            })?;
            ws_sender.send(Message::Text(error_msg)).await?;
            return Err(e);
        }
    };
    
    // Send initial session message
    let session_msg = serde_json::to_string(&ControlMessage::Session {
        id: session_id.to_string(),
    })?;
    
    if let Err(e) = ws_sender.send(Message::Text(session_msg)).await {
        error!("Failed to send session ID: {}", e);
        return Err(e.into());
    }
    
    info!("Session {} created for connection #{}", session_id, connection_id);
    
    // Get PTY reader and writer
    let mut pty_reader = pty_session.pty_pair.master.try_clone_reader()?;
    let mut pty_writer = pty_session.pty_pair.master.take_writer()?;
    
    // Wrap PTY session in Arc<Mutex> for shared access
    let pty_session = Arc::new(Mutex::new(pty_session));
    
    // Create a channel for PTY output
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
    
    // Task 1: PTY -> Channel
    // Read from PTY and send to channel
    let session_id_clone = session_id;
    let pty_to_channel_task = tokio::spawn(async move {
        let mut buffer = vec![0u8; 4096]; // 4KB buffer for optimal terminal performance
        
        loop {
            // Use block_in_place for synchronous PTY read
            let n = match tokio::task::block_in_place(|| pty_reader.read(&mut buffer)) {
                Ok(0) => {
                    debug!("PTY EOF reached");
                    break; // EOF
                }
                Ok(n) => n,
                Err(e) => {
                    error!("PTY read error: {}", e);
                    break;
                }
            };
            
            // Send data to channel
            if tx.send(buffer[..n].to_vec()).is_err() {
                error!("Channel closed, stopping PTY reader");
                break;
            }
            
            debug!("Read {} bytes from PTY", n);
        }
        
        info!("PTY reader task ended for session {}", session_id_clone);
    });
    
    // Task 2: Channel -> WebSocket
    // Forward data from channel to WebSocket
    let channel_to_ws_task = tokio::spawn(async move {
        while let Some(data) = rx.recv().await {
            if let Err(e) = ws_sender.send(Message::Binary(data)).await {
                error!("Failed to send PTY data to WebSocket: {}", e);
                break;
            }
        }
        info!("Channel->WebSocket task ended");
    });
    
    // Task 3: WebSocket -> PTY
    // Handle WebSocket messages and control commands
    let pty_session_clone = Arc::clone(&pty_session);
    let (control_tx, mut control_rx) = tokio::sync::mpsc::unbounded_channel::<Message>();
    
    // Spawn task to handle control messages
    let control_handler_task = tokio::spawn(async move {
        while let Some(msg) = control_rx.recv().await {
            if let Message::Text(text) = msg {
                let response = match serde_json::from_str::<ControlMessage>(&text) {
                    Ok(ControlMessage::Ping) => {
                        Some(Message::Text(serde_json::to_string(&ControlMessage::Pong).unwrap()))
                    }
                    Ok(ControlMessage::Metrics) => {
                        let metrics = MetricsResponse {
                            status: "healthy".to_string(),
                            version: env!("CARGO_PKG_VERSION").to_string(),
                            connections_total: 1,
                        };
                        Some(Message::Text(serde_json::to_string(&metrics).unwrap()))
                    }
                    _ => None,
                };
                
                if let Some(response) = response {
                    // Send response back through the channel
                    let _ = tx.send(response.into());
                }
            }
        }
    });
    
    while let Some(msg) = ws_receiver.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                debug!("Received text message: {}", text);
                
                // Parse and handle control messages
                match serde_json::from_str::<ControlMessage>(&text) {
                    Ok(ControlMessage::Resize { rows, cols }) => {
                        info!("Resizing PTY to {}x{} for session {}", cols, rows, session_id);
                        let mut session = pty_session_clone.lock().await;
                        if let Err(e) = session.resize(rows, cols) {
                            error!("Failed to resize PTY: {}", e);
                        }
                    }
                    Ok(ControlMessage::Ping) => {
                        let pong = serde_json::to_string(&ControlMessage::Pong)?;
                        tx.send(Message::Text(pong).into()).ok();
                    }
                    Ok(ControlMessage::Metrics) => {
                        let metrics = MetricsResponse {
                            status: "healthy".to_string(),
                            version: env!("CARGO_PKG_VERSION").to_string(),
                            connections_total: connection_id,
                        };
                        let response = serde_json::to_string(&metrics)?;
                        tx.send(Message::Text(response).into()).ok();
                    }
                    Ok(msg) => {
                        debug!("Unhandled control message: {:?}", msg);
                    }
                    Err(e) => {
                        warn!("Invalid control message: {}", e);
                    }
                }
            }
            Ok(Message::Binary(data)) => {
                debug!("Received {} bytes of binary data", data.len());
                
                // Write directly to PTY
                if let Err(e) = pty_writer.write_all(&data) {
                    error!("Failed to write to PTY: {}", e);
                    break;
                }
                
                // Flush to ensure immediate delivery
                if let Err(e) = pty_writer.flush() {
                    error!("Failed to flush PTY: {}", e);
                }
            }
            Ok(Message::Ping(data)) => {
                debug!("Received ping, sending pong");
                tx.send(Message::Pong(data).into()).ok();
            }
            Ok(Message::Close(frame)) => {
                info!("WebSocket closing for session {}: {:?}", session_id, frame);
                break;
            }
            Err(e) => {
                error!("WebSocket error for session {}: {}", session_id, e);
                break;
            }
            _ => {}
        }
    }
    
    // Cleanup: abort tasks
    pty_to_channel_task.abort();
    channel_to_ws_task.abort();
    control_handler_task.abort();
    
    // PTY session will be dropped here, killing the child process
    info!("Connection #{} closed (session: {})", connection_id, session_id);
    Ok(())
}