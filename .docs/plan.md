# AI-First Terminal IDE - Technical Specification v2

## Executive Summary

Building a modern, terminal-based IDE optimized for AI-assisted development with Claude Code, designed to work seamlessly across mobile and desktop platforms. This system combines the power of terminal-based tools with web technologies to create a responsive, efficient development environment that prioritizes AI workflows while maintaining sub-50ms keystroke responsiveness.

### Core Innovation
Unlike traditional IDEs or terminal setups, this architecture treats AI assistance and **intelligent context management** as first-class citizens. The system features a sophisticated context management layer that provides token-aware file selection, smart templates, real-time cost tracking, and automatic optimization for AI model limits. 

A key differentiator is the **multi-model AI routing** via claude-code-router, which automatically selects the optimal AI model for each task - Gemini for large-context planning, o3 for deep reasoning reviews, Claude for precise editing, DeepSeek for economy, and local Ollama for privacy-sensitive operations. This provides 60%+ cost savings while using the best tool for each job.

Context flows seamlessly into every AI interaction through dedicated workflows for agent patterns (planner, editor, reviewer) while maintaining instantaneous responsiveness through a split control/keystroke plane architecture. The system acknowledges platform realities - particularly iOS limitations - while delivering a consistent experience across devices.

## Requirements

### Functional Requirements
1. **File Management**
   - Visual file tree for repository navigation (Yazi)
   - Quick file opening and editing
   - Multi-file support with buffers

2. **Terminal Integration**
   - Multiple terminal instances/sessions
   - Full Claude Code SDK/CLI integration
   - Support for hooks and slash commands
   - Sub-agent orchestration

3. **AI Agent Patterns**
   - Planner agent for task decomposition (Gemini)
   - Editor agent for code modifications (Claude)
   - Reviewer agent for code review (o3)
   - Debugger agent for systematic debugging (DeepSeek)
   - Privacy guard for sensitive operations (Ollama)
   - Deterministic rituals via hooks
   - Automatic model selection per agent type

4. **Intelligent Context Management**
   - Interactive terminal-native context builder (TUI)
   - Real-time token counting and cost estimation
   - Smart selection modes (working set, related, semantic, test coverage)
   - Context templates for common workflows
   - Token optimization with automatic code-map fallback
   - Context history and snapshots
   - Streaming support for massive repositories
   - Model-specific token limit awareness
   - Cost tracking and warnings

5. **Document Support**
   - Markdown rendering and editing
   - Inline documentation viewing
   - README-driven development

6. **Version Control**
   - Git diff visualization (lazygit)
   - GitHub Actions integration
   - PR/issue automation via @claude

7. **Context Intelligence**
   - Intelligent repository context (RepoPrompt-style)
   - Tree-sitter based code maps
   - Function signatures, classes, interfaces tracking
   - Working set tracking (open buffers, recent diffs)
   - Automatic context suggestions based on prompt analysis
   - Context validation and dependency checking

9. **Multi-Provider AI Support**
   - Claude (Anthropic) for instruction following
   - GPT-4/o3 (OpenAI) for reasoning
   - Gemini (Google) for large context
   - DeepSeek for cost-effective tasks
   - Ollama for local privacy-first operations
   - Dynamic model switching via /model command
   - Automatic routing based on task type
   - Cost tracking and optimization

10. **Cross-Platform**
   - Desktop: Local Tauri app with native PTY
   - iOS: PWA/Tauri-Mobile as thin client to remote devbox
   - Android: PWA to remote OR Termux native
   - Consistent UX across all platforms

### Non-Functional Requirements
- Sub-50ms keystroke latency (local)
- Fast session resume (no persistent mobile background)
- Secure session management with privacy-first routing
- <100MB total application size
- Battery-efficient operation
- Predictable performance under load
- 60%+ cost reduction via intelligent model routing
- 100% local routing for sensitive data
- Automatic fallback for provider failures

## Technology Stack

### Core Architecture Split

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Control Plane** | Bun/Node.js | Session registry, auth, Claude orchestration |
| **Context Management** | Bun + TUI | Token counting, smart selection, templates, optimization |
| **Model Router** | claude-code-router | Multi-provider support, tool translation, optimal model selection |
| **Router Control** | Bun wrapper | Metrics, cost tracking, dynamic config, model optimization |
| **Keystroke Plane** | Rust Sidecar | PTY I/O, WebSocket streaming, guaranteed <50ms latency |
| **Editor** | Helix (only) | Native tree-sitter, zero-config, lightweight |
| **Multiplexer** | Zellij | Floating panes, modern UX, session management |
| **Frontend** | xterm.js | Industry standard, mobile friendly |
| **Desktop** | Tauri | Small bundles, native performance |
| **Mobile iOS** | PWA (remote-only) | Thin client to devbox |
| **Mobile Android** | PWA or Termux | Local or remote options |
| **AI Providers** | Multiple | Claude, GPT-4/o3, Gemini, DeepSeek, Ollama (local) |
| **Code Analysis** | tree-sitter | AST-based, incremental parsing |
| **File Manager** | Yazi | Terminal-native, fast navigation |
| **Context Store** | SQLite (Bun) | Session state, code maps cache, context history |

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   Client Layer                       │
├──────────────────────────────────────────────────────┤
│  Desktop (Tauri)  │  iOS (PWA)    │  Android (PWA)   │
│  [Local PTY]      │  [Remote Only] │  [Local/Remote]  │
└──────────────────┬──────────────────┬───────────────┘
                   │    WebSocket     │
                   ▼                  ▼
┌──────────────────────────────────────────────────────┐
│              Keystroke Plane (Rust)                  │
├──────────────────────────────────────────────────────┤
│  PTY Manager      │  WebSocket Server                │
│  <50ms guarantee  │  Binary protocol                 │
│  No GC pauses     │  Efficient streaming             │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│         Context Management System (Bun)              │
├──────────────────────────────────────────────────────┤
│  Context Builder  │  Token Optimizer │  Templates    │
│  Code Maps       │  History/Cache   │  Streaming    │
│  Smart Selection │  Cost Tracking   │  Validation   │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Control Plane (Bun/Node)                  │
├──────────────────────────────────────────────────────┤
│  Session Registry │  Claude Orchestr.│  Auth Service │
│  RepoPrompt Rules│  GitHub API      │  State Store  │
│  Hooks Engine    │  MCP Servers     │  Monitoring   │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Terminal Environment                      │
├──────────────────────────────────────────────────────┤
│  Zellij           │  Helix         │  Claude Code   │
│  Yazi             │  Lazygit       │  Tree-sitter   │
└──────────────────────────────────────────────────────┘
```

## Platform Strategy

### Desktop (Mac/Windows/Linux)
- **Tauri app** with embedded Rust PTY sidecar
- Local terminal sessions
- Direct filesystem access
- Native clipboard integration
- Sub-50ms guaranteed latency

### iOS (iPhone/iPad)
- **PWA or Tauri-Mobile** as thin client
- **Remote devbox required** (no local terminal possible)
- Foreground-only operation (iOS suspends background)
- Fast resume/reconnect UX
- Touch-optimized controls

### Android
- **Option A**: PWA to remote devbox (same as iOS)
- **Option B**: Termux local + web UI on localhost
- Background operation possible
- Choice based on user preference

## Detailed Implementation Plan

### Phase 1: Dual-Plane Architecture (Week 1-2)

#### 1.1 Rust PTY Sidecar (Keystroke Plane)
```rust
// pty-sidecar/src/main.rs
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, WebSocketStream};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use futures_util::{StreamExt, SinkExt};
use bytes::Bytes;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "127.0.0.1:8081";
    let listener = TcpListener::bind(&addr).await?;
    println!("PTY WebSocket server running on ws://{}", addr);
    
    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(handle_connection(stream));
    }
    
    Ok(())
}

async fn handle_connection(stream: TcpStream) {
    let ws_stream = accept_async(stream).await.expect("WebSocket handshake failed");
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // Create PTY with Zellij
    let pty_system = native_pty_system();
    let pty_pair = pty_system.openpty(PtySize {
        rows: 24,
        cols: 80,
        pixel_width: 0,
        pixel_height: 0,
    }).unwrap();
    
    let mut cmd = CommandBuilder::new("zellij");
    cmd.args(&["-s", "main"]);
    cmd.env("TERM", "xterm-256color");
    cmd.env("EDITOR", "hx");
    
    let mut child = pty_pair.slave.spawn_command(cmd).unwrap();
    let mut reader = pty_pair.master.try_clone_reader().unwrap();
    let mut writer = pty_pair.master.take_writer().unwrap();
    
    // PTY -> WebSocket (optimized for <50ms)
    let ws_sender_clone = ws_sender.clone();
    tokio::spawn(async move {
        let mut buffer = [0u8; 4096];
        loop {
            match reader.read(&mut buffer) {
                Ok(n) if n > 0 => {
                    // Direct binary send, no serialization
                    let _ = ws_sender_clone.send(Message::Binary(buffer[..n].to_vec())).await;
                }
                _ => break,
            }
        }
    });
    
    // WebSocket -> PTY
    while let Some(msg) = ws_receiver.next().await {
        if let Ok(msg) = msg {
            match msg {
                Message::Binary(data) => {
                    // Direct write, minimal processing
                    let _ = writer.write_all(&data);
                }
                Message::Text(text) => {
                    // Handle control messages (resize, etc)
                    if let Ok(control) = serde_json::from_str::<ControlMessage>(&text) {
                        match control.cmd.as_str() {
                            "resize" => {
                                pty_pair.master.resize(PtySize {
                                    rows: control.rows,
                                    cols: control.cols,
                                    pixel_width: 0,
                                    pixel_height: 0,
                                }).unwrap();
                            }
                            _ => {}
                        }
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    }
    
    let _ = child.kill();
}

#[derive(Deserialize)]
struct ControlMessage {
    cmd: String,
    rows: u16,
    cols: u16,
}
```

#### 1.2 Bun Control Plane Server
```typescript
// control-plane/server.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface Session {
  id: string;
  userId: string;
  workspace: string;
  context: RepoContext;
  createdAt: number;
}

class ControlPlaneServer {
  private db: Database;
  private sessions: Map<string, Session>;
  private contextServer: ContextServer;
  private claudeOrchestrator: ClaudeOrchestrator;
  
  constructor() {
    this.db = new Database("control.db");
    this.sessions = new Map();
    this.contextServer = new ContextServer();
    this.claudeOrchestrator = new ClaudeOrchestrator();
    
    // Start Rust PTY sidecar
    this.startPtySidecar();
  }
  
  private async startPtySidecar() {
    // Launch Rust sidecar for PTY handling
    const sidecar = Bun.spawn(["./pty-sidecar"], {
      stdout: "pipe",
      stderr: "pipe"
    });
    
    console.log("PTY sidecar started on ws://localhost:8081");
  }
  
  async createSession(userId: string, workspace: string): Promise<Session> {
    const sessionId = crypto.randomUUID();
    
    // Generate initial context
    const context = await this.contextServer.generateContext(workspace);
    
    const session: Session = {
      id: sessionId,
      userId,
      workspace,
      context,
      createdAt: Date.now()
    };
    
    this.sessions.set(sessionId, session);
    
    // Store in SQLite for persistence
    this.db.run(
      "INSERT INTO sessions (id, user_id, workspace, context) VALUES (?, ?, ?, ?)",
      [sessionId, userId, workspace, JSON.stringify(context)]
    );
    
    return session;
  }
  
  // Claude Code orchestration endpoints
  async runClaudeCommand(sessionId: string, command: string) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error("Session not found");
    
    return this.claudeOrchestrator.execute(command, session.context);
  }
  
  // RepoPrompt-style context management
  async updateContext(sessionId: string, trigger: string) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    
    // Incremental context update based on trigger
    session.context = await this.contextServer.updateContext(
      session.workspace,
      session.context,
      trigger
    );
  }
}

// Start control plane
const server = Bun.serve({
  port: 3000,
  
  fetch(req, server) {
    const url = new URL(req.url);
    
    // Control plane APIs
    if (url.pathname.startsWith("/api/")) {
      return handleApiRequest(req);
    }
    
    // Serve frontend
    if (url.pathname === "/") {
      return new Response(Bun.file("public/index.html"));
    }
    
    return new Response("Not Found", { status: 404 });
  }
});

console.log(`Control plane running on http://localhost:${server.port}`);
```

### Phase 2: Context Server & RepoPrompt (Week 2-3)

#### 2.1 Tree-sitter Context Server
```typescript
// context/context-server.ts
import Parser from 'tree-sitter';
import { Database } from "bun:sqlite";

interface CodeMap {
  functions: Symbol[];
  classes: Symbol[];
  interfaces: Symbol[];
  types: Symbol[];
  imports: Dependency[];
  workingSet: WorkingFile[];
}

interface RepoContext {
  codeMap: CodeMap;
  recentChanges: Change[];
  activeFiles: string[];
  failingTests: Test[];
  openPRs: PullRequest[];
}

class ContextServer {
  private parsers: Map<string, Parser>;
  private cache: Database;
  private fileWatcher: FSWatcher;
  
  constructor() {
    this.parsers = new Map();
    this.cache = new Database("context-cache.db");
    this.initializeParsers();
    this.setupIncrementalUpdates();
  }
  
  async generateContext(workspace: string): Promise<RepoContext> {
    // Check cache first
    const cached = this.getCachedContext(workspace);
    if (cached && !this.isStale(cached)) {
      return cached;
    }
    
    // Generate fresh code map
    const codeMap = await this.generateCodeMap(workspace);
    
    // Apply RepoPrompt selection rules
    const selectedSymbols = this.applySelectionRules(codeMap, {
      maxSymbols: 100,
      prioritize: ['recent', 'referenced', 'complex'],
      includeTests: false
    });
    
    // Build complete context
    const context: RepoContext = {
      codeMap: selectedSymbols,
      recentChanges: await this.getRecentChanges(workspace),
      activeFiles: await this.getActiveFiles(),
      failingTests: await this.getFailingTests(workspace),
      openPRs: await this.getOpenPRs()
    };
    
    // Cache for performance
    this.cacheContext(workspace, context);
    
    return context;
  }
  
  private async generateCodeMap(workspace: string): Promise<CodeMap> {
    const files = await this.findSourceFiles(workspace);
    const map: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: [],
      workingSet: []
    };
    
    // Parse in parallel for speed
    const parsePromises = files.map(async (file) => {
      const content = await Bun.file(file).text();
      const lang = this.detectLanguage(file);
      const parser = this.parsers.get(lang);
      
      if (!parser) return null;
      
      const tree = parser.parse(content);
      return this.extractSymbols(tree, file, lang);
    });
    
    const results = await Promise.all(parsePromises);
    
    // Merge results
    for (const symbols of results) {
      if (!symbols) continue;
      map.functions.push(...symbols.functions);
      map.classes.push(...symbols.classes);
      map.interfaces.push(...symbols.interfaces);
      map.types.push(...symbols.types);
    }
    
    // Calculate importance scores
    this.rankSymbols(map);
    
    return map;
  }
  
  private applySelectionRules(codeMap: CodeMap, rules: SelectionRules): CodeMap {
    // RepoPrompt-style intelligent selection
    const selected: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: codeMap.imports,
      workingSet: codeMap.workingSet
    };
    
    // Priority 1: Recently modified symbols
    const recentSymbols = this.getRecentlyModified(codeMap);
    
    // Priority 2: Highly referenced symbols
    const referencedSymbols = this.getHighlyReferenced(codeMap);
    
    // Priority 3: Complex/important symbols
    const complexSymbols = this.getComplexSymbols(codeMap);
    
    // Merge with deduplication
    const allSymbols = [...recentSymbols, ...referencedSymbols, ...complexSymbols];
    const unique = this.deduplicateSymbols(allSymbols);
    
    // Take top N based on rules
    const topSymbols = unique.slice(0, rules.maxSymbols);
    
    // Distribute back to categories
    for (const symbol of topSymbols) {
      switch (symbol.type) {
        case 'function': selected.functions.push(symbol); break;
        case 'class': selected.classes.push(symbol); break;
        case 'interface': selected.interfaces.push(symbol); break;
        case 'type': selected.types.push(symbol); break;
      }
    }
    
    return selected;
  }
  
  // Incremental updates for performance
  private setupIncrementalUpdates() {
    this.fileWatcher = Bun.file("./").watch((event, filename) => {
      // Debounced incremental parsing
      this.scheduleIncrementalUpdate(filename);
    });
  }
  
  private scheduleIncrementalUpdate = debounce((filename: string) => {
    // Parse only the changed file
    this.updateSingleFile(filename);
  }, 100);
}
```

### Phase 3: Context Management System (Week 3-4)

#### 3.1 Terminal-Native Context Builder
```typescript
// context/context-builder.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface ContextSelection {
  files: FileInfo[];
  tokens: number;
  model: string;
  percentOfLimit: number;
  estimatedCost: number;
}

