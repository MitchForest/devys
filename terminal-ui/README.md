# Devys Phase 4: Terminal UI Integration

Complete terminal-first AI development environment with Zellij plugins, Helix LSP server, Context Builder TUI, and Claude Code SDK integration.

## 🚀 Overview

Phase 4 brings together all infrastructure from Phases 1-3 into a fully functional development environment with:

- **Terminal-First Interface**: Zellij, Helix, Yazi integration
- **AI Command Palette**: WebAssembly plugins for real-time AI interaction  
- **Grunt Mode**: Delegate repetitive tasks to local/free models
- **Context Visualization**: Real-time context management with TUI
- **<50ms Latency**: Maintained from Phase 1 through PTY bridge

## 📁 Project Structure

```
terminal-ui/
├── src/
│   ├── main.rs                 # Main DevysCore orchestrator
│   ├── claude_integration.rs   # Claude Code SDK integration
│   ├── terminal_ui.rs          # Terminal UI management
│   └── pty_bridge.rs          # WebSocket PTY bridge
├── plugins/
│   ├── ai-command/            # AI Command Palette plugin (WASM)
│   ├── grunt-status/          # Background task monitoring (WASM)  
│   └── context-viz/           # Context visualizer (WASM)
├── lsp/
│   └── src/main.rs            # Helix LSP server for AI completions
├── tui/
│   └── src/main.rs            # Context Builder TUI with ratatui
├── config/
│   ├── zellij/                # Zellij layout and keybindings
│   ├── helix/                 # Helix editor configuration
│   └── shell/                 # Shell integration scripts
└── scripts/
    └── install.sh             # Complete installation script
```

## 🔧 Components

### 1. Zellij Plugins (WebAssembly)

**AI Command Palette** (`plugins/ai-command/`)
- Ctrl+A to open command palette
- Real-time workflow status display
- WebSocket connection to Control Plane
- Plan, Edit, Review, Grunt command shortcuts

**Grunt Status Monitor** (`plugins/grunt-status/`)
- Background task queue visualization
- Model status and availability
- Cost tracking with daily limits
- Real-time progress indicators

**Context Visualizer** (`plugins/context-viz/`)
- File relevance scores and inclusion status
- Multiple view modes (List, Tree, Heatmap, Dependencies)
- Token usage optimization
- Interactive file selection

### 2. Helix LSP Server

**AI-Powered Completions** (`lsp/src/main.rs`)
- Integration with Control Plane for AI completions
- Code actions (explain, refactor, optimize)
- Hover information with AI explanations
- Custom commands for AI workflows

**Features:**
- Real-time AI completions
- Code action suggestions
- Symbol explanations
- Multi-language support

### 3. Context Builder TUI

**Interactive Context Management** (`tui/src/main.rs`)
- Visual file selection with relevance scores
- Token usage tracking and optimization
- Model recommendations based on context size
- Real-time updates via API

**View Modes:**
- List: File list with scores and inclusion status
- Details: Selected file information and symbols
- Tree: Directory tree visualization

### 4. DevysCore Orchestrator

**Main Integration Hub** (`src/main.rs`)
- Coordinates all terminal UI components
- Manages workflow execution (Plan → Edit → Review → Grunt)
- PTY bridge for <50ms latency
- Command processing and routing

**Key Features:**
- WebSocket-based real-time updates
- Keystroke latency monitoring
- Cost tracking and optimization
- Error recovery and retry logic

## 🎯 Key Features

### Terminal-First Design
- Zellij session manager with custom layout
- Helix editor with AI-powered LSP
- Yazi file manager with context scores
- Seamless integration between tools

### AI Model Routing
```typescript
// Intelligent model selection based on task complexity
plan: 'gemini-2.0-flash-thinking',    // 1M context for planning
edit: 'claude-3-5-sonnet',            // Best code generation
review: 'o1',                         // Deep reasoning
grunt: 'ollama:qwen2.5-coder:14b'     // Local for simple tasks
```

### Grunt Mode Innovation
- 70% of tasks handled by free/local models
- Background task queue with prioritization
- Smart routing based on task complexity
- Cost optimization with daily limits

### Context Intelligence
- AI-powered file selection
- Relevance scoring with co-occurrence matrix
- Token optimization for different models
- Working set boost for recently accessed files

## ⚡ Performance Targets

