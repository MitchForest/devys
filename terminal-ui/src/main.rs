use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::process::{Command, Stdio};
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tokio::time::{interval, Duration};

mod claude_integration;
mod terminal_ui;
mod pty_bridge;

use claude_integration::ClaudeCodeIntegration;
use terminal_ui::TerminalUI;
use pty_bridge::PTYBridge;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DevysCoreConfig {
    pub control_plane_url: String,
    pub pty_bridge_url: String,
    pub zellij_config_path: String,
    pub helix_config_path: String,
    pub keystroke_latency_target_ms: u64,
    pub websocket_timeout_ms: u64,
    pub cache_size_mb: usize,
    pub ai: AIConfig,
    pub grunt: GruntConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AIConfig {
    pub planner_model: String,
    pub editor_model: String,
    pub reviewer_model: String,
    pub grunt_models: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GruntConfig {
    pub enabled: bool,
    pub local_first: bool,
    pub cost_limit_daily: f32,
    pub parallel_tasks: usize,
}

impl Default for DevysCoreConfig {
    fn default() -> Self {
        Self {
            control_plane_url: "http://localhost:3000".to_string(),
            pty_bridge_url: "ws://localhost:8080/pty".to_string(),
            zellij_config_path: "~/.config/zellij/devys-layout.kdl".to_string(),
            helix_config_path: "~/.config/helix/config.toml".to_string(),
            keystroke_latency_target_ms: 50,
            websocket_timeout_ms: 5000,
            cache_size_mb: 500,
            ai: AIConfig {
                planner_model: "gemini-2.0-flash-thinking".to_string(),
                editor_model: "claude-3-5-sonnet".to_string(),
                reviewer_model: "o1".to_string(),
                grunt_models: vec![
                    "ollama:qwen2.5-coder:14b".to_string(),
                    "deepseek-chat".to_string(),
                ],
            },
            grunt: GruntConfig {
                enabled: true,
                local_first: true,
                cost_limit_daily: 1.00,
                parallel_tasks: 4,
            },
        }
    }
}

#[derive(Debug)]
pub struct DevysCore {
    config: DevysCoreConfig,
    claude_code: Arc<ClaudeCodeIntegration>,
    terminal_ui: Arc<TerminalUI>,
    pty_bridge: Arc<PTYBridge>,
    command_channel: mpsc::UnboundedSender<DevysCommand>,
    status: Arc<RwLock<DevysStatus>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DevysStatus {
    pub mode: String,
    pub active_agents: Vec<String>,
    pub uptime_seconds: u64,
    pub keystroke_latency_ms: f64,
    pub commands_processed: u64,
    pub total_cost_usd: f32,
    pub daily_cost_usd: f32,
    pub error_count: u64,
}

#[derive(Debug, Clone)]
pub enum DevysCommand {
    Initialize,
    StartZellijSession,
    ExecuteWorkflow { query: String, mode: Option<String> },
    ToggleGruntMode,
    ShowStatus,
    Shutdown,
    RefreshContext,
    OptimizeContext,
    SwitchModel { model: String },
}

impl DevysCore {
    pub async fn new(config: DevysCoreConfig) -> Result<Self> {
        let (command_sender, command_receiver) = mpsc::unbounded_channel();
        
        let status = Arc::new(RwLock::new(DevysStatus {
            mode: "INITIALIZING".to_string(),
            active_agents: vec![],
            uptime_seconds: 0,
            keystroke_latency_ms: 0.0,
            commands_processed: 0,
            total_cost_usd: 0.0,
            daily_cost_usd: 0.0,
            error_count: 0,
        }));

        // Initialize components
        let claude_code = Arc::new(ClaudeCodeIntegration::new(&config).await?);
        let terminal_ui = Arc::new(TerminalUI::new(&config)?);
        let pty_bridge = Arc::new(PTYBridge::new(&config.pty_bridge_url).await?);

        let core = Self {
            config,
            claude_code,
            terminal_ui,
            pty_bridge,
            command_channel: command_sender,
            status,
        };

        // Start command processor
        let core_clone = Arc::new(core.clone());
        tokio::spawn(async move {
            core_clone.process_commands(command_receiver).await
        });

        Ok(core)
    }

    pub async fn initialize(&self) -> Result<()> {
        println!("🚀 Initializing Devys Core Phase 4...");

        // 1. Initialize PTY bridge for <50ms latency
        println!("⚡ Connecting to PTY bridge...");
        self.pty_bridge.connect().await?;

        // 2. Initialize Claude Code SDK
        println!("🧠 Initializing Claude Code SDK...");
        self.claude_code.initialize().await?;

        // 3. Setup terminal UI
        println!("🖥️  Setting up terminal UI...");
        self.terminal_ui.initialize_zellij().await?;

        // 4. Register keybindings
        println!("⌨️  Registering keybindings...");
        self.register_keybindings().await?;

        // 5. Start MCP servers
        println!("🔗 Starting MCP servers...");
        self.start_mcp_servers().await?;

        // 6. Start monitoring tasks
        println!("📊 Starting monitoring tasks...");
        self.start_monitoring().await?;

        // Update status
        {
            let mut status = self.status.write().await;
            status.mode = "READY".to_string();
        }

        println!("✅ Devys Phase 4 initialized successfully!");
        Ok(())
    }

    async fn register_keybindings(&self) -> Result<()> {
        // Register Helix keybindings for AI commands
        self.terminal_ui.helix.register_command("devys-plan", {
            let sender = self.command_channel.clone();
            Box::new(move |selection: String| {
                let sender = sender.clone();
                Box::pin(async move {
                    sender.send(DevysCommand::ExecuteWorkflow { 
                        query: selection, 
                        mode: Some("PLAN".to_string()) 
                    }).unwrap();
                })
            })
        }).await?;

        self.terminal_ui.helix.register_command("devys-edit", {
            let sender = self.command_channel.clone();
            Box::new(move |_: String| {
                let sender = sender.clone();
                Box::pin(async move {
                    sender.send(DevysCommand::ExecuteWorkflow { 
                        query: "Continue editing".to_string(), 
                        mode: Some("EDIT".to_string()) 
                    }).unwrap();
                })
            })
        }).await?;

        // Register Zellij keybindings for pane management
        self.terminal_ui.zellij.register_binding("Alt+a", {
            let ui = self.terminal_ui.clone();
            Box::new(move || {
                let ui = ui.clone();
                Box::pin(async move {
                    ui.zellij.focus_pane("ai-chat").await.unwrap();
                })
            })
        }).await?;

        self.terminal_ui.zellij.register_binding("Alt+c", {
            let ui = self.terminal_ui.clone();
            Box::new(move || {
                let ui = ui.clone();
                Box::pin(async move {
                    ui.zellij.toggle_pane("context-viewer").await.unwrap();
                })
            })
        }).await?;

        Ok(())
    }

    async fn start_mcp_servers(&self) -> Result<()> {
        // Start context MCP server
        let context_server = tokio::process::Command::new("devys-mcp-context")
            .arg("--stdio")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        // Start model routing MCP server  
        let models_server = tokio::process::Command::new("devys-mcp-models")
            .arg("--stdio")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;

        // Store server handles (in real implementation, we'd manage these)
        println!("🔗 MCP servers started");
        Ok(())
    }

    async fn start_monitoring(&self) -> Result<()> {
        // Start uptime counter
        let status = self.status.clone();
        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(1));
            loop {
                interval.tick().await;
                if let Ok(mut status) = status.write().await {
                    status.uptime_seconds += 1;
                }
            }
        });

        // Start latency monitoring
        let pty_bridge = self.pty_bridge.clone();
        let status = self.status.clone();
        tokio::spawn(async move {
            let mut interval = interval(Duration::from_secs(5));
            loop {
                interval.tick().await;
                if let Ok(latency) = pty_bridge.measure_latency().await {
                    if let Ok(mut status) = status.write().await {
                        status.keystroke_latency_ms = latency;
                    }
                }
            }
        });

        Ok(())
    }

    async fn process_commands(&self, mut receiver: mpsc::UnboundedReceiver<DevysCommand>) {
        while let Some(command) = receiver.recv().await {
            if let Err(e) = self.handle_command(command).await {
                eprintln!("Error handling command: {}", e);
                if let Ok(mut status) = self.status.write().await {
                    status.error_count += 1;
                }
            } else {
                if let Ok(mut status) = self.status.write().await {
                    status.commands_processed += 1;
                }
            }
        }
    }

    async fn handle_command(&self, command: DevysCommand) -> Result<()> {
        match command {
            DevysCommand::Initialize => {
                self.initialize().await?;
            }
            DevysCommand::StartZellijSession => {
                self.terminal_ui.zellij.start_session().await?;
            }
            DevysCommand::ExecuteWorkflow { query, mode } => {
                self.execute_workflow(&query, mode).await?;
            }
            DevysCommand::ToggleGruntMode => {
                self.toggle_grunt_mode().await?;
            }
            DevysCommand::ShowStatus => {
                self.show_status().await?;
            }
            DevysCommand::RefreshContext => {
                self.claude_code.refresh_context().await?;
            }
            DevysCommand::OptimizeContext => {
                self.claude_code.optimize_context().await?;
            }
            DevysCommand::SwitchModel { model } => {
                self.claude_code.switch_model(&model).await?;
            }
            DevysCommand::Shutdown => {
                self.shutdown().await?;
            }
        }
        Ok(())
    }

    async fn execute_workflow(&self, query: &str, mode: Option<String>) -> Result<()> {
        // Update status
        {
            let mut status = self.status.write().await;
            status.mode = mode.unwrap_or_else(|| "EXECUTING".to_string());
        }

        // Execute the integrated workflow
        let result = self.claude_code.workflow_controller.execute_workflow(query).await?;

        // Update cost tracking
        {
            let mut status = self.status.write().await;
            status.total_cost_usd += result.cost;
            status.daily_cost_usd += result.cost;
            status.mode = "READY".to_string();
        }

        println!("✅ Workflow completed: {} phases, ${:.4} cost", 
            result.phases.len(), result.cost);

        Ok(())
    }

    async fn toggle_grunt_mode(&self) -> Result<()> {
        let status = self.status.read().await;
        let is_grunt_active = status.active_agents.contains(&"grunt".to_string());
        drop(status);

        if is_grunt_active {
            // Disable grunt mode
            let mut status = self.status.write().await;
            status.active_agents.retain(|agent| agent != "grunt");
            println!("🤖 Grunt mode disabled");
        } else {
            // Enable grunt mode
            let mut status = self.status.write().await;
            status.active_agents.push("grunt".to_string());
            println!("🤖 Grunt mode enabled");
        }

        Ok(())
    }

    async fn show_status(&self) -> Result<()> {
        let status = self.status.read().await;
        
        println!("\n📊 Devys Status:");
        println!("  Mode: {}", status.mode);
        println!("  Uptime: {}s", status.uptime_seconds);
        println!("  Keystroke Latency: {:.1}ms", status.keystroke_latency_ms);
        println!("  Commands Processed: {}", status.commands_processed);
        println!("  Total Cost: ${:.4}", status.total_cost_usd);
        println!("  Daily Cost: ${:.4}", status.daily_cost_usd);
        println!("  Errors: {}", status.error_count);
        println!("  Active Agents: {}", status.active_agents.join(", "));

        Ok(())
    }

    async fn shutdown(&self) -> Result<()> {
        println!("🛑 Shutting down Devys Core...");
        
        // Cleanup terminal UI
        self.terminal_ui.cleanup().await?;
        
        // Disconnect PTY bridge
        self.pty_bridge.disconnect().await?;
        
        // Shutdown Claude Code integration
        self.claude_code.shutdown().await?;

        println!("✅ Devys Core shutdown complete");
        std::process::exit(0);
    }

    pub fn get_command_sender(&self) -> mpsc::UnboundedSender<DevysCommand> {
        self.command_channel.clone()
    }

    pub async fn get_status(&self) -> DevysStatus {
        self.status.read().await.clone()
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Load configuration
    let config = DevysCoreConfig::default();
    
    // Create and initialize Devys Core
    let devys = DevysCore::new(config).await?;
    let command_sender = devys.get_command_sender();

    // Initialize the system
    command_sender.send(DevysCommand::Initialize)?;

    // Start Zellij session
    command_sender.send(DevysCommand::StartZellijSession)?;

    // Setup signal handlers
    let command_sender_clone = command_sender.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.expect("Failed to listen for ctrl-c");
        command_sender_clone.send(DevysCommand::Shutdown).unwrap();
    });

    // Main event loop
    let mut stdin = tokio::io::stdin();
    let mut buffer = String::new();

    loop {
        println!("\nDevys> ");
        buffer.clear();
        
        use tokio::io::AsyncBufReadExt;
        let mut reader = tokio::io::BufReader::new(&mut stdin);
        
        match reader.read_line(&mut buffer).await {
            Ok(0) => break, // EOF
            Ok(_) => {
                let input = buffer.trim();
                
                match input {
                    "quit" | "exit" | "q" => {
                        command_sender.send(DevysCommand::Shutdown)?;
                        break;
                    }
                    "status" => {
                        command_sender.send(DevysCommand::ShowStatus)?;
                    }
                    "grunt" => {
                        command_sender.send(DevysCommand::ToggleGruntMode)?;
                    }
                    "refresh" => {
                        command_sender.send(DevysCommand::RefreshContext)?;
                    }
                    "optimize" => {
                        command_sender.send(DevysCommand::OptimizeContext)?;
                    }
                    input if input.starts_with("plan ") => {
                        let query = &input[5..];
                        command_sender.send(DevysCommand::ExecuteWorkflow {
                            query: query.to_string(),
                            mode: Some("PLAN".to_string()),
                        })?;
                    }
                    input if input.starts_with("model ") => {
                        let model = &input[6..];
                        command_sender.send(DevysCommand::SwitchModel {
                            model: model.to_string(),
                        })?;
                    }
                    "" => continue,
                    _ => {
                        // Default: execute as workflow query
                        command_sender.send(DevysCommand::ExecuteWorkflow {
                            query: input.to_string(),
                            mode: None,
                        })?;
                    }
                }
            }
            Err(e) => {
                eprintln!("Error reading input: {}", e);
                break;
            }
        }
    }

    Ok(())
}

impl Clone for DevysCore {
    fn clone(&self) -> Self {
        Self {
            config: self.config.clone(),
            claude_code: self.claude_code.clone(),
            terminal_ui: self.terminal_ui.clone(),
            pty_bridge: self.pty_bridge.clone(),
            command_channel: self.command_channel.clone(),
            status: self.status.clone(),
        }
    }
}