class ContextBuilder {
  private tokenCounter: TokenCounter;
  private codeMap: CodeMap;
  private workingSet: Set<string>;
  private db: Database;
  
  constructor() {
    this.db = new Database("context.db");
    this.tokenCounter = new TokenCounter();
    this.initializeUI();
  }
  
  async launch(options?: LaunchOptions) {
    // Launch in Zellij floating pane with TUI
    const result = await # AI-First Terminal IDE - Technical Specification v2

## Executive Summary

Building a modern, terminal-based IDE optimized for AI-assisted development with Claude Code, designed to work seamlessly across mobile and desktop platforms. This system combines the power of terminal-based tools with web technologies to create a responsive, efficient development environment that prioritizes AI workflows while maintaining sub-50ms keystroke responsiveness.

### Core Innovation
Unlike traditional IDEs or terminal setups, this architecture treats AI assistance as a first-class citizen, with dedicated workflows for agent patterns (planner, editor, reviewer) while maintaining instantaneous responsiveness through a split control/keystroke plane architecture. The system acknowledges platform realities - particularly iOS limitations - while delivering a consistent experience across devices.

## Requirements

### Functional Requirements
1. **File Management**
   - Visual file tree for repository navigation (Yazi)
   - Quick file opening and editing
   - Multi-file support with buffers

2. **Terminal Integration**
   - Multiple terminal instances/sessions
   - Full Claude Code SDK/CLI integration
   - Support for hooks and slash commands
   - Sub-agent orchestration

3. **AI Agent Patterns**
   - Planner agent for task decomposition
   - Editor agent for code modifications
   - Reviewer agent for code review
   - Deterministic rituals via hooks

4. **Document Support**
   - Markdown rendering and editing
   - Inline documentation viewing
   - README-driven development

5. **Version Control**
   - Git diff visualization (lazygit)
   - GitHub Actions integration
   - PR/issue automation via @claude

6. **Context Management**
   - Intelligent repository context (RepoPrompt-style)
   - Tree-sitter based code maps
   - Function signatures, classes, interfaces tracking
   - Working set tracking (open buffers, recent diffs)

7. **Cross-Platform**
   - Desktop: Local Tauri app with native PTY
   - iOS: PWA/Tauri-Mobile as thin client to remote devbox
   - Android: PWA to remote OR Termux native
   - Consistent UX across all platforms

### Non-Functional Requirements
- Sub-50ms keystroke latency (local)
- Fast session resume (no persistent mobile background)
- Secure session management
- <100MB total application size
- Battery-efficient operation
- Predictable performance under load

## Technology Stack

### Core Architecture Split

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Control Plane** | Bun/Node.js | Session registry, auth, context service, Claude orchestration |
| **Keystroke Plane** | Rust Sidecar | PTY I/O, WebSocket streaming, guaranteed <50ms latency |
| **Editor** | Helix (only) | Native tree-sitter, zero-config, lightweight |
| **Multiplexer** | Zellij | Floating panes, modern UX, session management |
| **Frontend** | xterm.js | Industry standard, mobile friendly |
| **Desktop** | Tauri | Small bundles, native performance |
| **Mobile iOS** | PWA (remote-only) | Thin client to devbox |
| **Mobile Android** | PWA or Termux | Local or remote options |
| **AI Integration** | Claude Code CLI/SDK | Interactive + batch orchestration |
| **Code Analysis** | tree-sitter | AST-based, incremental parsing |
| **File Manager** | Yazi | Terminal-native, fast navigation |
| **Context Store** | SQLite (Bun) | Session state, code maps cache |

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   Client Layer                       │
├──────────────────────────────────────────────────────┤
│  Desktop (Tauri)  │  iOS (PWA)    │  Android (PWA)   │
│  [Local PTY]      │  [Remote Only] │  [Local/Remote]  │
└──────────────────┬──────────────────┬───────────────┘
                   │    WebSocket     │
                   ▼                  ▼
┌──────────────────────────────────────────────────────┐
│              Keystroke Plane (Rust)                  │
├──────────────────────────────────────────────────────┤
│  PTY Manager      │  WebSocket Server                │
│  <50ms guarantee  │  Binary protocol                 │
│  No GC pauses     │  Efficient streaming             │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Control Plane (Bun/Node)                  │
├──────────────────────────────────────────────────────┤
│  Session Registry │  Context Server  │  Auth Service │
│  Claude Orchestr. │  RepoPrompt Rules│  GitHub API   │
│  Hooks Engine     │  Code Map Cache  │  State Store  │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Terminal Environment                      │
├──────────────────────────────────────────────────────┤
│  Zellij           │  Helix         │  Claude Code   │
│  Yazi             │  Lazygit       │  Tree-sitter   │
└──────────────────────────────────────────────────────┘
```

## Platform Strategy

### Desktop (Mac/Windows/Linux)
- **Tauri app** with embedded Rust PTY sidecar
- Local terminal sessions
- Direct filesystem access
- Native clipboard integration
- Sub-50ms guaranteed latency

### iOS (iPhone/iPad)
- **PWA or Tauri-Mobile** as thin client
- **Remote devbox required** (no local terminal possible)
- Foreground-only operation (iOS suspends background)
- Fast resume/reconnect UX
- Touch-optimized controls

### Android
- **Option A**: PWA to remote devbox (same as iOS)
- **Option B**: Termux local + web UI on localhost
- Background operation possible
- Choice based on user preference

## Detailed Implementation Plan

### Phase 1: Dual-Plane Architecture (Week 1-2)

#### 1.1 Rust PTY Sidecar (Keystroke Plane)
```rust
// pty-sidecar/src/main.rs
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, WebSocketStream};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use futures_util::{StreamExt, SinkExt};
use bytes::Bytes;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "127.0.0.1:8081";
    let listener = TcpListener::bind(&addr).await?;
    println!("PTY WebSocket server running on ws://{}", addr);
    
    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(handle_connection(stream));
    }
    
    Ok(())
}

async fn handle_connection(stream: TcpStream) {
    let ws_stream = accept_async(stream).await.expect("WebSocket handshake failed");
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // Create PTY with Zellij
    let pty_system = native_pty_system();
    let pty_pair = pty_system.openpty(PtySize {
        rows: 24,
        cols: 80,
        pixel_width: 0,
        pixel_height: 0,
    }).unwrap();
    
    let mut cmd = CommandBuilder::new("zellij");
    cmd.args(&["-s", "main"]);
    cmd.env("TERM", "xterm-256color");
    cmd.env("EDITOR", "hx");
    
    let mut child = pty_pair.slave.spawn_command(cmd).unwrap();
    let mut reader = pty_pair.master.try_clone_reader().unwrap();
    let mut writer = pty_pair.master.take_writer().unwrap();
    
    // PTY -> WebSocket (optimized for <50ms)
    let ws_sender_clone = ws_sender.clone();
    tokio::spawn(async move {
        let mut buffer = [0u8; 4096];
        loop {
            match reader.read(&mut buffer) {
                Ok(n) if n > 0 => {
                    // Direct binary send, no serialization
                    let _ = ws_sender_clone.send(Message::Binary(buffer[..n].to_vec())).await;
                }
                _ => break,
            }
        }
    });
    
    // WebSocket -> PTY
    while let Some(msg) = ws_receiver.next().await {
        if let Ok(msg) = msg {
            match msg {
                Message::Binary(data) => {
                    // Direct write, minimal processing
                    let _ = writer.write_all(&data);
                }
                Message::Text(text) => {
                    // Handle control messages (resize, etc)
                    if let Ok(control) = serde_json::from_str::<ControlMessage>(&text) {
                        match control.cmd.as_str() {
                            "resize" => {
                                pty_pair.master.resize(PtySize {
                                    rows: control.rows,
                                    cols: control.cols,
                                    pixel_width: 0,
                                    pixel_height: 0,
                                }).unwrap();
                            }
                            _ => {}
                        }
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    }
    
    let _ = child.kill();
}

#[derive(Deserialize)]
struct ControlMessage {
    cmd: String,
    rows: u16,
    cols: u16,
}
```

#### 1.2 Bun Control Plane Server
```typescript
// control-plane/server.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface Session {
  id: string;
  userId: string;
  workspace: string;
  context: RepoContext;
  createdAt: number;
}

class ControlPlaneServer {
  private db: Database;
  private sessions: Map<string, Session>;
  private contextServer: ContextServer;
  private claudeOrchestrator: ClaudeOrchestrator;
  
  constructor() {
    this.db = new Database("control.db");
    this.sessions = new Map();
    this.contextServer = new ContextServer();
    this.claudeOrchestrator = new ClaudeOrchestrator();
    
    // Start Rust PTY sidecar
    this.startPtySidecar();
  }
  
  private async startPtySidecar() {
    // Launch Rust sidecar for PTY handling
    const sidecar = Bun.spawn(["./pty-sidecar"], {
      stdout: "pipe",
      stderr: "pipe"
    });
    
    console.log("PTY sidecar started on ws://localhost:8081");
  }
  
  async createSession(userId: string, workspace: string): Promise<Session> {
    const sessionId = crypto.randomUUID();
    
    // Generate initial context
    const context = await this.contextServer.generateContext(workspace);
    
    const session: Session = {
      id: sessionId,
      userId,
      workspace,
      context,
      createdAt: Date.now()
    };
    
    this.sessions.set(sessionId, session);
    
    // Store in SQLite for persistence
    this.db.run(
      "INSERT INTO sessions (id, user_id, workspace, context) VALUES (?, ?, ?, ?)",
      [sessionId, userId, workspace, JSON.stringify(context)]
    );
    
    return session;
  }
  
  // Claude Code orchestration endpoints
  async runClaudeCommand(sessionId: string, command: string) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error("Session not found");
    
    return this.claudeOrchestrator.execute(command, session.context);
  }
  
  // RepoPrompt-style context management
  async updateContext(sessionId: string, trigger: string) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    
    // Incremental context update based on trigger
    session.context = await this.contextServer.updateContext(
      session.workspace,
      session.context,
      trigger
    );
  }
}

// Start control plane
const server = Bun.serve({
  port: 3000,
  
  fetch(req, server) {
    const url = new URL(req.url);
    
    // Control plane APIs
    if (url.pathname.startsWith("/api/")) {
      return handleApiRequest(req);
    }
    
    // Serve frontend
    if (url.pathname === "/") {
      return new Response(Bun.file("public/index.html"));
    }
    
    return new Response("Not Found", { status: 404 });
  }
});

console.log(`Control plane running on http://localhost:${server.port}`);
```

### Phase 2: Context Server & RepoPrompt (Week 2-3)

#### 2.1 Tree-sitter Context Server
```typescript
// context/context-server.ts
import Parser from 'tree-sitter';
import { Database } from "bun:sqlite";

interface CodeMap {
  functions: Symbol[];
  classes: Symbol[];
  interfaces: Symbol[];
  types: Symbol[];
  imports: Dependency[];
  workingSet: WorkingFile[];
}

interface RepoContext {
  codeMap: CodeMap;
  recentChanges: Change[];
  activeFiles: string[];
  failingTests: Test[];
  openPRs: PullRequest[];
}

class ContextServer {
  private parsers: Map<string, Parser>;
  private cache: Database;
  private fileWatcher: FSWatcher;
  
  constructor() {
    this.parsers = new Map();
    this.cache = new Database("context-cache.db");
    this.initializeParsers();
    this.setupIncrementalUpdates();
  }
  
  async generateContext(workspace: string): Promise<RepoContext> {
    // Check cache first
    const cached = this.getCachedContext(workspace);
    if (cached && !this.isStale(cached)) {
      return cached;
    }
    
    // Generate fresh code map
    const codeMap = await this.generateCodeMap(workspace);
    
    // Apply RepoPrompt selection rules
    const selectedSymbols = this.applySelectionRules(codeMap, {
      maxSymbols: 100,
      prioritize: ['recent', 'referenced', 'complex'],
      includeTests: false
    });
    
    // Build complete context
    const context: RepoContext = {
      codeMap: selectedSymbols,
      recentChanges: await this.getRecentChanges(workspace),
      activeFiles: await this.getActiveFiles(),
      failingTests: await this.getFailingTests(workspace),
      openPRs: await this.getOpenPRs()
    };
    
    // Cache for performance
    this.cacheContext(workspace, context);
    
    return context;
  }
  
  private async generateCodeMap(workspace: string): Promise<CodeMap> {
    const files = await this.findSourceFiles(workspace);
    const map: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: [],
      workingSet: []
    };
    
    // Parse in parallel for speed
    const parsePromises = files.map(async (file) => {
      const content = await Bun.file(file).text();
      const lang = this.detectLanguage(file);
      const parser = this.parsers.get(lang);
      
      if (!parser) return null;
      
      const tree = parser.parse(content);
      return this.extractSymbols(tree, file, lang);
    });
    
    const results = await Promise.all(parsePromises);
    
    // Merge results
    for (const symbols of results) {
      if (!symbols) continue;
      map.functions.push(...symbols.functions);
      map.classes.push(...symbols.classes);
      map.interfaces.push(...symbols.interfaces);
      map.types.push(...symbols.types);
    }
    
    // Calculate importance scores
    this.rankSymbols(map);
    
    return map;
  }
  
  private applySelectionRules(codeMap: CodeMap, rules: SelectionRules): CodeMap {
    // RepoPrompt-style intelligent selection
    const selected: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: codeMap.imports,
      workingSet: codeMap.workingSet
    };
    
    // Priority 1: Recently modified symbols
    const recentSymbols = this.getRecentlyModified(codeMap);
    
    // Priority 2: Highly referenced symbols
    const referencedSymbols = this.getHighlyReferenced(codeMap);
    
    // Priority 3: Complex/important symbols
    const complexSymbols = this.getComplexSymbols(codeMap);
    
    // Merge with deduplication
    const allSymbols = [...recentSymbols, ...referencedSymbols, ...complexSymbols];
    const unique = this.deduplicateSymbols(allSymbols);
    
    // Take top N based on rules
    const topSymbols = unique.slice(0, rules.maxSymbols);
    
    // Distribute back to categories
    for (const symbol of topSymbols) {
      switch (symbol.type) {
        case 'function': selected.functions.push(symbol); break;
        case 'class': selected.classes.push(symbol); break;
        case 'interface': selected.interfaces.push(symbol); break;
        case 'type': selected.types.push(symbol); break;
      }
    }
    
    return selected;
  }
  
  // Incremental updates for performance
  private setupIncrementalUpdates() {
    this.fileWatcher = Bun.file("./").watch((event, filename) => {
      // Debounced incremental parsing
      this.scheduleIncrementalUpdate(filename);
    });
  }
  
  private scheduleIncrementalUpdate = debounce((filename: string) => {
    // Parse only the changed file
    this.updateSingleFile(filename);
  }, 100);
}
```

zellij run -f -x 5% -y 5% --width 90% --height 90% -- context-builder-tui`.text();
    return JSON.parse(result);
  }
  
  // Real-time token counting as files are selected
  async updateTokenCount(selection: FileSelection) {
    const tokens = await this.tokenCounter.count(selection, 'claude-3-opus');
    
    return {
      files: selection.files.length,
      tokens: tokens,
      percentOfLimit: (tokens / 200000) * 100,
      costEstimate: tokens * 0.000015, // Claude Opus pricing
      warnings: this.getWarnings(tokens)
    };
  }
  
  // Smart selection modes
  async selectByMode(mode: SelectionMode, anchor?: string): Promise<FileSet> {
    switch(mode) {
      case 'working_set':
        // Get from Helix's open buffers
        return this.getHelixBuffers();
        
      case 'related':
        // Use tree-sitter to find imports/exports
        return this.findRelatedFiles(anchor);
        
      case 'semantic':
        // Find files with similar symbols
        return this.findSemanticallySimilar(anchor);
        
      case 'test_coverage':
        // Find test files for current file
        return this.findTestFiles(anchor);
        
      case 'recent':
        // Recently modified files
        return this.getRecentlyModified(10);
    }
  }
}