- **Terminal rendering**: <16ms per frame (60 FPS)
- **Keystroke latency**: <50ms (maintained from Phase 1)
- **Command execution**: <100ms for local operations
- **Context building**: <500ms for average project
- **WebSocket latency**: <10ms local, <50ms remote

## 🎮 Keybindings

### Global (Zellij)
- `Alt+a`: Focus AI chat pane
- `Alt+c`: Toggle context viewer
- `Alt+e`: Focus editor
- `Alt+f`: Focus file browser
- `Alt+t`: Focus terminal

### AI Commands (Helix)
- `Space+a+p`: Plan with AI
- `Space+a+e`: Edit with AI
- `Space+a+r`: Review with AI
- `Space+a+g`: Grunt tasks
- `Space+c`: Context view
- `Space+m`: Model select

### Shell Integration
- `Ctrl+Space`: AI command palette (FZF)
- `Alt+a`: AI completion
- `Alt+p`: Plan current
- `Alt+e`: Edit current
- `Alt+r`: Review current

## 📦 Installation

### Automated Installation
```bash
cd terminal-ui
./scripts/install.sh
```

### Manual Installation
```bash
# Install terminal tools
cargo install zellij helix-term yazi-fm

# Build plugins
cd plugins && cargo build --release --target wasm32-wasi

# Build LSP server
cd lsp && cargo build --release

# Build Context TUI
cd tui && cargo build --release

# Build main orchestrator
cargo build --release
```

### Shell Integration
Add to your `~/.zshrc` or `~/.bashrc`:
```bash
source ~/.config/devys/devys-init.zsh  # or devys-init.bash
```

## 🔄 Workflow Integration

### Complete AI Workflow
1. **PLAN**: Generate comprehensive task breakdown (Gemini 2.0 Flash Thinking)
2. **EDIT**: Execute code changes (Claude 3.5 Sonnet)
3. **REVIEW**: Validate with deep reasoning (O1)
4. **GRUNT**: Handle routine tasks (Local Ollama models)

### Example Usage
```bash
# Start Devys
devys-core

# Execute AI workflow
plan "Add error handling to authentication module"

# Monitor in real-time via Zellij plugins
# - AI Command Palette shows progress
# - Grunt Status shows background tasks
# - Context Visualizer shows file inclusion
```

## 💰 Cost Optimization

### Model Routing Strategy
- **Free models first**: Gemini 2.0 Flash for planning
- **Local models**: Ollama for grunt work
- **Premium models**: Claude/O1 only for complex tasks
- **Daily cost limits**: Configurable spending controls

### Expected Savings
- 70% of tasks handled by free/local models
- 50% reduction in AI costs
- 40% improvement in token usage efficiency

## 🔌 Configuration

### Model Preferences
```toml
[ai]
planner_model = "gemini-2.0-flash-thinking"
editor_model = "claude-3-5-sonnet"
reviewer_model = "o1"
grunt_models = ["ollama:qwen2.5-coder:14b", "deepseek-chat"]
```

### Performance Tuning
```toml
[performance]
keystroke_latency_target = 50    # ms
websocket_timeout = 5000         # ms
cache_size_mb = 500
```

### Context Management
```toml
[context]
max_tokens = 100000
auto_select = true
cache_ttl = 3600
learning_enabled = true
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Zellij Session Manager                   │
├─────────────┬──────────────┬──────────────┬─────────────────┤
│   Helix     │   Yazi       │   AI Panel   │   Grunt Panel   │
│   Editor    │   File Mgr   │   Commands   │   Background    │
├─────────────┴──────────────┴──────────────┴─────────────────┤
│                    PTY Sidecar (Rust)                        │
├───────────────────────────────────────────────────────────────┤
│                  Control Plane (Phase 3)                     │
└───────────────────────────────────────────────────────────────┘
```

## 🧪 Testing

Run the integration test suite:
```bash
cargo test --workspace
```

Performance benchmarks:
```bash
cargo bench --workspace
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Implement changes with tests
4. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🎯 Phase 5 Preview

Future enhancements planned:
- **Tauri Desktop App**: Native performance with web technologies
- **Mobile Companion**: iOS/Android monitoring app
- **Team Collaboration**: Shared contexts and pair programming
- **Custom Agent SDK**: User-defined AI agents
- **Visual Debugging**: Terminal-based AI decision visualization

---

**Devys Phase 4: Where AI meets terminal mastery** 🚀