# Devys — Next-Generation Agentic IDE

> "For decades, developers worked at the level of code. Now we can work at the level of Intent."

---

## Vision

Devys is a **native macOS/iOS** agentic IDE that reimagines how developers interact with code, agents, and their development environment. Built with Swift and SwiftUI, it combines the power of modern AI agents (Claude Code, Codex) with a beautiful, flexible workspace powered by Bonsplit's native panel system.

### Core Philosophy

1. **Native Performance** — Built with Swift/SwiftUI for 120fps animations, instant responsiveness, and seamless macOS/iOS integration.

2. **Agents as First-Class Citizens** — Agents aren't bolted on; they're the foundation. Every workspace has agents that can write code, review changes, coordinate tasks, and work in parallel (Ralph Wiggum style).

3. **Flexible Composition** — Bonsplit-powered panels that can be arranged however you need. Drag, split, and compose your workspace.

4. **Beautiful by Default** — Shiki-style syntax highlighting, elegant diffs, and a design system that makes spending hours in the IDE a pleasure.

5. **Work from Anywhere** — Phone via Tailscale, cloud sandboxes via E2B, or local Mac runtime. Your workspace follows you.

6. **Client-Server Architecture** — Clean separation between the Devys client and server, with OpenAPI endpoints for extensibility.

---

## Design Inspiration Analysis

### Warp Terminal Style (Image 1)

The Warp-style interface demonstrates:
- **Agent Review Panel** — Right-side panel showing agent analysis of code issues
- **Inline Code Annotations** — Issues highlighted directly in code with explanations
- **File Tree Sidebar** — Organized project navigation with semantic groupings
- **Task Checklist** — Actionable items from agent analysis
- **Code Context Display** — Showing relevant code snippets with line numbers

Key UI patterns to adopt:
- Split between code view and agent feedback
- Clear visual hierarchy for issues (numbered, color-coded)
- Collapsible sections for different analysis areas
- Integration of terminal with agent outputs

### Multi-Agent Coordination (Image 2)

The Intent Product Page interface shows:
- **Agent Sidebar** — List of agents with status indicators (running, complete)
- **Coordinator Pattern** — Main orchestrator that spawns sub-agents
- **Parallel Execution** — Multiple agents working simultaneously with live progress
- **Spec Panel** — Notes, tasks, and context for the current work
- **Live Code Snippets** — Showing what each agent is actively modifying
- **Terminal Integration** — Development server running alongside agent work

Key patterns to adopt:
- Agent status with colored indicators (green=running, etc.)
- Hierarchical agent display (coordinator → sub-agents)
- Real-time streaming of agent work
- Dual-panel layout: agents + spec/context
- Progress tracking with completed/pending tasks

---

## Architecture

### Swift Package Structure

```
devys/
├── Devys.xcworkspace          # Xcode workspace
│
├── Apps/
│   ├── Devys/                 # macOS app target
│   │   ├── DevysApp.swift     # App entry point
│   │   ├── Views/             # App-level views
│   │   ├── Models/            # App-level models
│   │   └── Resources/         # Assets, Info.plist
│   │
│   └── DevysMobile/           # iOS app target
│       ├── DevysMobileApp.swift
│       └── Views/             # Mobile-specific views
│
├── Packages/
│   ├── DevysCore/             # Shared core functionality
│   │   ├── Workspace/         # Workspace management
│   │   ├── Panels/            # Panel system (Bonsplit wrapper)
│   │   ├── FileSystem/        # File operations
│   │   ├── Networking/        # API client, WebSocket
│   │   └── Models/            # Core data models
│   │
│   ├── DevysSyntax/           # Shiki-compatible syntax highlighting
│   │   ├── Oniguruma/         # Swift wrapper for Oniguruma regex
│   │   ├── TextMate/          # TMGrammar, TMTokenizer, Registry
│   │   ├── Theme/             # ShikiTheme, ThemeResolver, ThemeRegistry
│   │   ├── Integration/       # Surface adapters (Editor, Diff, Chat, Viewer)
│   │   └── Resources/         # Grammar JSONs (17), Theme JSONs (13)
│   │
│   ├── DevysEditor/           # Code editor package
│   │   ├── Editor/            # Editor view & controller
│   │   ├── Themes/            # Editor chrome themes
│   │   └── Extensions/        # Editor extensions
│   │
│   ├── DevysGit/              # Git operations package
│   │   ├── Core/              # Git2Swift wrapper
│   │   ├── Diff/              # Shiki-style diff rendering
│   │   ├── Operations/        # Commit, branch, merge, etc.
│   │   └── UI/                # Git UI components
│   │
│   ├── DevysTerminal/         # Terminal package
│   │   ├── PTY/               # Pseudo-terminal management
│   │   ├── Renderer/          # Terminal rendering (SwiftTerm)
│   │   ├── Shell/             # Shell integration
│   │   └── UI/                # Terminal UI components
│   │
│   ├── DevysAgents/           # Agent orchestration package
│   │   ├── Core/              # Agent runtime & orchestration
│   │   ├── Clients/           # Claude Code, Codex clients
│   │   ├── Streaming/         # JSON streaming handlers
│   │   ├── Ralph/             # Long-running agent system
│   │   └── UI/                # Agent UI components
│   │
│   └── DevysUI/               # Shared UI components
│       ├── DesignSystem/      # Colors, typography, spacing
│       ├── Components/        # Reusable UI components
│       └── Icons/             # SF Symbols + custom icons
│
├── Server/                    # OpenAPI backend (Native Swift or Hummingbird)
│   ├── Sources/
│   │   └── DevysServer/
│   │       ├── Routes/        # API routes
│   │       ├── Services/      # Business logic
│   │       └── OpenAPI/       # OpenAPI spec
│   └── Package.swift
│
├── .docs/                     # Documentation
│   ├── plan.md                # This file
│   ├── m1.md                  # Milestone 1 detailed spec
│   ├── m2.md                  # Milestone 2 detailed spec
│   ├── m5-terminal-port.md    # Terminal port plan
│   ├── shiki-integration.md   # Syntax highlighting across all surfaces
│   └── ...
│
└── Scripts/                   # Build & utility scripts
```