// TUI Component (Rust for performance)
// context-builder-tui/src/main.rs
use ratatui::{
    backend::CrosstermBackend,
    widgets::{Block, Borders, List, ListItem, Gauge},
    Terminal,
};

struct ContextBuilderTUI {
    selected_files: Vec<FileInfo>,
    total_tokens: usize,
    token_limit: usize,
    current_cost: f32,
}

impl ContextBuilderTUI {
    fn render_file_tree(&self) -> List {
        let items: Vec<ListItem> = self.files
            .iter()
            .map(|f| {
                let tokens = self.count_tokens(f);
                let selected = if self.selected_files.contains(f) { "✓" } else { "□" };
                ListItem::new(format!("{} {} [{}]", selected, f.path, tokens))
            })
            .collect();
        
        List::new(items)
            .block(Block::default().borders(Borders::ALL).title("Files"))
    }
    
    fn render_token_gauge(&self) -> Gauge {
        let percent = (self.total_tokens as f64 / self.token_limit as f64) * 100.0;
        Gauge::default()
            .block(Block::default().borders(Borders::ALL).title("Token Usage"))
            .gauge_style(Style::default().fg(Color::Cyan))
            .percent(percent as u16)
            .label(format!("{}/{} tokens | ${:.2}", 
                self.total_tokens, 
                self.token_limit,
                self.current_cost
            ))
    }
}
```

#### 3.2 Context Templates & Workspaces
```yaml
# ~/.config/ai-ide/context-templates.yaml
templates:
  bug_fix:
    name: "Bug Fix Context"
    description: "Includes working files, tests, and recent changes"
    includes:
      - mode: working_set
      - mode: test_coverage
      - pattern: "**/*.log"
      - recent: 10
    code_map:
      include_functions: true
      include_classes: true
      max_depth: 2
    
  feature_development:
    name: "Feature Development"
    description: "Semantic context around current file"
    includes:
      - mode: semantic
        anchor: current_file
      - folder: "src/models/"
      - folder: "src/api/"
    code_map:
      include_interfaces: true
      include_types: true
      
  refactor:
    name: "Large Refactor"
    description: "All dependencies and tests"
    includes:
      - mode: related
        depth: 3
      - pattern: "**/*.test.ts"
    code_map:
      full: true
      
  review:
    name: "Code Review"
    description: "Changed files and their context"
    includes:
      - git: staged
      - git: modified
      - mode: related
        anchor: changed_files
    code_map:
      include_functions: true
      include_comments: true
```

#### 3.3 Token Optimizer
```typescript
// context/token-optimizer.ts
class TokenOptimizer {
  private readonly limits = {
    'claude-3-opus': 200000,
    'claude-3-sonnet': 200000,
    'claude-3-haiku': 200000,
    'gpt-4-turbo': 128000,
    'gpt-4o': 128000,
    'gemini-pro': 1000000,
    'deepseek': 64000
  };
  
  async optimize(files: FileSet, targetModel: string): Promise<OptimizedContext> {
    const limit = this.limits[targetModel];
    const safeLimit = limit * 0.8; // 20% headroom for response
    
    let currentTokens = 0;
    const included: ContextFile[] = [];
    const excluded: string[] = [];
    const codeMapOnly: string[] = [];
    
    // Rank files by importance
    const ranked = await this.rankByImportance(files);
    
    for (const file of ranked) {
      const fullTokens = await this.tokenCounter.count(file.content);
      
      if (currentTokens + fullTokens <= safeLimit) {
        // Include full file
        included.push({
          path: file.path,
          content: file.content,
          type: 'full',
          tokens: fullTokens
        });
        currentTokens += fullTokens;
      } else {
        // Try code map only
        const codeMap = await this.extractCodeMap(file);
        const mapTokens = await this.tokenCounter.count(codeMap);
        
        if (currentTokens + mapTokens <= safeLimit) {
          included.push({
            path: file.path,
            content: codeMap,
            type: 'code_map',
            tokens: mapTokens
          });
          codeMapOnly.push(file.path);
          currentTokens += mapTokens;
        } else {
          excluded.push(file.path);
        }
      }
    }
    
    return {
      included,
      excluded,
      codeMapOnly,
      totalTokens: currentTokens,
      percentUsed: (currentTokens / limit) * 100,
      estimatedCost: this.calculateCost(currentTokens, targetModel),
      warnings: this.generateWarnings(excluded, codeMapOnly)
    };
  }
  
  private async rankByImportance(files: FileSet): Promise<RankedFile[]> {
    // Multi-factor ranking
    const scores = await Promise.all(files.map(async (file) => {
      const factors = {
        recentlyModified: await this.getRecencyScore(file),
        frequentlyReferenced: await this.getReferenceScore(file),
        complexity: await this.getComplexityScore(file),
        testFile: file.path.includes('test') ? 0.8 : 1.0,
        configFile: file.path.match(/config|settings|env/) ? 1.2 : 1.0
      };
      
      const score = Object.values(factors).reduce((a, b) => a * b, 1);
      
      return { file, score };
    }));
    
    return scores.sort((a, b) => b.score - a.score).map(s => s.file);
  }
}
```

#### 3.4 Context History & Persistence
```typescript
// context/context-history.ts
class ContextHistory {
  private db: Database;
  
  constructor() {
    this.db = new Database("context-history.db");
    this.initSchema();
  }
  
