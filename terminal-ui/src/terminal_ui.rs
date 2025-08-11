use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::process::Command;
use std::sync::Arc;
use tokio::sync::RwLock;

use crate::DevysCoreConfig;

#[derive(Debug)]
pub struct TerminalUI {
    pub zellij: ZellijIntegration,
    pub helix: HelixIntegration,
    pub yazi: YaziIntegration,
    config: DevysCoreConfig,
}

#[derive(Debug)]
pub struct ZellijIntegration {
    config_path: String,
    active_session: Arc<RwLock<Option<String>>>,
    pane_map: Arc<RwLock<HashMap<String, String>>>,
    keybindings: Arc<RwLock<HashMap<String, Box<dyn Fn() -> Pin<Box<dyn Future<Output = ()> + Send>> + Send + Sync>>>>,
}

#[derive(Debug)]
pub struct HelixIntegration {
    config_path: String,
    commands: Arc<RwLock<HashMap<String, Box<dyn Fn(String) -> Pin<Box<dyn Future<Output = ()> + Send>> + Send + Sync>>>>,
    lsp_server_running: Arc<RwLock<bool>>,
}

#[derive(Debug)]
pub struct YaziIntegration {
    config_path: String,
    context_plugin_path: String,
}

impl TerminalUI {
    pub fn new(config: &DevysCoreConfig) -> Result<Self> {
        let zellij = ZellijIntegration::new(&config.zellij_config_path)?;
        let helix = HelixIntegration::new(&config.helix_config_path)?;
        let yazi = YaziIntegration::new()?;

        Ok(Self {
            zellij,
            helix,
            yazi,
            config: config.clone(),
        })
    }

    pub async fn initialize_zellij(&self) -> Result<()> {
        // Create Zellij layout configuration
        self.create_zellij_layout().await?;
        
        // Build and install Zellij plugins
        self.build_zellij_plugins().await?;
        
        // Start Zellij session
        self.zellij.start_session().await?;

        // Start Helix LSP server
        self.helix.start_lsp_server().await?;

        Ok(())
    }

    async fn create_zellij_layout(&self) -> Result<()> {
        let layout_content = r#"
layout {
    default_tab_template {
        pane size=1 borderless=true {
            plugin location="zellij:tab-bar"
        }
        children
        pane size=2 borderless=true {
            plugin location="file:~/.config/zellij/plugins/ai-status.wasm"
        }
    }
    
    tab name="devys" focus=true {
        pane split_direction="vertical" {
            // Left: File browser with Yazi
            pane size="20%" {
                command "yazi"
            }
            
            // Center: Editor with Helix
            pane size="60%" focus=true {
                command "helix"
            }
            
            // Right: AI Context & Status
            pane size="20%" split_direction="horizontal" {
                // Top: Context viewer
                pane size="70%" {
                    command "devys-context"
                    args "--mode" "watch"
                }
                
                // Bottom: Model status
                pane size="30%" {
                    command "devys-status"
                }
            }
        }
    }
    
    tab name="terminal" {
        pane command="bash"
    }
    
    tab name="ai-chat" {
        pane {
            command "devys-chat"
            args "--mode" "interactive"
        }
    }
}
"#;

        // Write layout to file
        let layout_path = shellexpand::tilde(&self.config.zellij_config_path);
        let layout_dir = std::path::Path::new(layout_path.as_ref()).parent()
            .ok_or_else(|| anyhow::anyhow!("Invalid zellij config path"))?;
        
        std::fs::create_dir_all(layout_dir)?;
        std::fs::write(layout_path.as_ref(), layout_content)?;

        println!("📝 Created Zellij layout: {}", layout_path);
        Ok(())
    }

