// pty-sidecar/src/main.rs
// Day 3: PTY Integration - Simplified approach
// Goal: Fully functional PTY with Zellij terminal multiplexer

use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, tungstenite::Message};
use futures_util::{StreamExt, SinkExt};
use portable_pty::{native_pty_system, CommandBuilder, PtySize, PtyPair, Child};
use serde::{Deserialize, Serialize};
use tracing::{info, error, warn, debug};
use anyhow::Result;
use std::net::SocketAddr;
use std::sync::Arc;
use std::io::{Read, Write};
use tokio::sync::Mutex;
use uuid::Uuid;

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
    status: String,
    version: String,
    connections_total: u64,
}

// PTY session structure to hold PTY state
struct PtySession {
    id: Uuid,
    pty_pair: Box<PtyPair>,
    child: Box<dyn Child + Send + Sync>,
}

impl PtySession {
    fn new(id: Uuid) -> Result<Self> {
        // Create PTY with initial size
        let pty_system = native_pty_system();
        let pty_pair = pty_system.openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        
        // Configure command to spawn Zellij (use short session name)
        let mut cmd = CommandBuilder::new("zellij");
        let short_id = format!("d{}", &id.to_string()[0..8]);
        cmd.args(&["-s", &short_id]);
        cmd.env("TERM", "xterm-256color");
        cmd.env("EDITOR", "hx");
        cmd.env("COLORTERM", "truecolor");
        
        // Spawn the child process
        let child = pty_pair.slave.spawn_command(cmd)?;
        
        Ok(Self {
            id,
            pty_pair: Box::new(pty_pair),
            child,
        })
    }
    
    fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        self.pty_pair.master.resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })?;
        Ok(())
    }
}

impl Drop for PtySession {
    fn drop(&mut self) {
        // Ensure child process is killed when session is dropped
        let _ = self.child.kill();
        info!("PTY session {} terminated", self.id);
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing with environment filter
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("pty_sidecar=info".parse()?)
        )
        .with_target(false)
        .with_thread_ids(false)
        .with_line_number(true)
        .init();
    
    let addr = "127.0.0.1:8081";
    let listener = TcpListener::bind(&addr).await?;
    info!("PTY WebSocket server running on ws://{}", addr);
    info!("Test with: wscat -c ws://localhost:8081");
    
    let mut connection_count: u64 = 0;
    
    // Main accept loop
    loop {
        match listener.accept().await {
            Ok((stream, addr)) => {
                connection_count += 1;
                info!("New connection #{} from: {}", connection_count, addr);
                
                // Spawn a task for each connection
                tokio::spawn(handle_connection(stream, addr, connection_count));
            }
            Err(e) => {
                error!("Failed to accept connection: {}", e);
            }
        }
    }
}

async fn handle_connection(
    stream: TcpStream,
    _addr: SocketAddr,
    connection_id: u64,
) -> Result<()> {
    debug!("Starting WebSocket handshake for connection #{}", connection_id);
    
    // Perform WebSocket handshake
    let ws_stream = match accept_async(stream).await {
        Ok(ws) => {
            info!("WebSocket handshake successful for connection #{}", connection_id);
            ws
        }
        Err(e) => {
            error!("WebSocket handshake failed for connection #{}: {}", connection_id, e);
            return Err(e.into());
        }
    };
    
    // Create PTY session
    let session_id = Uuid::new_v4();
    let mut pty_session = match PtySession::new(session_id) {
        Ok(session) => {
            info!("PTY session {} created with Zellij", session_id);
            session
        }
        Err(e) => {
            error!("Failed to create PTY session: {}", e);
            return Err(e);
        }
    };
    
    // Get PTY reader and writer
    let mut pty_reader = pty_session.pty_pair.master.try_clone_reader()?;
    let mut pty_writer = pty_session.pty_pair.master.take_writer()?;
    
    // Wrap PTY session in Arc<Mutex> for shared access
    let pty_session = Arc::new(Mutex::new(pty_session));
    
    // Create channel for PTY output
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();
    
    // Spawn PTY reader task
    let session_id_clone = session_id;
    let pty_reader_task = tokio::spawn(async move {
        let mut buffer = vec![0u8; 4096]; // 4KB buffer
        
        loop {
            let n = match tokio::task::block_in_place(|| pty_reader.read(&mut buffer)) {
                Ok(0) => break, // EOF
                Ok(n) => n,
                Err(e) => {
                    error!("PTY read error: {}", e);
                    break;
                }
            };
            
            if tx.send(buffer[..n].to_vec()).is_err() {
                break;
            }
        }
        
        info!("PTY reader task ended for session {}", session_id_clone);
    });
    
    // Split WebSocket for concurrent I/O
    let (mut ws_write, mut ws_read) = ws_stream.split();
    
    // Send initial session message
    let session_msg = serde_json::to_string(&ControlMessage::Session {
        id: session_id.to_string(),
    })?;
    ws_write.send(Message::Text(session_msg)).await?;
    
    // Spawn WebSocket writer task (PTY output -> WebSocket)
    let ws_writer_task = tokio::spawn(async move {
        while let Some(data) = rx.recv().await {
            if let Err(e) = ws_write.send(Message::Binary(data)).await {
                error!("Failed to send to WebSocket: {}", e);
                break;
            }
        }
    });
    
    // Main loop: Handle WebSocket input -> PTY
    let pty_session_clone = Arc::clone(&pty_session);
    
    while let Some(msg) = ws_read.next().await {
        match msg {
            Ok(Message::Binary(data)) => {
                // Write keyboard input to PTY
                if let Err(e) = pty_writer.write_all(&data) {
                    error!("Failed to write to PTY: {}", e);
                    break;
                }
                pty_writer.flush()?;
            }
            Ok(Message::Text(text)) => {
                // Handle control messages
                if let Ok(ctrl) = serde_json::from_str::<ControlMessage>(&text) {
                    match ctrl {
                        ControlMessage::Resize { rows, cols } => {
                            info!("Resizing PTY to {}x{}", cols, rows);
                            let mut session = pty_session_clone.lock().await;
                            session.resize(rows, cols)?;
                        }
                        _ => {}
                    }
                }
            }
            Ok(Message::Close(_)) => {
                info!("WebSocket closed for session {}", session_id);
                break;
            }
            Err(e) => {
                error!("WebSocket error: {}", e);
                break;
            }
            _ => {}
        }
    }
    
    // Cleanup
    pty_reader_task.abort();
    ws_writer_task.abort();
    
    info!("Connection #{} closed (session: {})", connection_id, session_id);
    Ok(())
}