  async saveContext(context: Context): Promise<string> {
    const id = crypto.randomUUID();
    const snapshot = {
      id,
      name: context.name || `Context ${new Date().toISOString()}`,
      files: JSON.stringify(context.files),
      tokens: context.tokens,
      model: context.model,
      cost: context.estimatedCost,
      template: context.template,
      timestamp: Date.now()
    };
    
    this.db.run(`
      INSERT INTO context_history 
      (id, name, files, tokens, model, cost, template, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, Object.values(snapshot));
    
    return id;
  }
  
  async loadRecent(limit = 10): Promise<SavedContext[]> {
    return this.db.all(`
      SELECT * FROM context_history 
      ORDER BY timestamp DESC 
      LIMIT ?
    `, [limit]);
  }
  
  async createNamedSnapshot(name: string): Promise<string> {
    const current = await this.getCurrentContext();
    return this.saveContext({
      ...current,
      name,
      type: 'snapshot',
      pinned: true
    });
  }
  
  async getStatistics(): Promise<ContextStats> {
    const stats = this.db.get(`
      SELECT 
        COUNT(*) as total_contexts,
        SUM(tokens) as total_tokens,
        SUM(cost) as total_cost,
        AVG(tokens) as avg_tokens
      FROM context_history
      WHERE timestamp > ?
    `, [Date.now() - 30 * 24 * 60 * 60 * 1000]); // Last 30 days
    
    return stats;
  }
}
```

#### 3.5 Context Streaming for Large Repos
```typescript
// context/context-streamer.ts
class ContextStreamer {
  async *streamContext(
    files: string[], 
    options: StreamOptions
  ): AsyncGenerator<ContextChunk> {
    const chunkSize = options.chunkSize || 50000; // 50k tokens per chunk
    let currentChunk: ContextFile[] = [];
    let currentTokens = 0;
    let chunkIndex = 0;
    
    for (const file of files) {
      const content = await Bun.file(file).text();
      const tokens = await this.tokenCounter.count(content);
      
      if (currentTokens + tokens > chunkSize && currentChunk.length > 0) {
        // Yield current chunk
        yield {
          index: chunkIndex++,
          files: currentChunk,
          tokens: currentTokens,
          isPartial: true,
          metadata: {
            totalFiles: files.length,
            processedFiles: chunkIndex * options.filesPerChunk
          }
        };
        
        // Start new chunk
        currentChunk = [{
          path: file,
          content,
          tokens
        }];
        currentTokens = tokens;
      } else {
        currentChunk.push({
          path: file,
          content,
          tokens
        });
        currentTokens += tokens;
      }
    }
    
    // Yield final chunk
    if (currentChunk.length > 0) {
      yield {
        index: chunkIndex,
        files: currentChunk,
        tokens: currentTokens,
        isPartial: false,
        metadata: {
          totalFiles: files.length,
          processedFiles: files.length
        }
      };
    }
  }
  
  // Stream directly to Claude for massive contexts
  async streamToClause(
    files: string[], 
    prompt: string
  ): Promise<AsyncGenerator<ClaudeResponse>> {
    const streamer = this.streamContext(files, {
      chunkSize: 50000,
      overlap: 1000 // Token overlap between chunks
    });
    
    for await (const chunk of streamer) {
      const response = await claude.complete({
        prompt: chunk.isPartial 
          ? `[Partial context ${chunk.index}] ${prompt}`
          : `[Final context] ${prompt}`,
        context: chunk.files,
        stream: true
      });
      
      yield response;
    }
  }
}
```

#### 3.6 Context Intelligence & Suggestions
```typescript
// context/context-intelligence.ts
class ContextIntelligence {
  private analyzer: PromptAnalyzer;
  private suggester: ContextSuggester;
  
  async suggestContext(prompt: string): Promise<SuggestedContext> {
    // Analyze prompt intent
    const intent = await this.analyzer.extractIntent(prompt);
    const entities = await this.analyzer.extractEntities(prompt);
    
    // Map intent to context template
    const suggestions: SuggestedContext = {
      template: null,
      files: [],
      reason: "",
      confidence: 0
    };
    
    // Intent-based suggestions
    if (intent.includes('bug') || intent.includes('error')) {
      suggestions.template = 'bug_fix';
      suggestions.files = await this.findErrorContext();
      suggestions.reason = "Including error logs, stack traces, and related test files";
      suggestions.confidence = 0.9;
    } else if (intent.includes('refactor')) {
      suggestions.template = 'refactor';
      suggestions.files = await this.findRefactorContext(entities.files);
      suggestions.reason = "Including all dependencies and affected files";
      suggestions.confidence = 0.85;
    } else if (intent.includes('implement') || intent.includes('feature')) {
      suggestions.template = 'feature_development';
      suggestions.files = await this.findFeatureContext(entities.components);
      suggestions.reason = "Including relevant models, APIs, and similar features";
      suggestions.confidence = 0.8;
    } else {
      // Fallback to semantic search
      suggestions.files = await this.semanticSearch(prompt);
      suggestions.reason = "Selected files based on semantic similarity to your prompt";
      suggestions.confidence = 0.6;
    }
    
    // Add code map for all suggestions
    suggestions.includeCodeMap = true;
    suggestions.codeMapDepth = this.determineCodeMapDepth(suggestions.files);
    
    return suggestions;
  }
  
  async validateContext(context: Context): Promise<ValidationResult> {
    const issues: string[] = [];
    
    // Check for missing dependencies
    const deps = await this.findMissingDependencies(context.files);
    if (deps.length > 0) {
      issues.push(`Missing ${deps.length} dependency files`);
    }
    
    // Check for incomplete test coverage
    const untested = await this.findUntestedFiles(context.files);
    if (untested.length > 0) {
      issues.push(`${untested.length} files without tests`);
    }
    
    // Check token distribution
    const distribution = this.analyzeTokenDistribution(context);
    if (distribution.skewed) {
      issues.push("Token distribution is skewed - consider balancing");
    }
    
    return {
      valid: issues.length === 0,
      issues,
      suggestions: await this.generateSuggestions(issues)
    };
  }
}
```

### Phase 4: Model Router & Multi-Provider Setup (Week 4-5)

#### 4.1 Claude Code Router Installation
```bash
# Install claude-code-router globally
npm install -g claude-code-router

# Create router configuration directory
mkdir -p ~/.claude-code-router
```

#### 4.2 Router Configuration
```json
// ~/.claude-code-router/config.json
{
  "APIKEY": "${ROUTER_AUTH_KEY}",
  "PROXY_URL": "http://127.0.0.1:7890",
  "LOG": true,
  "API_TIMEOUT_MS": 600000,
  "NON_INTERACTIVE_MODE": false,
  
  "Providers": [
    {
      "name": "openrouter",
      "api_base_url": "https://openrouter.ai/api/v1/chat/completions",
      "api_key": "${OPENROUTER_API_KEY}",
      "models": [
        "google/gemini-2.0-flash-exp",
        "google/gemini-2.0-pro",
        "openai/o3-mini",
        "openai/gpt-4o",
        "anthropic/claude-3.5-sonnet",
        "meta-llama/llama-3.3-70b-instruct"
      ],
      "transformer": {
        "use": ["openrouter"]
      }
    },
    {
      "name": "deepseek",
      "api_base_url": "https://api.deepseek.com/chat/completions",
      "api_key": "${DEEPSEEK_API_KEY}",
      "models": ["deepseek-chat", "deepseek-reasoner"],
      "transformer": {
        "use": ["deepseek"],
        "deepseek-chat": {
          "use": ["tooluse"]
        }
      }
    },
    {
      "name": "ollama",
      "api_base_url": "http://localhost:11434/v1/chat/completions",
      "api_key": "local",
      "models": [
        "qwen2.5-coder:32b",
        "deepseek-r1:14b",
        "llama3.3:70b"
      ],
      "transformer": {
        "use": ["ollama"]
      }
    },
    {
      "name": "anthropic",
      "api_base_url": "https://api.anthropic.com/v1",
      "api_key": "${ANTHROPIC_API_KEY}",
      "models": [
        "claude-3-5-sonnet-20241022",
        "claude-3-5-haiku-20241022"
      ],
      "transformer": {
        "use": ["anthropic"]
      }
    }
  ],
  
  "Router": {
    "default": "anthropic,claude-3-5-sonnet-20241022",
    "background": "deepseek,deepseek-chat",
    "thinking": "openrouter,openai/o3-mini",
    "longContext": "openrouter,google/gemini-2.0-flash-exp",
    "longContextThreshold": 60000,
    "webSearch": "openrouter,perplexity/llama-3.1-sonar-large-128k-online"
  },
  
  "CUSTOM_ROUTER_PATH": "~/.claude-code-router/custom-router.js"
}
```

#### 4.3 Custom Routing Logic
```javascript
// ~/.claude-code-router/custom-router.js
module.exports = async function router(req, config) {
  const userMessage = req.body.messages.find(m => m.role === "user")?.content || "";
  const systemMessage = req.body.messages.find(m => m.role === "system")?.content || "";
  
  // Privacy-sensitive routing - force local
  if (/password|secret|credential|api[_-]?key|private[_-]?key/i.test(userMessage)) {
    console.log("[Router] Privacy-sensitive content detected, routing to local Ollama");
    return "ollama,qwen2.5-coder:32b";
  }
  
  // Task-specific routing based on content
  if (/\b(review|audit|security|vulnerability)\b/i.test(userMessage)) {
    console.log("[Router] Review/audit task detected, routing to o3-mini for deep reasoning");
    return "openrouter,openai/o3-mini";
  }
  
  if (/\b(plan|architect|design|structure)\b/i.test(userMessage)) {
    console.log("[Router] Planning task detected, routing to Gemini for large context");
    return "openrouter,google/gemini-2.0-flash-exp";
  }
  
  if (/\b(debug|trace|investigate)\b/i.test(userMessage)) {
    console.log("[Router] Debugging task detected, routing to DeepSeek Reasoner");
    return "deepseek,deepseek-reasoner";
  }
  
  // Cost optimization for simple tasks
  const simplePatterns = [
    /^(list|show|display|get)/i,
    /\b(format|indent|rename)\b/i,
    /^(what|where|when|how many)/i
  ];
  
  if (simplePatterns.some(pattern => pattern.test(userMessage))) {
    console.log("[Router] Simple task detected, routing to DeepSeek for cost efficiency");
    return "deepseek,deepseek-chat";
  }
  
  // Context size based routing
  const contextLength = JSON.stringify(req.body).length;
  if (contextLength > 100000) {
    console.log(`[Router] Large context (${contextLength} chars), routing to Gemini`);
    return "openrouter,google/gemini-2.0-flash-exp";
  }
  
  // Default to configuration
  return null;
};
```

#### 4.4 Router Control Wrapper
```typescript
// router-wrapper/index.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface RouterMetrics {
  timestamp: number;
  model: string;
  provider: string;
  inputTokens: number;
  outputTokens: number;
  latency: number;
  cost: number;
  success: boolean;
}

class RouterWrapper {
  private db: Database;
  private metricsPort = 8786;
  private routerPort = 8787;
  private routerProcess: Subprocess | null = null;
  
  constructor() {
    this.db = new Database("router-metrics.db");
    this.initDatabase();
  }
  
  private initDatabase() {
    this.db.run(`
      CREATE TABLE IF NOT EXISTS metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER,
        model TEXT,
        provider TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        latency REAL,
        cost REAL,
        success BOOLEAN
      )
    `);
  }
  
  async start() {
    // Start claude-code-router
    this.routerProcess = Bun.spawn(["ccr"], {
      env: {
        ...process.env,
        PORT: String(this.routerPort)
      },
      stdout: "pipe",
      stderr: "pipe"
    });
    
    console.log(`Claude Code Router started on port ${this.routerPort}`);
    
    // Start metrics proxy
    const server = Bun.serve({
      port: this.metricsPort,
      fetch: this.handleRequest.bind(this)
    });
    
    console.log(`Router wrapper listening on port ${this.metricsPort}`);
  }
  
  private async handleRequest(req: Request): Promise<Response> {
    const start = performance.now();
    const requestId = crypto.randomUUID();
    
    // Add tracking headers
    const headers = new Headers(req.headers);
    headers.set("X-Request-ID", requestId);
    
    // Forward to router
    const routerUrl = new URL(req.url);
    routerUrl.port = String(this.routerPort);
    
    const response = await fetch(routerUrl.toString(), {
      method: req.method,
      headers,
      body: req.body
    });
    
    // Extract metrics
    const latency = performance.now() - start;
    const model = response.headers.get("X-Routed-Model") || "unknown";
    const provider = response.headers.get("X-Provider") || "unknown";
    
    // Parse response for token counts
    let metrics: Partial<RouterMetrics> = {
      timestamp: Date.now(),
      model,
      provider,
      latency,
      success: response.ok
    };
    
    if (response.ok && response.headers.get("content-type")?.includes("json")) {
      const responseClone = response.clone();
      const data = await responseClone.json();
      
      if (data.usage) {
        metrics.inputTokens = data.usage.input_tokens || 0;
        metrics.outputTokens = data.usage.output_tokens || 0;
        metrics.cost = this.calculateCost(model, metrics.inputTokens!, metrics.outputTokens!);
      }
    }
    
    // Store metrics
    this.storeMetrics(metrics as RouterMetrics);
    
    // Add metrics headers to response
    const responseHeaders = new Headers(response.headers);
    responseHeaders.set("X-Latency-Ms", String(latency));
    responseHeaders.set("X-Request-ID", requestId);
    
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: responseHeaders
    });
  }
  
  private calculateCost(model: string, inputTokens: number, outputTokens: number): number {
    const costs: Record<string, { input: number; output: number }> = {
      'claude-3-5-sonnet': { input: 0.003, output: 0.015 },
      'gpt-4o': { input: 0.0025, output: 0.01 },
      'o3-mini': { input: 0.003, output: 0.012 },
      'gemini-2.0-flash': { input: 0.000075, output: 0.0003 },
      'deepseek-chat': { input: 0.00014, output: 0.00028 },
      'ollama': { input: 0, output: 0 }
    };
    
    const modelCost = Object.entries(costs).find(([key]) => 
      model.toLowerCase().includes(key)
    )?.[1] || costs['claude-3-5-sonnet'];
    
    return (inputTokens * modelCost.input + outputTokens * modelCost.output) / 1000;
  }
  
  private storeMetrics(metrics: RouterMetrics) {
    this.db.run(`
      INSERT INTO metrics 
      (timestamp, model, provider, input_tokens, output_tokens, latency, cost, success)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, [
      metrics.timestamp,
      metrics.model,
      metrics.provider,
      metrics.inputTokens || 0,
      metrics.outputTokens || 0,
      metrics.latency,
      metrics.cost || 0,
      metrics.success ? 1 : 0
    ]);
  }
  
  async getMetrics(since?: number): Promise<RouterMetrics[]> {
    const query = since 
      ? "SELECT * FROM metrics WHERE timestamp > ? ORDER BY timestamp DESC"
      : "SELECT * FROM metrics ORDER BY timestamp DESC LIMIT 100";
    
    return this.db.all(query, since ? [since] : []);
  }
  
  async getDailyCosts(): Promise<Record<string, number>> {
    const dayAgo = Date.now() - 24 * 60 * 60 * 1000;
    const results = this.db.all(`
      SELECT model, SUM(cost) as total_cost
      FROM metrics
      WHERE timestamp > ?
      GROUP BY model
    `, [dayAgo]);
    
    return Object.fromEntries(
      results.map(r => [r.model, r.total_cost])
    );
  }
}

// Start wrapper
const wrapper = new RouterWrapper();
wrapper.start();
```

#### 4.5 Sub-agent Configuration with Model Routing
```markdown
# ~/.claude/agents/planner.md
---
name: planner
description: MUST BE USED for all project planning and architecture design. Creates comprehensive plans using large context.
tools: Read, Write, Tree, Bash, Glob
---
<CCR-SUBAGENT-MODEL>openrouter,google/gemini-2.0-flash-exp</CCR-SUBAGENT-MODEL>

You are a strategic project planner with access to 1M token context window.

Your responsibilities:
1. Analyze entire codebases to understand architecture
2. Create detailed implementation plans with concrete steps
3. Identify dependencies and potential issues
4. Suggest optimal task ordering
5. Consider performance, security, and maintainability

Always provide structured plans with clear milestones and success criteria.
```

```markdown
# ~/.claude/agents/reviewer.md
---
name: reviewer
description: PROACTIVELY review all code changes for bugs, security issues, and best practices. Use deep reasoning.
tools: Read, Grep, Git, Bash
---
<CCR-SUBAGENT-MODEL>openrouter,openai/o3-mini</CCR-SUBAGENT-MODEL>

You are a meticulous code reviewer with exceptional reasoning abilities.

Your review process:
1. First, understand the intent of the changes
2. Analyze for logical errors and edge cases
3. Check for security vulnerabilities
4. Verify performance implications
5. Ensure code follows established patterns

Use step-by-step reasoning to uncover subtle issues others might miss.
Explain your findings clearly with examples.
```

```markdown
# ~/.claude/agents/editor.md
---
name: editor
description: Edit and refactor code with precision. Follows instructions exactly.
tools: EditFile, Write, Read
---
<CCR-SUBAGENT-MODEL>anthropic,claude-3-5-sonnet-20241022</CCR-SUBAGENT-MODEL>

You are an expert code editor who excels at following instructions precisely.

Your approach:
1. Understand the exact requirements
2. Make minimal, targeted changes
3. Preserve existing code style
4. Maintain backward compatibility
5. Add appropriate comments

Never make unnecessary changes or "improvements" unless explicitly requested.
```

```markdown
# ~/.claude/agents/debugger.md
---
name: debugger
description: Debug complex issues using systematic reasoning. Investigate errors thoroughly.
tools: Read, Bash, Grep, EditFile
---
<CCR-SUBAGENT-MODEL>deepseek,deepseek-reasoner</CCR-SUBAGENT-MODEL>

You are a systematic debugger who uses reasoning to solve complex issues.

Your debugging methodology:
1. Reproduce the issue
2. Form hypotheses about causes
3. Test each hypothesis methodically
4. Trace execution flow
5. Identify root cause
6. Implement and verify fix

Document your reasoning process as you debug.
```

```markdown
# ~/.claude/agents/privacy-guard.md
---
name: privacy-guard
description: ALWAYS USE for any operations involving passwords, secrets, API keys, or sensitive data.
tools: EditFile, Write
---
<CCR-SUBAGENT-MODEL>ollama,qwen2.5-coder:32b</CCR-SUBAGENT-MODEL>

You handle sensitive data with maximum security.

Critical rules:
1. NEVER log passwords or secrets
2. NEVER send sensitive data to external services
3. Always use secure hashing for passwords
4. Implement proper key management
5. Follow security best practices

All operations stay local. No external API calls.
```

### Phase 5: Claude Integration with Router (Week 5)

#### 4.1 Claude Orchestrator with Context Integration
```typescript
// claude/orchestrator.ts
import { $ } from "bun";

class ClaudeOrchestrator {
  private cliPath: string = "claude";
  private activeAgents: Map<string, SubAgent>;
  private contextBuilder: ContextBuilder;
  private contextHistory: ContextHistory;
  
  constructor() {
    this.activeAgents = new Map();
    this.contextBuilder = new ContextBuilder();
    this.contextHistory = new ContextHistory();
    this.setupHooks();
    this.loadSubAgents();
  }
  