---

## Technology Stack

### Native Apps (macOS/iOS)

| Layer | Technology | Purpose |
|-------|------------|---------|
| UI Framework | SwiftUI | Declarative UI, cross-platform |
| Panel System | [Bonsplit](https://github.com/almonk/bonsplit) | Tab bar, splits, 120fps drag |
| Terminal | DevysTerminal (Metal) | GPU-accelerated terminal (ported from devys-old) |
| Git | Git2Swift / libgit2 | Native git operations |
| Syntax Coloring | TextMate + Oniguruma | Shiki-compatible highlighting (17 languages, 13 themes) |
| Syntax Structure | TreeSitter | Code folding, brackets, outline |
| Networking | URLSession + AsyncStream | API + streaming |
| Persistence | SwiftData | Local data storage |
| IPC | XPC Services | Sandboxed operations |

### Backend Server

| Layer | Technology | Purpose |
|-------|------------|---------|
| Framework | Native Swift or [Hummingbird](https://github.com/hummingbird-project/hummingbird) | Lightweight Swift backend (TBD) |
| API Spec | OpenAPI 3.1 + [Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator) | Type-safe API |
| Database | SQLite (local) / PostgreSQL (cloud) | Data persistence |
| Agent Proxies | Process spawning | Claude Code, Codex CLI |
| WebSocket | async/await streams | Real-time updates |

> **Note**: Framework decision deferred. Options are:
> - **Native Swift**: Foundation + SwiftNIO for minimal dependencies
> - **Hummingbird**: Lightweight, async/await-first, modular design

### Infrastructure

| Purpose | Technology |
|---------|------------|
| Remote Access | Tailscale | Phone access to local server |
| Cloud Sandboxes | E2B | Remote execution environments |
| Packaging | Xcode Archive / Notarization | macOS distribution |

---

## Design System

### Color Palette

```swift
// DevysColors.swift
enum DevysColors {
    // Backgrounds
    static let base = Color(hex: "#0a0a0c")        // Near-black with blue undertone
    static let surface = Color(hex: "#12131a")     // Panels, cards
    static let elevated = Color(hex: "#1a1b24")    // Modals, dropdowns
    static let border = Color(hex: "#2a2b36")      // Subtle borders
    
    // Accents
    static let primary = Color(hex: "#10b981")     // Emerald green — status, focus
    static let secondary = Color(hex: "#6366f1")   // Indigo — links, secondary
    static let warning = Color(hex: "#f59e0b")     // Amber — warnings, pending
    static let error = Color(hex: "#ef4444")       // Red — errors, destructive
    
    // Text
    static let textPrimary = Color(hex: "#f4f4f5")    // Bright white-ish
    static let textSecondary = Color(hex: "#a1a1aa")  // Muted
    static let textTertiary = Color(hex: "#71717a")   // Very muted, hints
    
    // Agent Status
    static let agentRunning = Color(hex: "#22c55e")   // Green
    static let agentPending = Color(hex: "#eab308")   // Yellow
    static let agentComplete = Color(hex: "#3b82f6")  // Blue
    static let agentError = Color(hex: "#ef4444")     // Red
}
```

### Typography

```swift
// DevysTypography.swift
enum DevysTypography {
    // UI Font: SF Pro (system default)
    static let small = Font.system(size: 12)
    static let body = Font.system(size: 13)
    static let emphasis = Font.system(size: 14, weight: .medium)
    static let heading = Font.system(size: 16, weight: .semibold)
    
    // Code Font: Berkeley Mono or JetBrains Mono
    static let code = Font.custom("Berkeley Mono", size: 13)
    static let codeSmall = Font.custom("Berkeley Mono", size: 12)
}
```

### Visual Language

- **Subtle Depth** — Background color variation instead of heavy shadows
- **Thin Borders** — 1px borders at ~10% opacity
- **Status Indicators** — Small colored dots (8px, rounded)
- **Corner Radius** — 6px panels, 4px buttons, 8px modals
- **Spacing** — 8px grid (8, 16, 24, 32, 48)
- **Animations** — 120fps, spring-based, 150-250ms duration

---

## Milestones Overview

### Milestone 1: Beautiful Interface Foundation
> **Goal**: Stunning workspace with Bonsplit-powered flexible panels

- Native macOS app scaffold with SwiftUI
- Bonsplit integration for tabs/panes/splits
- Multi-workspace management (each workspace = folder)
- File explorer sidebar with basic operations
- Panel system with drag/resize/split
- Design system implementation
- Empty panel states and workspace switching
- **File Viewer with Shiki highlighting** (read-only, for previewing files)

### Milestone 2: Agent Integration
> **Goal**: Unified interface for Claude Code and Codex

- JSON streaming wrapper for Claude Code CLI
- JSON streaming wrapper for Codex CLI
- Agent conversation UI with streaming output
- **Shiki-highlighted code blocks in agent chat**
- Agent task management and progress display
- Coordinator + sub-agent pattern (Ralph Wiggum style)
- Agent status indicators and real-time updates

### Milestone 3: Git Integration
> **Goal**: Beautiful Shiki-style git operations

- Git2Swift/libgit2 integration
- Git status, log, blame views
- **Shiki-highlighted inline diffs** (full syntax coloring per line)
- Commit, branch, merge operations
- Conflict resolution UI
- Staging area management

### Milestone 4: Code Editor
> **Goal**: Full code editing with Shiki-style highlighting

- **Full Shiki/TextMate syntax highlighting** via `ShikiHighlightProvider`
- TreeSitter for code folding, brackets, outline (structural)
- Read/write code editing
- Multiple file tabs within panes
- Search/replace functionality
- 13 bundled themes (GitHub Dark, Vitesse, Tokyo Night, etc.)
- Keyboard shortcuts (⌘S, ⌘F, etc.)

### Milestone 5: Terminal
> **Goal**: Native terminal integration

**Source**: Port from `devys-old/Packages/DevysTerminal` (GPU-accelerated Metal terminal)

**Detailed Plan**: See [m5-terminal-port.md](m5-terminal-port.md)

**Approach**: Careful integration with refactoring:

1. **Strip legacy code**:
   - Remove `DevysPaneKit` protocol dependency
   - Remove old canvas/pane mental model (TabbedTerminalWindow, etc.)
   - Adapt to Bonsplit tab content pattern

2. **Core components to keep** (production-quality):
   - `VTParser` — Complete VT100/VT220/ANSI parser (825 lines, well-tested)
   - `PtySession` — Darwin forkpty, shell hooks, non-blocking I/O
   - `ScreenBuffer` — Grid, cursor, scrollback, attributes
   - `Metal/*` — GPU rendering pipeline (shaders, glyph atlas)
   - `Input/*` — Keyboard/mouse handling

3. **Heavy testing before integration**:
   - Run existing unit tests (10 test files)
   - Manual testing matrix (vim, htop, tmux, claude CLI, ssh)
   - Performance benchmarks (target: 120fps scrolling)
   - Fix any bugs found before declaring ready

4. **Integration work**:
   - Create `TerminalPanelView` for Bonsplit tab content
   - Sync colors with Devys design system
   - Multiple terminals per workspace

### Milestone 6: Remote Access (Tailscale)
> **Goal**: Access from anywhere

- Tailscale SDK integration
- iOS companion app
- Mobile-responsive layouts
- Touch-friendly interactions
- Secure connection to local server

### Milestone 7: Cloud Execution
> **Goal**: Run in cloud sandboxes

- E2B integration
- Sandbox lifecycle management
- Remote file system operations
- Resource monitoring
- Environment persistence

---

## UI Layout Philosophy

### Main Window Structure

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Window Title Bar (native macOS traffic lights)                          │
├─────────────────────┬────────────────────────────────────────────────────┤
│                     │  Tab Bar (Bonsplit)                                │
│                     │  [Tab 1] [Tab 2] [Tab 3] [+]  [⊞] [⊟]              │
│   Activity          ├────────────────────────────────────────────────────┤
│   Sidebar           │                                                    │
│   ─────────         │           Main Canvas                              │
│   ▾ Workspaces      │        (Bonsplit Split Panes)                      │
│     📁 devys        │                                                    │
│     📁 project2     │   ┌─────────────────────┬────────────────────────┐ │
│                     │   │                     │                        │ │
│   ▾ Files           │   │   Panel 1           │      Panel 2           │ │
│     📄 main.swift   │   │   (Editor)          │      (Agent Chat)      │ │
│     📄 views/       │   │                     │                        │ │
│                     │   │                     │                        │ │
│   ▾ Agents          │   ├─────────────────────┴────────────────────────┤ │
│     ● Coordinator   │   │                                              │ │
│     ○ Code Review   │   │               Panel 3                        │ │
│     ○ Design Agent  │   │               (Terminal)                     │ │
│                     │   │                                              │ │
│   ▾ Git             │   └──────────────────────────────────────────────┘ │
│     main            │                                                    │
│     ↑2 ↓0           │                                                    │
├─────────────────────┴────────────────────────────────────────────────────┤
│  Status Bar: [Branch: main] [Agents: 2 running] [Server: Connected]     │
└──────────────────────────────────────────────────────────────────────────┘
```

### Panel Types

| Panel Type | Description | Primary Use |
|------------|-------------|-------------|
| **Editor** | Code editing with syntax highlighting | Writing/reading code |
| **Agent** | Chat interface with streaming output | Agent conversations |
| **Terminal** | Shell access | Commands, builds |
| **Diff** | Git diff viewer | Code review |
| **Files** | File browser | Navigation |
| **Preview** | Web/Markdown preview | Content preview |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Command palette |
| `⌘P` | Quick file open |
| `⌘\` | Toggle sidebar |
| `⌘D` | Split pane horizontally |
| `⌘⇧D` | Split pane vertically |
| `⌘W` | Close current tab |
| `⌘1-9` | Switch to tab N |
| `⌃Tab` | Next tab |
| `⌃⇧Tab` | Previous tab |
| `⌘⌥←→` | Navigate between panes |

---

## Agent Workflow

### Ralph Wiggum Pattern

Long-running agents that can coordinate and spawn sub-agents:

```
┌─────────────────────────────────────────────────────────────────┐
│                        COORDINATOR                               │
│  "Implement dark mode for the entire app"                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐            │
│   │ Theme Agent │  │ Toggle Agent│  │ Persist Agent│            │
│   │ ● Running   │  │ ● Running   │  │ ○ Pending   │            │
│   │             │  │             │  │             │            │
│   │ Creating    │  │ Building    │  │ Waiting for │            │
│   │ color       │  │ toggle      │  │ dependencies│            │
│   │ system...   │  │ component...│  │             │            │
│   └─────────────┘  └─────────────┘  └─────────────┘            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### JSON Streaming Protocol

Both Claude Code and Codex will be wrapped with a unified streaming interface:

```swift
protocol AgentClient {
    func stream(prompt: String) -> AsyncThrowingStream<AgentEvent, Error>
}

enum AgentEvent {
    case thinking(content: String)
    case toolUse(name: String, input: Any)
    case toolResult(output: String)
    case text(content: String)
    case codeBlock(language: String, code: String)
    case complete
    case error(message: String)
}
```

---

## Shiki-Compatible Syntax Highlighting

> **Detailed Plan**: See [shiki-integration.md](shiki-integration.md)

### Architecture: Dual-Layer System

VS Code and Cursor use a dual-layer approach — we do the same:

| System | Optimized For | We Use For |
|--------|---------------|------------|
| **TextMate** (Oniguruma regex) | Visual accuracy, theme ecosystem | Syntax **coloring** |
| **TreeSitter** (incremental parsing) | Structural accuracy | Code **intelligence** (folding, brackets, outline) |

### Core Engine (DevysSyntax Package)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DevysSyntax Package                                 │
├──────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌───────────────┐       │
│  │  Oniguruma   │ │ TMTokenizer  │ │ThemeResolver │ │  TMRegistry   │       │
│  │   Wrapper    │ │ (TextMate)   │ │ (scope→color)│ │ ThemeRegistry │       │
│  └──────────────┘ └──────────────┘ └──────────────┘ └───────────────┘       │
│                              │                                               │
│             ┌────────────────┼────────────────────┐                         │
│             ▼                ▼                    ▼                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │                      Surface Adapters                                   ││
│  │  ┌─────────────────┐ ┌─────────────────┐ ┌──────────────────────────┐   ││
│  │  │ShikiHighlight   │ │HighlightedCode  │ │DiffHighlighter           │   ││
│  │  │Provider (Editor)│ │Block (Chat)     │ │(Git diffs)               │   ││
│  │  └─────────────────┘ └─────────────────┘ └──────────────────────────┘   ││
│  └─────────────────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────────────────┘
```

### Syntax Highlighting Across All Surfaces

| Surface | Component | Method | Milestone |
|---------|-----------|--------|-----------|
| **File Viewer** | `FileViewerPanel` | Full doc async | M1 |
| **Agent Chat** | `HighlightedCodeBlock` | Per code block | M2 |
| **Git Diffs** | `DiffHighlighter` | Per diff line | M3 |
| **Code Editor** | `ShikiHighlightProvider` | Incremental, cached | M4 |
| **Terminal** | DevysTerminal (ANSI) | VT/ANSI native | M5 |

### Bundled Resources

**17 Languages** (TextMate grammars):
Swift, Python, JavaScript, TypeScript, TSX, JSX, HTML, CSS, JSON, Markdown, Ruby, Rust, C, C++, Go, PHP, Shell/Bash

**13 Themes** (Shiki themes):
- Dark: GitHub Dark, GitHub Dark Dimmed, Vitesse Dark, One Dark Pro, Tokyo Night, Dracula, Nord, Monokai, Catppuccin Mocha
- Light: GitHub Light, Vitesse Light, One Light, Catppuccin Latte

---

## Dependencies

### External Swift Packages

| Package | Version | Purpose |
|---------|---------|---------|
| [Bonsplit](https://github.com/almonk/bonsplit) | 1.1.1+ | Tab bar, split panes (pure Swift, TypeScript is just their docs site) |
| [Oniguruma](https://github.com/aspect-apps/Oniguruma) | Latest | Regex engine for TextMate grammars |
| [swift-syntax](https://github.com/apple/swift-syntax) | Latest | Swift parsing (for syntax) |
| [TreeSitter](https://github.com/AuroraEditor/AuroraEditorSourceEditor) | Latest | Code structure (folding, brackets, outline) |
| [Hummingbird](https://github.com/hummingbird-project/hummingbird) | 2.x | Backend server (optional, may use native Swift) |
| [Swift OpenAPI Generator](https://github.com/apple/swift-openapi-generator) | Latest | Type-safe API from OpenAPI spec |

### Internal Packages (ported from devys-old)

| Package | Status | Notes |
|---------|--------|-------|
| DevysTerminal | ⚠️ Needs refactoring | GPU-accelerated Metal terminal, strip DevysPaneKit dependency, heavy testing required |

### System Frameworks

- Foundation
- SwiftUI
- AppKit (macOS)
- UIKit (iOS)
- Metal (terminal rendering)
- MetalKit (terminal rendering)
- CoreText (glyph rendering)
- Combine
- SwiftData

---

## Success Metrics

| Metric | Target |
|--------|--------|
| App Launch | < 500ms cold start |
| First Meaningful Paint | < 1s |
| Panel Resize/Drag | 120fps |
| Tab Switch | < 50ms |
| Agent Streaming Latency | < 100ms perceived |
| Syntax Highlighting | No visible flash on load |
| Memory (idle) | < 150MB |
| Memory (per workspace) | < 50MB additional |

---

## Development Principles

1. **Swift-First** — Leverage Swift's type system, concurrency, and SwiftUI for everything possible.

2. **Package Isolation** — Each package (Editor, Git, Terminal, Agents) should be independently testable and usable.

3. **Async/Await Native** — Use modern Swift concurrency throughout, no callback hell.

4. **Accessibility** — VoiceOver support, keyboard navigation, Dynamic Type.

5. **Offline First** — Core functionality works without network; agents/sync are additive.

---

*This document evolves as we build. Last updated: January 2026*