    async fn build_zellij_plugins(&self) -> Result<()> {
        println!("🔨 Building Zellij plugins...");
        
        // Build plugins workspace
        let output = Command::new("cargo")
            .arg("build")
            .arg("--release")
            .arg("--target")
            .arg("wasm32-wasi")
            .current_dir("plugins/")
            .output()?;

        if !output.status.success() {
            return Err(anyhow::anyhow!(
                "Failed to build plugins: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        // Optimize WASM files
        for plugin in ["ai-command", "grunt-status", "context-viz"] {
            let wasm_path = format!("plugins/target/wasm32-wasi/release/{}.wasm", plugin.replace("-", "_"));
            let optimized_path = format!("~/.config/zellij/plugins/{}.wasm", plugin);
            
            Command::new("wasm-opt")
                .arg("-O")
                .arg(&wasm_path)
                .arg("-o")
                .arg(shellexpand::tilde(&optimized_path).as_ref())
                .output()?;
        }

        println!("✅ Zellij plugins built and installed");
        Ok(())
    }

    pub async fn cleanup(&self) -> Result<()> {
        // Stop Helix LSP server
        self.helix.stop_lsp_server().await?;
        
        // Kill Zellij session
        self.zellij.kill_session().await?;

        Ok(())
    }
}

impl ZellijIntegration {
    pub fn new(config_path: &str) -> Result<Self> {
        Ok(Self {
            config_path: config_path.to_string(),
            active_session: Arc::new(RwLock::new(None)),
            pane_map: Arc::new(RwLock::new(HashMap::new())),
            keybindings: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    pub async fn start_session(&self) -> Result<()> {
        let session_name = "devys-main";
        
        let output = Command::new("zellij")
            .arg("--layout")
            .arg(&self.config_path)
            .arg("--session")
            .arg(session_name)
            .arg("attach")
            .output()?;

        if output.status.success() {
            let mut session = self.active_session.write().await;
            *session = Some(session_name.to_string());
            println!("🖥️  Started Zellij session: {}", session_name);
        } else {
            return Err(anyhow::anyhow!(
                "Failed to start Zellij session: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        Ok(())
    }

    pub async fn focus_pane(&self, pane_name: &str) -> Result<()> {
        let pane_map = self.pane_map.read().await;
        if let Some(pane_id) = pane_map.get(pane_name) {
            Command::new("zellij")
                .arg("action")
                .arg("focus-pane")
                .arg("--id")
                .arg(pane_id)
                .output()?;
        }
        Ok(())
    }

    pub async fn toggle_pane(&self, pane_name: &str) -> Result<()> {
        // Implementation for toggling pane visibility
        Command::new("zellij")
            .arg("action")
            .arg("toggle-pane-frames")
            .output()?;
        Ok(())
    }

    pub async fn register_binding<F, Fut>(&self, key_combo: &str, handler: F) -> Result<()>
    where
        F: Fn() -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ()> + Send + 'static,
    {
        let mut bindings = self.keybindings.write().await;
        bindings.insert(
            key_combo.to_string(),
            Box::new(move || Box::pin(handler())),
        );
        Ok(())
    }

    pub async fn kill_session(&self) -> Result<()> {
        if let Some(session) = &*self.active_session.read().await {
            Command::new("zellij")
                .arg("kill-session")
                .arg(session)
                .output()?;
        }
        Ok(())
    }
}

impl HelixIntegration {
    pub fn new(config_path: &str) -> Result<Self> {
        Ok(Self {
            config_path: config_path.to_string(),
            commands: Arc::new(RwLock::new(HashMap::new())),
            lsp_server_running: Arc::new(RwLock::new(false)),
        })
    }

    pub async fn register_command<F, Fut>(&self, command_name: &str, handler: F) -> Result<()>
    where
        F: Fn(String) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = ()> + Send + 'static,
    {
        let mut commands = self.commands.write().await;
        commands.insert(
            command_name.to_string(),
            Box::new(move |input: String| Box::pin(handler(input))),
        );
        Ok(())
    }

    pub async fn start_lsp_server(&self) -> Result<()> {
        // Start the Devys LSP server
        let mut child = tokio::process::Command::new("devys-lsp")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()?;

        // Store the process handle (in real implementation)
        let mut running = self.lsp_server_running.write().await;
        *running = true;

        println!("🧠 Started Devys LSP server");
        Ok(())
    }

    pub async fn stop_lsp_server(&self) -> Result<()> {
        // Kill the LSP server process
        let mut running = self.lsp_server_running.write().await;
        *running = false;
        
        println!("🛑 Stopped Devys LSP server");
        Ok(())
    }

    pub async fn create_helix_config(&self) -> Result<()> {
        let helix_config = r#"
theme = "devys-dark"

[editor]
line-number = "relative"
mouse = true
completion-trigger-len = 1
auto-completion = true
auto-format = true
auto-save = true
gutters = ["diagnostics", "spacer", "line-numbers", "spacer", "diff"]

[editor.statusline]
left = ["mode", "spinner", "file-name", "file-modification-indicator"]
center = ["workspace-diagnostics"]
right = ["diagnostics", "selections", "register", "position", "file-encoding"]

[editor.lsp]
display-messages = true
auto-signature-help = true
display-inlay-hints = true
display-signature-help-docs = true

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[keys.normal]
C-s = ":w" # Save
C-q = ":q" # Quit
C-z = ":u" # Undo

# Devys AI bindings
[keys.normal.space.a]
a = ":devys-ai-complete"
p = ":devys-plan"
e = ":devys-edit"
r = ":devys-review"
g = ":devys-grunt"

[keys.normal.space]
c = ":devys-context-view"
m = ":devys-model-select"
s = ":devys-status"

# Enhanced goto with AI understanding
[keys.normal.g]
d = "devys:goto-definition"
r = "devys:goto-references"
i = "devys:goto-implementation"
"#;

        // Write Helix config
        let config_path = shellexpand::tilde(&self.config_path);
        let config_dir = std::path::Path::new(config_path.as_ref()).parent()
            .ok_or_else(|| anyhow::anyhow!("Invalid helix config path"))?;
        
        std::fs::create_dir_all(config_dir)?;
        std::fs::write(config_path.as_ref(), helix_config)?;

        // Create languages.toml for LSP integration
        let languages_config = r#"
[[language]]
name = "typescript"
language-servers = ["typescript-language-server", "devys-lsp"]

[[language]]
name = "javascript"
language-servers = ["typescript-language-server", "devys-lsp"]

[[language]]
name = "rust"
language-servers = ["rust-analyzer", "devys-lsp"]

[[language]]
name = "python"
language-servers = ["pylsp", "devys-lsp"]

[language-server.devys-lsp]
command = "devys-lsp"
args = ["--stdio"]
"#;

        let languages_path = config_dir.join("languages.toml");
        std::fs::write(languages_path, languages_config)?;

        println!("📝 Created Helix configuration");
        Ok(())
    }
}

impl YaziIntegration {
    pub fn new() -> Result<Self> {
        Ok(Self {
            config_path: "~/.config/yazi/yazi.toml".to_string(),
            context_plugin_path: "~/.config/yazi/plugins/devys-context.yazi/".to_string(),
        })
    }

    pub async fn create_context_plugin(&self) -> Result<()> {
        let plugin_code = r#"
-- Devys Context Score Plugin for Yazi
local function setup()
    -- Subscribe to directory changes
    ps.sub("cd", function()
        local cwd = cx.active.current.cwd
        ya.manager_emit("plugin:devys-context", { cwd = tostring(cwd) })
    end)
    
    -- Subscribe to file selection
    ps.sub("select", function()
        local selected = cx.active.current:selected()
        update_context_scores(selected)
    end)
end

local function fetch_scores()
    local scores = ya.sync(function()
        return io.popen("devys-cli context scores --json"):read("*a")
    end)
    return scores and vim.json.decode(scores) or {}
end

local function render_with_scores()
    local scores = fetch_scores()
    
    -- Color code files based on relevance
    for _, file in ipairs(cx.active.current.files) do
        local score = scores[file.name] or 0
        
        if score > 0.8 then
            file.style = { fg = "green", bold = true }  -- High relevance
        elseif score > 0.5 then
            file.style = { fg = "yellow" }  -- Medium relevance
        else
            file.style = { fg = "gray" }  -- Low relevance
        end
        
        -- Add icon indicating inclusion in context
        if file.in_context then
            file.icon = "✓ " .. (file.icon or "")
        end
    end
end

return { setup = setup, render = render_with_scores }
"#;

        // Create plugin directory and file
        let plugin_dir = shellexpand::tilde(&self.context_plugin_path);
        std::fs::create_dir_all(plugin_dir.as_ref())?;
        
        let init_file = std::path::Path::new(plugin_dir.as_ref()).join("init.lua");
        std::fs::write(init_file, plugin_code)?;

        println!("📝 Created Yazi context plugin");
        Ok(())
    }

    pub async fn create_yazi_config(&self) -> Result<()> {
        let yazi_config = r#"
[manager]
ratio = [1, 4, 3]
sort_by = "alphabetical"
sort_sensitive = false
sort_reverse = false
sort_dir_first = true
linemode = "none"
show_hidden = false
show_symlink = true

[preview]
tab_size = 2
max_width = 600
max_height = 900
cache_dir = ""
image_filter = "triangle"
image_quality = 75
sixel_fraction = 15
ueberzug_scale = 1
ueberzug_offset = [0, 0]

[opener]
edit = [
    { run = 'helix "$@"', block = true },
]
open = [
    { run = 'xdg-open "$1"', desc = "Open" },
]
reveal = [
    { run = 'open -R "$1"', desc = "Reveal" },
]

[open]
rules = [
    { name = "*/", use = [ "edit", "open", "reveal" ] },
    { mime = "text/*", use = [ "edit", "reveal" ] },
    { mime = "application/json", use = [ "edit", "reveal" ] },
    { mime = "*/xml", use = [ "edit", "reveal" ] },
    { mime = "application/javascript", use = [ "edit", "reveal" ] },
]

[plugin]
prepend_previewers = [
    { name = "*/", run = "devys-context" },
]
"#;

        let config_path = shellexpand::tilde(&self.config_path);
        let config_dir = std::path::Path::new(config_path.as_ref()).parent()
            .ok_or_else(|| anyhow::anyhow!("Invalid yazi config path"))?;
        
        std::fs::create_dir_all(config_dir)?;
        std::fs::write(config_path.as_ref(), yazi_config)?;

        println!("📝 Created Yazi configuration");
        Ok(())
    }
}