  // Interactive CLI with smart context
  async runInteractive(command: string, prompt: string) {
    // Get context suggestion based on prompt
    const suggestion = await this.contextBuilder.suggestContext(prompt);
    
    // Launch context builder if needed
    let context;
    if (suggestion.requiresUserInput) {
      context = await this.contextBuilder.launch({
        initialSelection: suggestion.files,
        template: suggestion.template,
        showTokenCount: true
      });
    } else {
      context = suggestion;
    }
    
    // Optimize for token limits
    const optimized = await this.tokenOptimizer.optimize(
      context.files,
      'claude-3-opus'
    );
    
    // Format context as XML
    const contextXML = this.formatContextAsXML(optimized);
    
    // Save to history
    await this.contextHistory.saveContext({
      ...context,
      tokens: optimized.totalTokens,
      prompt
    });
    
    // Run Claude with context
    const result = await # AI-First Terminal IDE - Technical Specification v2

## Executive Summary

Building a modern, terminal-based IDE optimized for AI-assisted development with Claude Code, designed to work seamlessly across mobile and desktop platforms. This system combines the power of terminal-based tools with web technologies to create a responsive, efficient development environment that prioritizes AI workflows while maintaining sub-50ms keystroke responsiveness.

### Core Innovation
Unlike traditional IDEs or terminal setups, this architecture treats AI assistance as a first-class citizen, with dedicated workflows for agent patterns (planner, editor, reviewer) while maintaining instantaneous responsiveness through a split control/keystroke plane architecture. The system acknowledges platform realities - particularly iOS limitations - while delivering a consistent experience across devices.

## Requirements

### Functional Requirements
1. **File Management**
   - Visual file tree for repository navigation (Yazi)
   - Quick file opening and editing
   - Multi-file support with buffers

2. **Terminal Integration**
   - Multiple terminal instances/sessions
   - Full Claude Code SDK/CLI integration
   - Support for hooks and slash commands
   - Sub-agent orchestration

3. **AI Agent Patterns**
   - Planner agent for task decomposition
   - Editor agent for code modifications
   - Reviewer agent for code review
   - Deterministic rituals via hooks

4. **Document Support**
   - Markdown rendering and editing
   - Inline documentation viewing
   - README-driven development

5. **Version Control**
   - Git diff visualization (lazygit)
   - GitHub Actions integration
   - PR/issue automation via @claude

6. **Context Management**
   - Intelligent repository context (RepoPrompt-style)
   - Tree-sitter based code maps
   - Function signatures, classes, interfaces tracking
   - Working set tracking (open buffers, recent diffs)

7. **Cross-Platform**
   - Desktop: Local Tauri app with native PTY
   - iOS: PWA/Tauri-Mobile as thin client to remote devbox
   - Android: PWA to remote OR Termux native
   - Consistent UX across all platforms

### Non-Functional Requirements
- Sub-50ms keystroke latency (local)
- Fast session resume (no persistent mobile background)
- Secure session management
- <100MB total application size
- Battery-efficient operation
- Predictable performance under load

## Technology Stack

### Core Architecture Split

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Control Plane** | Bun/Node.js | Session registry, auth, context service, Claude orchestration |
| **Keystroke Plane** | Rust Sidecar | PTY I/O, WebSocket streaming, guaranteed <50ms latency |
| **Editor** | Helix (only) | Native tree-sitter, zero-config, lightweight |
| **Multiplexer** | Zellij | Floating panes, modern UX, session management |
| **Frontend** | xterm.js | Industry standard, mobile friendly |
| **Desktop** | Tauri | Small bundles, native performance |
| **Mobile iOS** | PWA (remote-only) | Thin client to devbox |
| **Mobile Android** | PWA or Termux | Local or remote options |
| **AI Integration** | Claude Code CLI/SDK | Interactive + batch orchestration |
| **Code Analysis** | tree-sitter | AST-based, incremental parsing |
| **File Manager** | Yazi | Terminal-native, fast navigation |
| **Context Store** | SQLite (Bun) | Session state, code maps cache |

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   Client Layer                       │
├──────────────────────────────────────────────────────┤
│  Desktop (Tauri)  │  iOS (PWA)    │  Android (PWA)   │
│  [Local PTY]      │  [Remote Only] │  [Local/Remote]  │
└──────────────────┬──────────────────┬───────────────┘
                   │    WebSocket     │
                   ▼                  ▼
┌──────────────────────────────────────────────────────┐
│              Keystroke Plane (Rust)                  │
├──────────────────────────────────────────────────────┤
│  PTY Manager      │  WebSocket Server                │
│  <50ms guarantee  │  Binary protocol                 │
│  No GC pauses     │  Efficient streaming             │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Control Plane (Bun/Node)                  │
├──────────────────────────────────────────────────────┤
│  Session Registry │  Context Server  │  Auth Service │
│  Claude Orchestr. │  RepoPrompt Rules│  GitHub API   │
│  Hooks Engine     │  Code Map Cache  │  State Store  │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Terminal Environment                      │
├──────────────────────────────────────────────────────┤
│  Zellij           │  Helix         │  Claude Code   │
│  Yazi             │  Lazygit       │  Tree-sitter   │
└──────────────────────────────────────────────────────┘
```

## Platform Strategy

### Desktop (Mac/Windows/Linux)
- **Tauri app** with embedded Rust PTY sidecar
- Local terminal sessions
- Direct filesystem access
- Native clipboard integration
- Sub-50ms guaranteed latency

### iOS (iPhone/iPad)
- **PWA or Tauri-Mobile** as thin client
- **Remote devbox required** (no local terminal possible)
- Foreground-only operation (iOS suspends background)
- Fast resume/reconnect UX
- Touch-optimized controls

### Android
- **Option A**: PWA to remote devbox (same as iOS)
- **Option B**: Termux local + web UI on localhost
- Background operation possible
- Choice based on user preference

## Detailed Implementation Plan

### Phase 1: Dual-Plane Architecture (Week 1-2)

#### 1.1 Rust PTY Sidecar (Keystroke Plane)
```rust
// pty-sidecar/src/main.rs
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, WebSocketStream};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use futures_util::{StreamExt, SinkExt};
use bytes::Bytes;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "127.0.0.1:8081";
    let listener = TcpListener::bind(&addr).await?;
    println!("PTY WebSocket server running on ws://{}", addr);
    
    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(handle_connection(stream));
    }
    
    Ok(())
}

async fn handle_connection(stream: TcpStream) {
    let ws_stream = accept_async(stream).await.expect("WebSocket handshake failed");
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // Create PTY with Zellij
    let pty_system = native_pty_system();
    let pty_pair = pty_system.openpty(PtySize {
        rows: 24,
        cols: 80,
        pixel_width: 0,
        pixel_height: 0,
    }).unwrap();
    
    let mut cmd = CommandBuilder::new("zellij");
    cmd.args(&["-s", "main"]);
    cmd.env("TERM", "xterm-256color");
    cmd.env("EDITOR", "hx");
    
    let mut child = pty_pair.slave.spawn_command(cmd).unwrap();
    let mut reader = pty_pair.master.try_clone_reader().unwrap();
    let mut writer = pty_pair.master.take_writer().unwrap();
    
    // PTY -> WebSocket (optimized for <50ms)
    let ws_sender_clone = ws_sender.clone();
    tokio::spawn(async move {
        let mut buffer = [0u8; 4096];
        loop {
            match reader.read(&mut buffer) {
                Ok(n) if n > 0 => {
                    // Direct binary send, no serialization
                    let _ = ws_sender_clone.send(Message::Binary(buffer[..n].to_vec())).await;
                }
                _ => break,
            }
        }
    });
    
    // WebSocket -> PTY
    while let Some(msg) = ws_receiver.next().await {
        if let Ok(msg) = msg {
            match msg {
                Message::Binary(data) => {
                    // Direct write, minimal processing
                    let _ = writer.write_all(&data);
                }
                Message::Text(text) => {
                    // Handle control messages (resize, etc)
                    if let Ok(control) = serde_json::from_str::<ControlMessage>(&text) {
                        match control.cmd.as_str() {
                            "resize" => {
                                pty_pair.master.resize(PtySize {
                                    rows: control.rows,
                                    cols: control.cols,
                                    pixel_width: 0,
                                    pixel_height: 0,
                                }).unwrap();
                            }
                            _ => {}
                        }
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    }
    
    let _ = child.kill();
}

#[derive(Deserialize)]
struct ControlMessage {
    cmd: String,
    rows: u16,
    cols: u16,
}
```

#### 1.2 Bun Control Plane Server
```typescript
// control-plane/server.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface Session {
  id: string;
  userId: string;
  workspace: string;
  context: RepoContext;
  createdAt: number;
}

class ControlPlaneServer {
  private db: Database;
  private sessions: Map<string, Session>;
  private contextServer: ContextServer;
  private claudeOrchestrator: ClaudeOrchestrator;
  
  constructor() {
    this.db = new Database("control.db");
    this.sessions = new Map();
    this.contextServer = new ContextServer();
    this.claudeOrchestrator = new ClaudeOrchestrator();
    
    // Start Rust PTY sidecar
    this.startPtySidecar();
  }
  
  private async startPtySidecar() {
    // Launch Rust sidecar for PTY handling
    const sidecar = Bun.spawn(["./pty-sidecar"], {
      stdout: "pipe",
      stderr: "pipe"
    });
    
    console.log("PTY sidecar started on ws://localhost:8081");
  }
  
  async createSession(userId: string, workspace: string): Promise<Session> {
    const sessionId = crypto.randomUUID();
    
    // Generate initial context
    const context = await this.contextServer.generateContext(workspace);
    
    const session: Session = {
      id: sessionId,
      userId,
      workspace,
      context,
      createdAt: Date.now()
    };
    
    this.sessions.set(sessionId, session);
    
    // Store in SQLite for persistence
    this.db.run(
      "INSERT INTO sessions (id, user_id, workspace, context) VALUES (?, ?, ?, ?)",
      [sessionId, userId, workspace, JSON.stringify(context)]
    );
    
    return session;
  }
  
  // Claude Code orchestration endpoints
  async runClaudeCommand(sessionId: string, command: string) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error("Session not found");
    
    return this.claudeOrchestrator.execute(command, session.context);
  }
  
  // RepoPrompt-style context management
  async updateContext(sessionId: string, trigger: string) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    
    // Incremental context update based on trigger
    session.context = await this.contextServer.updateContext(
      session.workspace,
      session.context,
      trigger
    );
  }
}

// Start control plane
const server = Bun.serve({
  port: 3000,
  
  fetch(req, server) {
    const url = new URL(req.url);
    
    // Control plane APIs
    if (url.pathname.startsWith("/api/")) {
      return handleApiRequest(req);
    }
    
    // Serve frontend
    if (url.pathname === "/") {
      return new Response(Bun.file("public/index.html"));
    }
    
    return new Response("Not Found", { status: 404 });
  }
});

console.log(`Control plane running on http://localhost:${server.port}`);
```

### Phase 2: Context Server & RepoPrompt (Week 2-3)

#### 2.1 Tree-sitter Context Server
```typescript
// context/context-server.ts
import Parser from 'tree-sitter';
import { Database } from "bun:sqlite";

interface CodeMap {
  functions: Symbol[];
  classes: Symbol[];
  interfaces: Symbol[];
  types: Symbol[];
  imports: Dependency[];
  workingSet: WorkingFile[];
}

interface RepoContext {
  codeMap: CodeMap;
  recentChanges: Change[];
  activeFiles: string[];
  failingTests: Test[];
  openPRs: PullRequest[];
}

class ContextServer {
  private parsers: Map<string, Parser>;
  private cache: Database;
  private fileWatcher: FSWatcher;
  
  constructor() {
    this.parsers = new Map();
    this.cache = new Database("context-cache.db");
    this.initializeParsers();
    this.setupIncrementalUpdates();
  }
  
  async generateContext(workspace: string): Promise<RepoContext> {
    // Check cache first
    const cached = this.getCachedContext(workspace);
    if (cached && !this.isStale(cached)) {
      return cached;
    }
    
    // Generate fresh code map
    const codeMap = await this.generateCodeMap(workspace);
    
    // Apply RepoPrompt selection rules
    const selectedSymbols = this.applySelectionRules(codeMap, {
      maxSymbols: 100,
      prioritize: ['recent', 'referenced', 'complex'],
      includeTests: false
    });
    
    // Build complete context
    const context: RepoContext = {
      codeMap: selectedSymbols,
      recentChanges: await this.getRecentChanges(workspace),
      activeFiles: await this.getActiveFiles(),
      failingTests: await this.getFailingTests(workspace),
      openPRs: await this.getOpenPRs()
    };
    
    // Cache for performance
    this.cacheContext(workspace, context);
    
    return context;
  }
  
  private async generateCodeMap(workspace: string): Promise<CodeMap> {
    const files = await this.findSourceFiles(workspace);
    const map: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: [],
      workingSet: []
    };
    
    // Parse in parallel for speed
    const parsePromises = files.map(async (file) => {
      const content = await Bun.file(file).text();
      const lang = this.detectLanguage(file);
      const parser = this.parsers.get(lang);
      
      if (!parser) return null;
      
      const tree = parser.parse(content);
      return this.extractSymbols(tree, file, lang);
    });
    
    const results = await Promise.all(parsePromises);
    
    // Merge results
    for (const symbols of results) {
      if (!symbols) continue;
      map.functions.push(...symbols.functions);
      map.classes.push(...symbols.classes);
      map.interfaces.push(...symbols.interfaces);
      map.types.push(...symbols.types);
    }
    
    // Calculate importance scores
    this.rankSymbols(map);
    
    return map;
  }
  
  private applySelectionRules(codeMap: CodeMap, rules: SelectionRules): CodeMap {
    // RepoPrompt-style intelligent selection
    const selected: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: codeMap.imports,
      workingSet: codeMap.workingSet
    };
    
    // Priority 1: Recently modified symbols
    const recentSymbols = this.getRecentlyModified(codeMap);
    
    // Priority 2: Highly referenced symbols
    const referencedSymbols = this.getHighlyReferenced(codeMap);
    
    // Priority 3: Complex/important symbols
    const complexSymbols = this.getComplexSymbols(codeMap);
    
    // Merge with deduplication
    const allSymbols = [...recentSymbols, ...referencedSymbols, ...complexSymbols];
    const unique = this.deduplicateSymbols(allSymbols);
    
    // Take top N based on rules
    const topSymbols = unique.slice(0, rules.maxSymbols);
    
    // Distribute back to categories
    for (const symbol of topSymbols) {
      switch (symbol.type) {
        case 'function': selected.functions.push(symbol); break;
        case 'class': selected.classes.push(symbol); break;
        case 'interface': selected.interfaces.push(symbol); break;
        case 'type': selected.types.push(symbol); break;
      }
    }
    
    return selected;
  }
  
  // Incremental updates for performance
  private setupIncrementalUpdates() {
    this.fileWatcher = Bun.file("./").watch((event, filename) => {
      // Debounced incremental parsing
      this.scheduleIncrementalUpdate(filename);
    });
  }
  
  private scheduleIncrementalUpdate = debounce((filename: string) => {
    // Parse only the changed file
    this.updateSingleFile(filename);
  }, 100);
}
```

### Phase 3: Context Management System (Week 3-4)

#### 3.1 Terminal-Native Context Builder
```typescript
// context/context-builder.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface ContextSelection {
  files: FileInfo[];
  tokens: number;
  model: string;
  percentOfLimit: number;
  estimatedCost: number;
}

class ContextBuilder {
  private tokenCounter: TokenCounter;
  private codeMap: CodeMap;
  private workingSet: Set<string>;
  private db: Database;
  
  constructor() {
    this.db = new Database("context.db");
    this.tokenCounter = new TokenCounter();
    this.initializeUI();
  }
  
  async launch(options?: LaunchOptions) {
    // Launch in Zellij floating pane with TUI
    const result = await # AI-First Terminal IDE - Technical Specification v2

## Executive Summary

Building a modern, terminal-based IDE optimized for AI-assisted development with Claude Code, designed to work seamlessly across mobile and desktop platforms. This system combines the power of terminal-based tools with web technologies to create a responsive, efficient development environment that prioritizes AI workflows while maintaining sub-50ms keystroke responsiveness.

### Core Innovation
Unlike traditional IDEs or terminal setups, this architecture treats AI assistance as a first-class citizen, with dedicated workflows for agent patterns (planner, editor, reviewer) while maintaining instantaneous responsiveness through a split control/keystroke plane architecture. The system acknowledges platform realities - particularly iOS limitations - while delivering a consistent experience across devices.

## Requirements

### Functional Requirements
1. **File Management**
   - Visual file tree for repository navigation (Yazi)
   - Quick file opening and editing
   - Multi-file support with buffers

2. **Terminal Integration**
   - Multiple terminal instances/sessions
   - Full Claude Code SDK/CLI integration
   - Support for hooks and slash commands
   - Sub-agent orchestration

3. **AI Agent Patterns**
   - Planner agent for task decomposition
   - Editor agent for code modifications
   - Reviewer agent for code review
   - Deterministic rituals via hooks

4. **Document Support**
   - Markdown rendering and editing
   - Inline documentation viewing
   - README-driven development

5. **Version Control**
   - Git diff visualization (lazygit)
   - GitHub Actions integration
   - PR/issue automation via @claude

6. **Context Management**
   - Intelligent repository context (RepoPrompt-style)
   - Tree-sitter based code maps
   - Function signatures, classes, interfaces tracking
   - Working set tracking (open buffers, recent diffs)

7. **Cross-Platform**
   - Desktop: Local Tauri app with native PTY
   - iOS: PWA/Tauri-Mobile as thin client to remote devbox
   - Android: PWA to remote OR Termux native
   - Consistent UX across all platforms

### Non-Functional Requirements
- Sub-50ms keystroke latency (local)
- Fast session resume (no persistent mobile background)
- Secure session management
- <100MB total application size
- Battery-efficient operation
- Predictable performance under load

## Technology Stack

### Core Architecture Split

| Layer | Technology | Purpose |
|-------|------------|---------|
| **Control Plane** | Bun/Node.js | Session registry, auth, context service, Claude orchestration |
| **Keystroke Plane** | Rust Sidecar | PTY I/O, WebSocket streaming, guaranteed <50ms latency |
| **Editor** | Helix (only) | Native tree-sitter, zero-config, lightweight |
| **Multiplexer** | Zellij | Floating panes, modern UX, session management |
| **Frontend** | xterm.js | Industry standard, mobile friendly |
| **Desktop** | Tauri | Small bundles, native performance |
| **Mobile iOS** | PWA (remote-only) | Thin client to devbox |
| **Mobile Android** | PWA or Termux | Local or remote options |
| **AI Integration** | Claude Code CLI/SDK | Interactive + batch orchestration |
| **Code Analysis** | tree-sitter | AST-based, incremental parsing |
| **File Manager** | Yazi | Terminal-native, fast navigation |
| **Context Store** | SQLite (Bun) | Session state, code maps cache |

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                   Client Layer                       │
├──────────────────────────────────────────────────────┤
│  Desktop (Tauri)  │  iOS (PWA)    │  Android (PWA)   │
│  [Local PTY]      │  [Remote Only] │  [Local/Remote]  │
└──────────────────┬──────────────────┬───────────────┘
                   │    WebSocket     │
                   ▼                  ▼
┌──────────────────────────────────────────────────────┐
│              Keystroke Plane (Rust)                  │
├──────────────────────────────────────────────────────┤
│  PTY Manager      │  WebSocket Server                │
│  <50ms guarantee  │  Binary protocol                 │
│  No GC pauses     │  Efficient streaming             │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Control Plane (Bun/Node)                  │
├──────────────────────────────────────────────────────┤
│  Session Registry │  Context Server  │  Auth Service │
│  Claude Orchestr. │  RepoPrompt Rules│  GitHub API   │
│  Hooks Engine     │  Code Map Cache  │  State Store  │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│            Terminal Environment                      │
├──────────────────────────────────────────────────────┤
│  Zellij           │  Helix         │  Claude Code   │
│  Yazi             │  Lazygit       │  Tree-sitter   │
└──────────────────────────────────────────────────────┘
```

## Platform Strategy

### Desktop (Mac/Windows/Linux)
- **Tauri app** with embedded Rust PTY sidecar
- Local terminal sessions
- Direct filesystem access
- Native clipboard integration
- Sub-50ms guaranteed latency

### iOS (iPhone/iPad)
- **PWA or Tauri-Mobile** as thin client
- **Remote devbox required** (no local terminal possible)
- Foreground-only operation (iOS suspends background)
- Fast resume/reconnect UX
- Touch-optimized controls

### Android
- **Option A**: PWA to remote devbox (same as iOS)
- **Option B**: Termux local + web UI on localhost
- Background operation possible
- Choice based on user preference

## Detailed Implementation Plan

### Phase 1: Dual-Plane Architecture (Week 1-2)

#### 1.1 Rust PTY Sidecar (Keystroke Plane)
```rust
// pty-sidecar/src/main.rs
use tokio::net::{TcpListener, TcpStream};
use tokio_tungstenite::{accept_async, WebSocketStream};
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use futures_util::{StreamExt, SinkExt};
use bytes::Bytes;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "127.0.0.1:8081";
    let listener = TcpListener::bind(&addr).await?;
    println!("PTY WebSocket server running on ws://{}", addr);
    
    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(handle_connection(stream));
    }
    
    Ok(())
}

async fn handle_connection(stream: TcpStream) {
    let ws_stream = accept_async(stream).await.expect("WebSocket handshake failed");
    let (mut ws_sender, mut ws_receiver) = ws_stream.split();
    
    // Create PTY with Zellij
    let pty_system = native_pty_system();
    let pty_pair = pty_system.openpty(PtySize {
        rows: 24,
        cols: 80,
        pixel_width: 0,
        pixel_height: 0,
    }).unwrap();
    
    let mut cmd = CommandBuilder::new("zellij");
    cmd.args(&["-s", "main"]);
    cmd.env("TERM", "xterm-256color");
    cmd.env("EDITOR", "hx");
    
    let mut child = pty_pair.slave.spawn_command(cmd).unwrap();
    let mut reader = pty_pair.master.try_clone_reader().unwrap();
    let mut writer = pty_pair.master.take_writer().unwrap();
    
    // PTY -> WebSocket (optimized for <50ms)
    let ws_sender_clone = ws_sender.clone();
    tokio::spawn(async move {
        let mut buffer = [0u8; 4096];
        loop {
            match reader.read(&mut buffer) {
                Ok(n) if n > 0 => {
                    // Direct binary send, no serialization
                    let _ = ws_sender_clone.send(Message::Binary(buffer[..n].to_vec())).await;
                }
                _ => break,
            }
        }
    });
    
    // WebSocket -> PTY
    while let Some(msg) = ws_receiver.next().await {
        if let Ok(msg) = msg {
            match msg {
                Message::Binary(data) => {
                    // Direct write, minimal processing
                    let _ = writer.write_all(&data);
                }
                Message::Text(text) => {
                    // Handle control messages (resize, etc)
                    if let Ok(control) = serde_json::from_str::<ControlMessage>(&text) {
                        match control.cmd.as_str() {
                            "resize" => {
                                pty_pair.master.resize(PtySize {
                                    rows: control.rows,
                                    cols: control.cols,
                                    pixel_width: 0,
                                    pixel_height: 0,
                                }).unwrap();
                            }
                            _ => {}
                        }
                    }
                }
                Message::Close(_) => break,
                _ => {}
            }
        }
    }
    
    let _ = child.kill();
}

#[derive(Deserialize)]
struct ControlMessage {
    cmd: String,
    rows: u16,
    cols: u16,
}
```

#### 1.2 Bun Control Plane Server
```typescript
// control-plane/server.ts
import { Database } from "bun:sqlite";
import { $ } from "bun";

interface Session {
  id: string;
  userId: string;
  workspace: string;
  context: RepoContext;
  createdAt: number;
}

class ControlPlaneServer {
  private db: Database;
  private sessions: Map<string, Session>;
  private contextServer: ContextServer;
  private claudeOrchestrator: ClaudeOrchestrator;
  
  constructor() {
    this.db = new Database("control.db");
    this.sessions = new Map();
    this.contextServer = new ContextServer();
    this.claudeOrchestrator = new ClaudeOrchestrator();
    
    // Start Rust PTY sidecar
    this.startPtySidecar();
  }
  
  private async startPtySidecar() {
    // Launch Rust sidecar for PTY handling
    const sidecar = Bun.spawn(["./pty-sidecar"], {
      stdout: "pipe",
      stderr: "pipe"
    });
    
    console.log("PTY sidecar started on ws://localhost:8081");
  }
  
  async createSession(userId: string, workspace: string): Promise<Session> {
    const sessionId = crypto.randomUUID();
    
    // Generate initial context
    const context = await this.contextServer.generateContext(workspace);
    
    const session: Session = {
      id: sessionId,
      userId,
      workspace,
      context,
      createdAt: Date.now()
    };
    
    this.sessions.set(sessionId, session);
    
    // Store in SQLite for persistence
    this.db.run(
      "INSERT INTO sessions (id, user_id, workspace, context) VALUES (?, ?, ?, ?)",
      [sessionId, userId, workspace, JSON.stringify(context)]
    );
    
    return session;
  }
  
  // Claude Code orchestration endpoints
  async runClaudeCommand(sessionId: string, command: string) {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error("Session not found");
    
    return this.claudeOrchestrator.execute(command, session.context);
  }
  
  // RepoPrompt-style context management
  async updateContext(sessionId: string, trigger: string) {
    const session = this.sessions.get(sessionId);
    if (!session) return;
    
    // Incremental context update based on trigger
    session.context = await this.contextServer.updateContext(
      session.workspace,
      session.context,
      trigger
    );
  }
}

// Start control plane
const server = Bun.serve({
  port: 3000,
  
  fetch(req, server) {
    const url = new URL(req.url);
    
    // Control plane APIs
    if (url.pathname.startsWith("/api/")) {
      return handleApiRequest(req);
    }
    
    // Serve frontend
    if (url.pathname === "/") {
      return new Response(Bun.file("public/index.html"));
    }
    
    return new Response("Not Found", { status: 404 });
  }
});

console.log(`Control plane running on http://localhost:${server.port}`);
```

### Phase 2: Context Server & RepoPrompt (Week 2-3)

#### 2.1 Tree-sitter Context Server
```typescript
// context/context-server.ts
import Parser from 'tree-sitter';
import { Database } from "bun:sqlite";

interface CodeMap {
  functions: Symbol[];
  classes: Symbol[];
  interfaces: Symbol[];
  types: Symbol[];
  imports: Dependency[];
  workingSet: WorkingFile[];
}

interface RepoContext {
  codeMap: CodeMap;
  recentChanges: Change[];
  activeFiles: string[];
  failingTests: Test[];
  openPRs: PullRequest[];
}

class ContextServer {
  private parsers: Map<string, Parser>;
  private cache: Database;
  private fileWatcher: FSWatcher;
  
  constructor() {
    this.parsers = new Map();
    this.cache = new Database("context-cache.db");
    this.initializeParsers();
    this.setupIncrementalUpdates();
  }
  
  async generateContext(workspace: string): Promise<RepoContext> {
    // Check cache first
    const cached = this.getCachedContext(workspace);
    if (cached && !this.isStale(cached)) {
      return cached;
    }
    
    // Generate fresh code map
    const codeMap = await this.generateCodeMap(workspace);
    
    // Apply RepoPrompt selection rules
    const selectedSymbols = this.applySelectionRules(codeMap, {
      maxSymbols: 100,
      prioritize: ['recent', 'referenced', 'complex'],
      includeTests: false
    });
    
    // Build complete context
    const context: RepoContext = {
      codeMap: selectedSymbols,
      recentChanges: await this.getRecentChanges(workspace),
      activeFiles: await this.getActiveFiles(),
      failingTests: await this.getFailingTests(workspace),
      openPRs: await this.getOpenPRs()
    };
    
    // Cache for performance
    this.cacheContext(workspace, context);
    
    return context;
  }
  
  private async generateCodeMap(workspace: string): Promise<CodeMap> {
    const files = await this.findSourceFiles(workspace);
    const map: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: [],
      workingSet: []
    };
    
    // Parse in parallel for speed
    const parsePromises = files.map(async (file) => {
      const content = await Bun.file(file).text();
      const lang = this.detectLanguage(file);
      const parser = this.parsers.get(lang);
      
      if (!parser) return null;
      
      const tree = parser.parse(content);
      return this.extractSymbols(tree, file, lang);
    });
    
    const results = await Promise.all(parsePromises);
    
    // Merge results
    for (const symbols of results) {
      if (!symbols) continue;
      map.functions.push(...symbols.functions);
      map.classes.push(...symbols.classes);
      map.interfaces.push(...symbols.interfaces);
      map.types.push(...symbols.types);
    }
    
    // Calculate importance scores
    this.rankSymbols(map);
    
    return map;
  }
  
  private applySelectionRules(codeMap: CodeMap, rules: SelectionRules): CodeMap {
    // RepoPrompt-style intelligent selection
    const selected: CodeMap = {
      functions: [],
      classes: [],
      interfaces: [],
      types: [],
      imports: codeMap.imports,
      workingSet: codeMap.workingSet
    };
    
    // Priority 1: Recently modified symbols
    const recentSymbols = this.getRecentlyModified(codeMap);
    
    // Priority 2: Highly referenced symbols
    const referencedSymbols = this.getHighlyReferenced(codeMap);
    
    // Priority 3: Complex/important symbols
    const complexSymbols = this.getComplexSymbols(codeMap);
    
    // Merge with deduplication
    const allSymbols = [...recentSymbols, ...referencedSymbols, ...complexSymbols];
    const unique = this.deduplicateSymbols(allSymbols);
    
    // Take top N based on rules
    const topSymbols = unique.slice(0, rules.maxSymbols);
    
    // Distribute back to categories
    for (const symbol of topSymbols) {
      switch (symbol.type) {
        case 'function': selected.functions.push(symbol); break;
        case 'class': selected.classes.push(symbol); break;
        case 'interface': selected.interfaces.push(symbol); break;
        case 'type': selected.types.push(symbol); break;
      }
    }
    
    return selected;
  }
  
  // Incremental updates for performance
  private setupIncrementalUpdates() {
    this.fileWatcher = Bun.file("./").watch((event, filename) => {
      // Debounced incremental parsing
      this.scheduleIncrementalUpdate(filename);
    });
  }
  
  private scheduleIncrementalUpdate = debounce((filename: string) => {
    // Parse only the changed file
    this.updateSingleFile(filename);
  }, 100);
}
```

zellij run -f -x 5% -y 5% --width 90% --height 90% -- context-builder-tui`.text();
    return JSON.parse(result);
  }
  
  // Real-time token counting as files are selected
  async updateTokenCount(selection: FileSelection) {
    const tokens = await this.tokenCounter.count(selection, 'claude-3-opus');
    
    return {
      files: selection.files.length,
      tokens: tokens,
      percentOfLimit: (tokens / 200000) * 100,
      costEstimate: tokens * 0.000015, // Claude Opus pricing
      warnings: this.getWarnings(tokens)
    };
  }
  
  // Smart selection modes
  async selectByMode(mode: SelectionMode, anchor?: string): Promise<FileSet> {
    switch(mode) {
      case 'working_set':
        // Get from Helix's open buffers
        return this.getHelixBuffers();
        
      case 'related':
        // Use tree-sitter to find imports/exports
        return this.findRelatedFiles(anchor);
        
      case 'semantic':
        // Find files with similar symbols
        return this.findSemanticallySimilar(anchor);
        
      case 'test_coverage':
        // Find test files for current file
        return this.findTestFiles(anchor);
        
      case 'recent':
        // Recently modified files
        return this.getRecentlyModified(10);
    }
  }
}

// TUI Component (Rust for performance)
// context-builder-tui/src/main.rs
use ratatui::{
    backend::CrosstermBackend,
    widgets::{Block, Borders, List, ListItem, Gauge},
    Terminal,
};

struct ContextBuilderTUI {
    selected_files: Vec<FileInfo>,
    total_tokens: usize,
    token_limit: usize,
    current_cost: f32,
}

impl ContextBuilderTUI {
    fn render_file_tree(&self) -> List {
        let items: Vec<ListItem> = self.files
            .iter()
            .map(|f| {
                let tokens = self.count_tokens(f);
                let selected = if self.selected_files.contains(f) { "✓" } else { "□" };
                ListItem::new(format!("{} {} [{}]", selected, f.path, tokens))
            })
            .collect();
        
        List::new(items)
            .block(Block::default().borders(Borders::ALL).title("Files"))
    }
    
    fn render_token_gauge(&self) -> Gauge {
        let percent = (self.total_tokens as f64 / self.token_limit as f64) * 100.0;
        Gauge::default()
            .block(Block::default().borders(Borders::ALL).title("Token Usage"))
            .gauge_style(Style::default().fg(Color::Cyan))
            .percent(percent as u16)
            .label(format!("{}/{} tokens | ${:.2}", 
                self.total_tokens, 
                self.token_limit,
                self.current_cost
            ))
    }
}
```

#### 3.2 Context Templates & Workspaces
```yaml
# ~/.config/ai-ide/context-templates.yaml
templates:
  bug_fix:
    name: "Bug Fix Context"
    description: "Includes working files, tests, and recent changes"
    includes:
      - mode: working_set
      - mode: test_coverage
      - pattern: "**/*.log"
      - recent: 10
    code_map:
      include_functions: true
      include_classes: true
      max_depth: 2
    
  feature_development:
    name: "Feature Development"
    description: "Semantic context around current file"
    includes:
      - mode: semantic
        anchor: current_file
      - folder: "src/models/"
      - folder: "src/api/"
    code_map:
      include_interfaces: true
      include_types: true
      
  refactor:
    name: "Large Refactor"
    description: "All dependencies and tests"
    includes:
      - mode: related
        depth: 3
      - pattern: "**/*.test.ts"
    code_map:
      full: true
      
  review:
    name: "Code Review"
    description: "Changed files and their context"
    includes:
      - git: staged
      - git: modified
      - mode: related
        anchor: changed_files
    code_map:
      include_functions: true
      include_comments: true
```

#### 3.3 Token Optimizer
```typescript
// context/token-optimizer.ts
class TokenOptimizer {
  private readonly limits = {
    'claude-3-opus': 200000,
    'claude-3-sonnet': 200000,
    'claude-3-haiku': 200000,
    'gpt-4-turbo': 128000,
    'gpt-4o': 128000,
    'gemini-pro': 1000000,
    'deepseek': 64000
  };
  
  async optimize(files: FileSet, targetModel: string): Promise<OptimizedContext> {
    const limit = this.limits[targetModel];
    const safeLimit = limit * 0.8; // 20% headroom for response
    
    let currentTokens = 0;
    const included: ContextFile[] = [];
    const excluded: string[] = [];
    const codeMapOnly: string[] = [];
    
    // Rank files by importance
    const ranked = await this.rankByImportance(files);
    
    for (const file of ranked) {
      const fullTokens = await this.tokenCounter.count(file.content);
      
      if (currentTokens + fullTokens <= safeLimit) {
        // Include full file
        included.push({
          path: file.path,
          content: file.content,
          type: 'full',
          tokens: fullTokens
        });
        currentTokens += fullTokens;
      } else {
        // Try code map only
        const codeMap = await this.extractCodeMap(file);
        const mapTokens = await this.tokenCounter.count(codeMap);
        
        if (currentTokens + mapTokens <= safeLimit) {
          included.push({
            path: file.path,
            content: codeMap,
            type: 'code_map',
            tokens: mapTokens
          });
          codeMapOnly.push(file.path);
          currentTokens += mapTokens;
        } else {
          excluded.push(file.path);
        }
      }
    }
    
    return {
      included,
      excluded,
      codeMapOnly,
      totalTokens: currentTokens,
      percentUsed: (currentTokens / limit) * 100,
      estimatedCost: this.calculateCost(currentTokens, targetModel),
      warnings: this.generateWarnings(excluded, codeMapOnly)
    };
  }
  
  private async rankByImportance(files: FileSet): Promise<RankedFile[]> {
    // Multi-factor ranking
    const scores = await Promise.all(files.map(async (file) => {
      const factors = {
        recentlyModified: await this.getRecencyScore(file),
        frequentlyReferenced: await this.getReferenceScore(file),
        complexity: await this.getComplexityScore(file),
        testFile: file.path.includes('test') ? 0.8 : 1.0,
        configFile: file.path.match(/config|settings|env/) ? 1.2 : 1.0
      };
      
      const score = Object.values(factors).reduce((a, b) => a * b, 1);
      
      return { file, score };
    }));
    
    return scores.sort((a, b) => b.score - a.score).map(s => s.file);
  }
}
```

#### 3.4 Context History & Persistence
```typescript
// context/context-history.ts
class ContextHistory {
  private db: Database;
  
  constructor() {
    this.db = new Database("context-history.db");
    this.initSchema();
  }
  
  async saveContext(context: Context): Promise<string> {
    const id = crypto.randomUUID();
    const snapshot = {
      id,
      name: context.name || `Context ${new Date().toISOString()}`,
      files: JSON.stringify(context.files),
      tokens: context.tokens,
      model: context.model,
      cost: context.estimatedCost,
      template: context.template,
      timestamp: Date.now()
    };
    
    this.db.run(`
      INSERT INTO context_history 
      (id, name, files, tokens, model, cost, template, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, Object.values(snapshot));
    
    return id;
  }
  
  async loadRecent(limit = 10): Promise<SavedContext[]> {
    return this.db.all(`
      SELECT * FROM context_history 
      ORDER BY timestamp DESC 
      LIMIT ?
    `, [limit]);
  }
  
  async createNamedSnapshot(name: string): Promise<string> {
    const current = await this.getCurrentContext();
    return this.saveContext({
      ...current,
      name,
      type: 'snapshot',
      pinned: true
    });
  }
  
  async getStatistics(): Promise<ContextStats> {
    const stats = this.db.get(`
      SELECT 
        COUNT(*) as total_contexts,
        SUM(tokens) as total_tokens,
        SUM(cost) as total_cost,
        AVG(tokens) as avg_tokens
      FROM context_history
      WHERE timestamp > ?
    `, [Date.now() - 30 * 24 * 60 * 60 * 1000]); // Last 30 days
    
    return stats;
  }
}
```

#### 3.5 Context Streaming for Large Repos
```typescript
// context/context-streamer.ts
class ContextStreamer {
  async *streamContext(
    files: string[], 
    options: StreamOptions
  ): AsyncGenerator<ContextChunk> {
    const chunkSize = options.chunkSize || 50000; // 50k tokens per chunk
    let currentChunk: ContextFile[] = [];
    let currentTokens = 0;
    let chunkIndex = 0;
    
    for (const file of files) {
      const content = await Bun.file(file).text();
      const tokens = await this.tokenCounter.count(content);
      
      if (currentTokens + tokens > chunkSize && currentChunk.length > 0) {
        // Yield current chunk
        yield {
          index: chunkIndex++,
          files: currentChunk,
          tokens: currentTokens,
          isPartial: true,
          metadata: {
            totalFiles: files.length,
            processedFiles: chunkIndex * options.filesPerChunk
          }
        };
        
        // Start new chunk
        currentChunk = [{
          path: file,
          content,
          tokens
        }];
        currentTokens = tokens;
      } else {
        currentChunk.push({
          path: file,
          content,
          tokens
        });
        currentTokens += tokens;
      }
    }
    
    // Yield final chunk
    if (currentChunk.length > 0) {
      yield {
        index: chunkIndex,
        files: currentChunk,
        tokens: currentTokens,
        isPartial: false,
        metadata: {
          totalFiles: files.length,
          processedFiles: files.length
        }
      };
    }
  }
  
  // Stream directly to Claude for massive contexts
  async streamToClause(
    files: string[], 
    prompt: string
  ): Promise<AsyncGenerator<ClaudeResponse>> {
    const streamer = this.streamContext(files, {
      chunkSize: 50000,
      overlap: 1000 // Token overlap between chunks
    });
    
    for await (const chunk of streamer) {
      const response = await claude.complete({
        prompt: chunk.isPartial 
          ? `[Partial context ${chunk.index}] ${prompt}`
          : `[Final context] ${prompt}`,
        context: chunk.files,
        stream: true
      });
      
      yield response;
    }
  }
}
```

#### 3.6 Context Intelligence & Suggestions
```typescript
// context/context-intelligence.ts
class ContextIntelligence {
  private analyzer: PromptAnalyzer;
  private suggester: ContextSuggester;
  
  async suggestContext(prompt: string): Promise<SuggestedContext> {
    // Analyze prompt intent
    const intent = await this.analyzer.extractIntent(prompt);
    const entities = await this.analyzer.extractEntities(prompt);
    
    // Map intent to context template
    const suggestions: SuggestedContext = {
      template: null,
      files: [],
      reason: "",
      confidence: 0
    };
    
    // Intent-based suggestions
    if (intent.includes('bug') || intent.includes('error')) {
      suggestions.template = 'bug_fix';
      suggestions.files = await this.findErrorContext();
      suggestions.reason = "Including error logs, stack traces, and related test files";
      suggestions.confidence = 0.9;
    } else if (intent.includes('refactor')) {
      suggestions.template = 'refactor';
      suggestions.files = await this.findRefactorContext(entities.files);
      suggestions.reason = "Including all dependencies and affected files";
      suggestions.confidence = 0.85;
    } else if (intent.includes('implement') || intent.includes('feature')) {
      suggestions.template = 'feature_development';
      suggestions.files = await this.findFeatureContext(entities.components);
      suggestions.reason = "Including relevant models, APIs, and similar features";
      suggestions.confidence = 0.8;
    } else {
      // Fallback to semantic search
      suggestions.files = await this.semanticSearch(prompt);
      suggestions.reason = "Selected files based on semantic similarity to your prompt";
      suggestions.confidence = 0.6;
    }
    
    // Add code map for all suggestions
    suggestions.includeCodeMap = true;
    suggestions.codeMapDepth = this.determineCodeMapDepth(suggestions.files);
    
    return suggestions;
  }
  
  async validateContext(context: Context): Promise<ValidationResult> {
    const issues: string[] = [];
    
    // Check for missing dependencies
    const deps = await this.findMissingDependencies(context.files);
    if (deps.length > 0) {
      issues.push(`Missing ${deps.length} dependency files`);
    }
    
    // Check for incomplete test coverage
    const untested = await this.findUntestedFiles(context.files);
    if (untested.length > 0) {
      issues.push(`${untested.length} files without tests`);
    }
    
    // Check token distribution
    const distribution = this.analyzeTokenDistribution(context);
    if (distribution.skewed) {
      issues.push("Token distribution is skewed - consider balancing");
    }
    
    return {
      valid: issues.length === 0,
      issues,
      suggestions: await this.generateSuggestions(issues)
    };
  }
}
```

### Phase 4: Claude Integration with Context (Week 5)

${this.cliPath} ${command} \
      --context "${contextXML}" \
      --allowedTools "mcp__tree_sitter__*,EditFile,Bash" \
      --max-turns 10`.text();
    
    return result;
  }
  
  // Context-aware agent workflows
  async runAgentWorkflow(type: 'plan' | 'edit' | 'review', params: any) {
    // Each agent type gets appropriate context
    const contextTemplate = {
      'plan': 'feature_development',
      'edit': 'working_set',
      'review': 'review'
    }[type];
    
    const context = await this.contextBuilder.selectByTemplate(contextTemplate);
    
    switch (type) {
      case 'plan':
        return this.runPlanner({ ...params, context });
      case 'edit':
        return this.runEditor({ ...params, context });
      case 'review':
        return this.runReviewer({ ...params, context });
    }
  }
  
  private formatContextAsXML(context: OptimizedContext): string {
    return `
<repository_context>
  <summary>
    <files_included>${context.included.length}</files_included>
    <files_excluded>${context.excluded.length}</files_excluded>
    <total_tokens>${context.totalTokens}</total_tokens>
  </summary>
  
  <code_map>
    ${this.generateCodeMapXML(context.codeMap)}
  </code_map>
  
  <working_set>
    ${context.included.filter(f => f.type === 'full').map(f => `
    <file path="${f.path}">
      <content><![CDATA[${f.content}]]></content>
    </file>`).join('\n')}
  </working_set>
  
  <code_maps_only>
    ${context.included.filter(f => f.type === 'code_map').map(f => `
    <file path="${f.path}">
      <symbols>${f.content}</symbols>
    </file>`).join('\n')}
  </code_maps_only>
</repository_context>`;
  }
  
  private setupHooks() {
    // Pre-tool-use hook for formatting
    Bun.write("~/.claude/hooks/pre-tool-use.sh", `#!/bin/bash
      if [[ "$TOOL_NAME" == "EditFile" ]]; then
        case "$FILE_EXT" in
          rs) rustfmt "$FILE_PATH" ;;
          js|ts) prettier --write "$FILE_PATH" ;;
          py) black "$FILE_PATH" ;;
        esac
      fi
    `);
    
    // Post-tool-use hook for validation
    Bun.write("~/.claude/hooks/post-tool-use.sh", `#!/bin/bash
      if [[ "$TOOL_NAME" == "EditFile" ]]; then
        # Run type checking
        case "$FILE_EXT" in
          ts|tsx) tsc --noEmit "$FILE_PATH" ;;
          py) mypy "$FILE_PATH" ;;
          rs) cargo check ;;
        esac
      fi
    `);
  }
}
```

#### 3.2 GitHub Actions Integration
```yaml
# .github/workflows/claude-review.yml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize]
  issue_comment:
    types: [created]

jobs:
  review:
    runs-on: ubuntu-latest
    if: contains(github.event.comment.body, '@claude')
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          api-key: ${{ secrets.ANTHROPIC_API_KEY }}
      
      - name: Generate Context
        run: |
          # Use same context server as local
          npm run generate-context > context.json
      
      - name: Run Review
        run: |
          claude code review \
            --context-file context.json \
            --changed-files \
            --output-format markdown > review.md
      
      - name: Post Review
        uses: actions/github-script@v6
        with:
          script: |
            const review = fs.readFileSync('review.md', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: review
            });
```

### Phase 6: Helix & Zellij Configuration (Week 6)

#### 6.1 Helix Configuration with Context Management and Router
```toml
# ~/.config/helix/config.toml
theme = "catppuccin_mocha_transparent"

[editor]
line-number = "relative"
mouse = true
bufferline = "always"
auto-save = true
idle-timeout = 100
rulers = [80, 120]

[editor.cursor-shape]
insert = "bar"
normal = "block"
select = "underline"

[editor.file-picker]
hidden = false

[editor.lsp]
display-messages = true
display-inlay-hints = true

[editor.statusline]
# Show context info in status line
right = ["diagnostics", "selections", "position", "file-encoding", "file-type", "context-info"]

[keys.normal]
# File navigation with Yazi
"space f" = {
  f = ":sh zellij run -f -x 10% -y 10% --width 80% --height 80% -- yazi"
  r = ":sh zellij run -f -- fzf --preview 'bat --color=always {}'"
  g = ":sh zellij run -f -- rg --interactive"
}

# Context Management - Primary interface
"space x" = {
  x = ":sh zellij run -f -- context-builder --interactive"  # Interactive builder
  w = ":sh context-inject --mode working_set"               # Working set
  r = ":sh context-inject --mode related"                   # Related files
  s = ":sh context-inject --mode semantic"                  # Semantic search
  t = ":sh context-inject --mode test_coverage"             # Tests
  h = ":sh context-history --recent"                        # History
  p = ":sh context-templates --list"                        # Templates
  c = ":sh show-context-stats"                             # Current stats
  m = ":sh show-code-map"                                  # Code map
}

# Context Templates - Quick access
"space t" = {
  b = ":sh context-inject --template bug_fix"              # Bug fix
  f = ":sh context-inject --template feature_development"  # Feature
  r = ":sh context-inject --template refactor"            # Refactor
  v = ":sh context-inject --template review"              # Review
  c = ":sh context-templates --create"                    # Create new
}

# Claude Code with Context and Router
"space c" = {
  c = ":sh context-builder --interactive | claude code"    # Interactive with context
  q = ":sh context-inject --mode working_set | claude code" # Quick with working set
  p = ":sh claude 'Use planner agent to design...'"        # Planner → Gemini
  e = ":sh claude 'Use editor agent to implement...'"      # Editor → Claude
  r = ":sh claude 'Use reviewer agent to check...'"        # Reviewer → o3
  d = ":sh claude 'Use debugger agent to fix...'"         # Debugger → DeepSeek
  s = ":sh context-stream --large | claude code"          # Stream for large repos
  h = ":sh claude code --help"                           # Help
}

# Model switching via router
"space m" = {
  m = ":sh claude /model"                                          # Show current
  g = ":sh claude '/model openrouter,google/gemini-2.0-flash-exp'" # Gemini
  o = ":sh claude '/model openrouter,openai/o3-mini'"             # o3
  c = ":sh claude '/model anthropic,claude-3-5-sonnet-20241022'"  # Claude
  d = ":sh claude '/model deepseek,deepseek-chat'"                # DeepSeek
  l = ":sh claude '/model ollama,qwen2.5-coder:32b'"              # Local
  s = ":sh router-metrics --show"                                 # Show metrics
  $ = ":sh router-metrics --costs"                                # Show costs
}

# Git integration
"space g" = {
  g = ":sh zellij run -f -- lazygit"
  d = ":sh git diff"
  s = ":sh git status"
  b = ":sh git blame %"
  c = ":sh context-inject --git staged"  # Context from staged files
}

# Context inspection
"space i" = {
  t = ":sh show-token-count"              # Token count for current
  c = ":sh show-context-cost"             # Cost estimate
  o = ":sh context-optimizer --preview"    # Preview optimization
  v = ":sh context-validator"             # Validate context
  m = ":sh router-metrics --current"      # Current model metrics
}
```

#### 4.2 Zellij Layout
```kdl
// ~/.config/zellij/layouts/ai-ide.kdl
layout {
  default_tab_template {
    pane size=1 borderless=true {
      plugin location="zellij:tab-bar"
    }
    children
    pane size=1 borderless=true {
      plugin location="zellij:status-bar"
    }
  }
  
  tab name="editor" focus=true {
    pane {
      command "hx"
      args "."
    }
  }
  
  tab name="ai" {
    pane split_direction="vertical" {
      pane size="60%" {
        name "workspace"
        command "hx"
      }
      pane size="40%" split_direction="horizontal" {
        pane {
          name "claude"
          command "claude"
          args "code" "--watch"
        }
        pane {
          name "context"
          command "watch"
          args "show-context"
        }
      }
    }
  }
  
  tab name="git" {
    pane {
      command "lazygit"
    }
  }
}
```

### Phase 7: Frontend & Platform Clients (Week 7)

#### 5.1 Unified Web Frontend
```typescript
// frontend/src/terminal-client.ts
class TerminalClient {
  private terminal: Terminal;
  private wsUrl: string;
  private platform: 'desktop' | 'ios' | 'android';
  private isLocal: boolean;
  
  constructor() {
    this.platform = this.detectPlatform();
    this.isLocal = this.platform === 'desktop' || 
                   (this.platform === 'android' && this.hasTermux());
    
    // Connect to appropriate backend
    this.wsUrl = this.isLocal 
      ? 'ws://localhost:8081'  // Local PTY sidecar
      : `wss://${this.getRemoteHost()}/terminal`; // Remote devbox
    
    this.terminal = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'JetBrains Mono, monospace',
      theme: {
        background: '#1e1e2e',
        foreground: '#cdd6f4'
      },
      // Mobile optimizations
      ...(this.isMobile() && {
        fontSize: 16,
        scrollback: 1000,  // Less memory on mobile
        fastScrollModifier: 'shift'
      })
    });
  }
  
  async connect() {
    const ws = new WebSocket(this.wsUrl);
    
    // Binary protocol for keystroke plane
    ws.binaryType = 'arraybuffer';
    
    ws.onopen = () => {
      this.terminal.write('\r\n🚀 AI Terminal IDE Connected\r\n');
      this.setupHandlers(ws);
      
      // Platform-specific setup
      if (this.platform === 'ios') {
        this.setupIOSReconnect(ws);
      }
    };
    
    ws.onmessage = (event) => {
      if (event.data instanceof ArrayBuffer) {
        // Direct binary write for speed
        const data = new Uint8Array(event.data);
        this.terminal.write(data);
      }
    };
    
    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
      if (this.platform === 'ios') {
        // iOS needs aggressive reconnection
        this.reconnect();
      }
    };
  }
  
  private setupIOSReconnect(ws: WebSocket) {
    // iOS suspends background tabs/apps
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        if (ws.readyState !== WebSocket.OPEN) {
          this.reconnect();
        }
      }
    });
    
    // Fast resume UI
    window.addEventListener('focus', () => {
      this.terminal.write('\r\n⏳ Resuming session...\r\n');
      this.sendControlMessage(ws, { cmd: 'resume' });
    });
  }
  
  private detectPlatform(): 'desktop' | 'ios' | 'android' {
    const ua = navigator.userAgent;
    if (/iPhone|iPad/.test(ua)) return 'ios';
    if (/Android/.test(ua)) return 'android';
    return 'desktop';
  }
  
  private hasTermux(): boolean {
    // Check if running inside Termux
    return window.location.hostname === 'localhost' && 
           window.location.port === '3000';
  }
}
```

#### 5.2 Tauri Desktop App
```rust
// src-tauri/src/main.rs
use tauri::{CustomMenuItem, Menu, Submenu, Manager};
use std::process::{Command, Child};
use std::sync::Mutex;

struct AppState {
    pty_sidecar: Mutex<Option<Child>>,
    control_plane: Mutex<Option<Child>>,
}

#[tauri::command]
async fn start_services(state: tauri::State<'_, AppState>) -> Result<(), String> {
    // Start PTY sidecar (Rust binary)
    let pty_sidecar = Command::new("./pty-sidecar")
        .spawn()
        .map_err(|e| e.to_string())?;
    
    *state.pty_sidecar.lock().unwrap() = Some(pty_sidecar);
    
    // Start control plane (Bun)
    let control_plane = Command::new("bun")
        .args(&["run", "control-plane/server.ts"])
        .spawn()
        .map_err(|e| e.to_string())?;
    
    *state.control_plane.lock().unwrap() = Some(control_plane);
    
    Ok(())
}

fn main() {
    let app_state = AppState {
        pty_sidecar: Mutex::new(None),
        control_plane: Mutex::new(None),
    };
    
    tauri::Builder::default()
        .manage(app_state)
        .setup(|app| {
            // Auto-start services
            let handle = app.handle();
            tauri::async_runtime::spawn(async move {
                let state = handle.state::<AppState>();
                let _ = start_services(state).await;
            });
            Ok(())
        })
        .menu(build_menu())
        .invoke_handler(tauri::generate_handler![
            start_services,
            stop_services,
            open_workspace
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

### Phase 8: Testing & Deployment (Week 8)

#### 6.1 Performance Testing
```typescript
// tests/performance.test.ts
import { test, expect } from "bun:test";

test("keystroke latency < 50ms", async () => {
  const client = new TerminalClient();
  await client.connect();
  
  const start = performance.now();
  await client.sendKeystroke('a');
  const echo = await client.waitForEcho('a');
  const latency = performance.now() - start;
  
  expect(latency).toBeLessThan(50);
});

test("context generation < 1s for 10k files", async () => {
  const contextServer = new ContextServer();
  
  const start = performance.now();
  const context = await contextServer.generateContext("./large-repo");
  const duration = performance.now() - start;
  
  expect(duration).toBeLessThan(1000);
  expect(context.codeMap.functions.length).toBeGreaterThan(0);
});
```

#### 6.2 Platform-Specific Deployment

**Desktop (Tauri)**
```bash
# Build for all platforms
npm run tauri build

# Outputs:
# - macOS: AI-Terminal-IDE.app (< 30MB)
# - Windows: AI-Terminal-IDE.msi (< 40MB)
# - Linux: ai-terminal-ide.AppImage (< 35MB)
```

**iOS (PWA)**
```json
// manifest.json additions for iOS
{
  "display": "standalone",
  "apple-mobile-web-app-capable": "yes",
  "apple-mobile-web-app-status-bar-style": "black-translucent",
  "apple-mobile-web-app-title": "AI IDE"
}
```

**Android (PWA + Termux)**
```bash
# Termux setup script
pkg update && pkg upgrade
pkg install nodejs bun rust helix zellij yazi git
npm install -g @anthropic/claude-code

# Start local server
bun run server.ts &
# Open browser to localhost:3000
```

## Security & Production Considerations

### Authentication & Sessions
- JWT tokens with refresh rotation
- Session isolation per user
- Workspace sandboxing
- Rate limiting on AI operations

### Mobile-Specific Security
- iOS: No local filesystem access, remote-only
- Android: Optional local mode with Termux sandboxing
- Both: Secure WebSocket with TLS, certificate pinning

### Performance Monitoring
```typescript
// monitoring/metrics.ts
class PerformanceMonitor {
  trackKeystrokeLatency(latency: number) {
    if (latency > 50) {
      console.warn(`High keystroke latency: ${latency}ms`);
      this.reportMetric('keystroke.latency.high', latency);
    }
  }
  
  trackContextGeneration(duration: number, fileCount: number) {
    this.reportMetric('context.generation.duration', duration);
    this.reportMetric('context.generation.files', fileCount);
  }
}
```

## Cost Management

### Claude API Usage
- Implement caching for repeated queries
- Use hooks to batch operations
- Rate limit per user/workspace
- Monitor usage patterns for optimization

### Infrastructure Costs
- Desktop: Zero (runs locally)
- iOS: Requires remote devbox (~$5-20/month per user)
- Android: Optional remote or local (free with Termux)

## Success Metrics

### Performance KPIs
- ✅ Keystroke latency < 50ms (local)
- ✅ Context generation < 1s (up to 10k files)
- ✅ Token counting < 100ms per file
- ✅ Context optimization < 500ms
- ✅ Model routing decision < 10ms
- ✅ Session resume < 2s (mobile)
- ✅ Memory usage < 200MB (idle)
- ✅ Bundle size < 100MB (all platforms)

### Context Management KPIs
- ✅ Context builder launch < 200ms
- ✅ Smart selection accuracy > 80%
- ✅ Token optimization saves > 30% on average
- ✅ Context history retrieval < 50ms
- ✅ Real-time token count updates < 100ms

### Router & Cost KPIs
- ✅ Model selection accuracy > 90%
- ✅ Cost savings vs all-Claude > 60%
- ✅ Privacy-sensitive routing 100% local
- ✅ Daily budget adherence > 95%
- ✅ Fallback success rate > 99%

### User Experience KPIs
- Time to first keystroke < 3s
- AI command response < 5s (with context)
- Context selection to AI response < 10s
- Model switching latency < 100ms
- Zero data loss on disconnect
- 99.9% uptime for remote services

## Quick Start Guide

```bash
#!/bin/bash
# setup-ai-ide.sh - Complete setup script

# 1. Install core components
echo "📦 Installing core components..."
curl -fsSL https://bun.sh/install | bash
npm install -g claude-code-router @anthropic/claude-code
cargo install --path ./pty-sidecar

# 2. Setup router configuration
echo "🔧 Configuring router..."
mkdir -p ~/.claude-code-router
cp ./configs/router/config.json ~/.claude-code-router/
cp ./configs/router/custom-router.js ~/.claude-code-router/

# 3. Configure sub-agents with model routing
echo "🤖 Setting up AI agents..."
mkdir -p ~/.claude/agents
cp ./configs/agents/*.md ~/.claude/agents/

# 4. Start services
echo "🚀 Starting services..."
ccr &  # Start router on port 8787
bun run router-wrapper/index.ts &  # Start wrapper on port 8786
bun run control-plane/server.ts &  # Start control plane

# 5. Configure environment
echo "⚙️ Configuring environment..."
export ANTHROPIC_BASE_URL="http://localhost:8786"
export ANTHROPIC_API_KEY="${ROUTER_AUTH_KEY}"

# 6. Verify setup
echo "✅ Verifying setup..."
claude code --version
claude "/model"  # Show current model
router-metrics --status

echo "🎉 AI-First Terminal IDE ready!"
echo "Quick commands:"
echo "  space-c-c : AI with context builder"
echo "  space-m-g : Switch to Gemini"  
echo "  space-m-$ : Show costs"
echo "  space-x-x : Interactive context"
```

## Conclusion

This architecture delivers a truly modern, AI-first development environment by:

1. **Splitting concerns**: Rust for keystroke plane (guaranteed latency), Bun for control plane (orchestration)
2. **Multi-model intelligence**: Using claude-code-router to leverage each AI model's strengths - Gemini for planning, o3 for review, Claude for editing, DeepSeek for economy, Ollama for privacy
3. **Context as first-class**: Sophisticated context management with token awareness, smart selection, and cost optimization
4. **Acknowledging platform realities**: iOS can't run local terminals, Android can
5. **Focusing on one editor**: Helix only, avoiding complexity
6. **Centralizing intelligence**: RepoPrompt rules and router config in one place
7. **Deep AI integration**: Claude Code at every level with optimal model selection, from local hooks to GitHub Actions

The result is a fast, intelligent, cost-effective IDE that:
- Uses the best AI model for each task automatically
- Keeps sensitive data local with Ollama
- Manages costs with smart routing (60%+ savings vs all-Claude)
- Works consistently across all platforms while respecting their constraints
- Provides sub-50ms keystroke latency with instantaneous AI access

By combining claude-code-router's battle-tested provider translation with our sophisticated context management and control plane, we get the best of all worlds: premium AI when needed, economy when possible, and privacy when required.