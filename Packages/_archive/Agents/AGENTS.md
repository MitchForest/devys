# DevysAgents

Native Swift package providing a unified interface to AI coding agent CLIs (OpenAI Codex and Anthropic Claude Code).

## Overview

DevysAgents is a Swift 6 package that wraps the Codex and Claude Code command-line interfaces, providing:

- **Unified event streaming** across both agent harnesses
- **SwiftUI views** for chat interfaces, sidebars, and message composition
- **Session management** with persistence and discovery
- **Approval handling** for dangerous operations
- **Skills system** integration (Codex)

The package abstracts away the differences between the two CLI protocols, presenting a single `AgentEvent` stream to the UI layer.

## Architecture

### High-Level Design

```
+------------------+     +------------------+     +------------------+
|   SwiftUI Views  | --> |   ChatSession    | --> |   DevysAgent     |
| (ChatSessionView)|     | (State Manager)  |     | (API Facade)     |
+------------------+     +------------------+     +------------------+
                                                          |
                              +---------------------------+
                              |                           |
                    +---------v---------+       +---------v---------+
                    |   CodexClient     |       | ClaudeCodeClient  |
                    | (JSON-RPC stdio)  |       | (NDJSON stdio)    |
                    +-------------------+       +-------------------+
                              |                           |
                    +---------v---------+       +---------v---------+
                    |   codex CLI       |       |   claude CLI      |
                    | (App Server mode) |       | (stream-json)     |
                    +-------------------+       +-------------------+
```

### Core Components

#### 1. Agent Layer (`DevysAgent`)

The main entry point for interacting with agent harnesses:

- Creates and manages `CodexClient` or `ClaudeCodeClient` based on `HarnessType`
- Provides a unified `AsyncStream<AgentEvent>` for all events
- Handles thread/turn management (Codex) and query/response (Claude)
- Manages approval responses across both protocols

#### 2. Harness Clients

**CodexClient** (`Services/Harness/CodexClient.swift`)
- Communicates via JSON-RPC over stdio with `codex app-server`
- Manages thread lifecycle: `thread/start`, `thread/resume`, `thread/list`
- Handles turn execution: `turn/start`, `turn/interrupt`
- Processes skills: `skills/list`, `skills/config/write`
- Requires approval responses for dangerous commands

**ClaudeCodeClient** (`Services/Harness/ClaudeCodeClient.swift`)
- Communicates via NDJSON (newline-delimited JSON) over stdio
- Invoked with: `claude -p --input-format=stream-json --output-format=stream-json`
- Supports session resume via `--resume <sessionId>`
- Handles `control_request`/`control_response` for approvals

#### 3. Event System

Events flow through three layers:

1. **Harness-specific events** (`CodexEvent`, `ClaudeCodeEvent`)
   - Parsed directly from CLI output
   - Contain protocol-specific details

2. **Unified events** (`AgentEvent`)
   - Normalized representation for UI consumption
   - Includes: `messageDelta`, `messageComplete`, `turnCompleted`, `approvalRequired`, `toolStarted`, `toolOutput`, `toolCompleted`, `error`, `reasoningDelta`, `sessionStarted`, `raw`

3. **UI updates** via `ChatSession` observable

#### 4. Session Management

**ChatSession** (`Models/ChatSession.swift`)
- `@Observable` class managing single chat state
- Handles lifecycle: `start()`, `stop()`, `restart()`
- Manages message array and streaming state
- Coordinates approval flow
- Loads history from disk on resume

**ChatStore** (`Models/ChatStore.swift`)
- `@Observable` container for sidebar state
- Discovers sessions from both harnesses
- Manages CRUD operations on chat items
- Background polling for new sessions

## File Organization

```
Sources/DevysAgents/
+-- Models/
|   +-- AgentConfiguration.swift   # Sandbox modes, approval policies, presets
|   +-- AgentEvent.swift           # Unified event enum + AgentApproval
|   +-- ChatDeleteResult.swift     # Deletion result enum
|   +-- ChatItem.swift             # Sidebar item model + Transferable
|   +-- ChatMessage.swift          # Message model + ToolCallDisplay
|   +-- ChatSession.swift          # Per-chat state manager
|   +-- ChatSession+Approvals.swift
|   +-- ChatSession+Skills.swift
|   +-- ChatSession+TabContentProvider.swift
|   +-- ChatStore.swift            # Sidebar state container
|   +-- CodexJSON.swift            # Sendable JSON wrappers
|   +-- CodexThread.swift          # Thread model + ApprovalRequest
|   +-- ComposerAttachment.swift   # Attachment types for composer
|   +-- HarnessType.swift          # Codex vs Claude Code enum
|   +-- LLMModel.swift             # Model definitions + tiers
|
+-- Services/
|   +-- AgentLogging.swift         # OSLog bootstrap
|   +-- AgentSessionService.swift  # Protocol + default impl
|   +-- ChatDiscoveryService.swift # Session discovery
|   +-- ChatHistoryService.swift   # History loading
|   +-- ChatPersistenceService.swift # Archive/restore/delete
|   +-- ClaudePathCoder.swift      # Path escaping for Claude dirs
|   +-- CodexThreadService.swift   # Thread listing/archiving
|   +-- CommandCleaner.swift       # Shell wrapper stripping
|   +-- DevysAgents.swift          # Main DevysAgent class
|   +-- SessionHistoryLoader.swift # JSONL parsing
|   +-- SkillService.swift         # Codex skills management
|   +-- Harness/
|       +-- ActiveHarness.swift    # Runtime harness wrapper
|       +-- ClaudeCodeClient.swift # Claude CLI wrapper
|       +-- ClaudeCodeEvent.swift  # Claude event parsing
|       +-- CodexClient.swift      # Codex CLI wrapper
|       +-- CodexConfiguration.swift # Config.toml reader
|       +-- CodexError.swift       # Error types
|       +-- CodexEvent.swift       # Codex event parsing
|
+-- Views/
    +-- ChatRowView.swift          # Sidebar row
    +-- ChatSessionView.swift      # Main chat view
    +-- ChatSidebarView.swift      # Sidebar container
    +-- ChatSidebarView+Sections.swift
    +-- Components/
    |   +-- ApprovalSheet.swift    # Permission dialog
    |   +-- HarnessPicker.swift    # Harness selection
    |   +-- MessageBubble.swift    # Message rendering
    |   +-- ModelPicker.swift      # Model selection
    |   +-- ToolCallCard.swift     # Tool execution display
    +-- Composer/
        +-- AttachmentChipView.swift
        +-- ChatComposerView.swift
        +-- ComposerToolbar.swift
```

## Key Types

### Models

| Type | Purpose |
|------|---------|
| `HarnessType` | Enum: `.codex`, `.claudeCode` with binary paths, capabilities |
| `LLMModel` | Type-safe model IDs (Claude 4.5, Codex 5.x) with metadata |
| `AgentConfiguration` | Sandbox mode + approval policy + network settings |
| `AgentEvent` | Unified event type for UI consumption |
| `ChatSession` | `@Observable` per-chat state manager |
| `ChatStore` | `@Observable` sidebar state container |
| `ChatItem` | Sidebar row data (id, title, harness, model, timestamps) |
| `ChatMessage` | Display message with role, content, tool calls |
| `ToolCallDisplay` | Tool execution state (id, name, input, output, status) |
| `ComposerAttachment` | File, git diff, URL, or code snippet attachment |

### Services

| Service | Protocol | Purpose |
|---------|----------|---------|
| `AgentSessionService` | Yes | Wraps DevysAgent for ChatSession |
| `ChatDiscoveryService` | Yes | Discovers sessions from disk |
| `ChatHistoryService` | Yes | Loads message history from JSONL |
| `ChatPersistenceService` | Yes | Archive/restore/delete operations |
| `SkillService` | Yes | Codex skills management |
| `CodexThreadService` | Yes | Codex thread listing |

### Views

| View | Purpose |
|------|---------|
| `ChatSessionView` | Main chat interface with header, messages, composer |
| `ChatSidebarView` | Session list with active/archived sections |
| `ChatComposerView` | Floating input with attachments, model picker |
| `MessageBubble` | Role-based message rendering |
| `ToolCallCard` | Expandable tool execution display |
| `ApprovalSheet` | Permission request modal |
| `ModelPicker` | LLM model dropdown |
| `HarnessPicker` | Harness selection dropdown |

## Dependencies

From `Package.swift`:

```swift
dependencies: [
    .package(path: "../DevysCore"),    // Core utilities, TabContentProvider
    .package(path: "../DevysSyntax"),  // Syntax highlighting (unused in main code)
    .package(path: "../DevysUI"),      // Theme system, colors, MarkdownText
    .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
]
```

### DevysCore

- `TabContentProvider` protocol (ChatSession conforms)
- `GitDiffTransfer` for drag-drop
- `UTType.devysChatItem`, `UTType.devysGitDiff` content types

### DevysUI

- `DevysTheme` environment key
- `DevysColors` for consistent coloring
- Theme properties: `base`, `surface`, `elevated`, `accent`, `accentMuted`, `text`, `textSecondary`, `textTertiary`, `border`, `borderSubtle`

### swift-log

- `Logger` instances throughout for debugging
- `AgentLogging.bootstrap()` configures OSLog backend
- View logs: `log stream --predicate 'subsystem BEGINSWITH "devys"' --level debug`

## Concurrency Patterns

### Swift 6 Strict Concurrency

The package uses Swift 6 language mode with strict concurrency:

```swift
swiftSettings: [
    .swiftLanguageMode(.v6),
    .enableExperimentalFeature("StrictConcurrency"),
]
```

### Actor Isolation

- `CodexClient` and `ClaudeCodeClient` are `actor` types
- `DevysAgent`, `ChatSession`, `ChatStore` are `@MainActor`
- Event streams use `nonisolated let events: AsyncStream<Event>`

### Sendable Compliance

- All event types are `Sendable`
- JSON wrappers (`CodexJSON`, `RawPayload`) are `@unchecked Sendable` with documented safety rationale
- Model types (`ChatItem`, `ChatMessage`, etc.) are `Sendable`

### AsyncStream Pattern

```swift
// Client initialization
actor CodexClient {
    nonisolated let events: AsyncStream<CodexEvent>
    private let eventContinuation: AsyncStream<CodexEvent>.Continuation

    init() {
        var continuation: AsyncStream<CodexEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }
}

// Event forwarding in DevysAgent
private func forwardEvents() async {
    for await event in harness.events {
        eventContinuation.yield(event.toAgentEvent())
    }
    eventContinuation.finish()
}
```

## SwiftUI Patterns

### Observable Macro

```swift
@MainActor
@Observable
public final class ChatSession {
    public internal(set) var state: State = .idle
    public private(set) var messages: [ChatMessage] = []
    public var pendingApproval: AgentApproval?
}
```

### Environment Values

```swift
@Environment(\.devysTheme) private var theme
```

### Task Lifecycle

```swift
.task(id: session.chatItem.id) {
    if session.state == .idle {
        await session.start()
    }
}
```

### Bindable Property Wrapper

```swift
@Bindable var session: ChatSession
```

## CLI Invocation

### Codex App Server

```bash
codex app-server \
  --enable collab \
  --enable child_agents_md \
  -c 'model="gpt-5.2-codex"'
```

JSON-RPC methods:
- `initialize`, `initialized`
- `thread/start`, `thread/resume`, `thread/list`, `thread/archive`
- `turn/start`, `turn/interrupt`
- `skills/list`, `skills/config/write`

### Claude Code

```bash
claude -p \
  --input-format=stream-json \
  --output-format=stream-json \
  --permission-prompt-tool=stdio \
  --permission-mode=default \
  --verbose \
  --include-partial-messages \
  --replay-user-messages \
  --model claude-opus-4-5-20251101 \
  [--resume <sessionId>]
```

Message types:
- Input: `user`, `control_response`
- Output: `system`, `stream_event`, `assistant`, `user`, `permission_request`, `control_request`, `result`, `error`

## Session Storage

### Claude Code Sessions

- Pre-v1.0.30: `~/.claude/projects/<escaped-path>/<sessionId>.jsonl`
- v1.0.30+: `~/.config/claude/projects/<escaped-path>/<sessionId>.jsonl`
- Path escaping: `/` -> `-`, ` ` -> `%20`

### Codex Sessions

- `~/.codex/sessions/<year>/<month>/<day>/<threadId>.jsonl`
- Config: `~/.codex/config.toml`

## Public API Surface

### Main Entry Points

```swift
// Create agent
let agent = await DevysAgent(harnessType: .codex, cwd: "/path", model: .codex52)

// Start and listen
try await agent.start()
for await event in agent.events {
    switch event {
    case .messageDelta(let text): print(text)
    case .approvalRequired(let req): try await agent.respondToApproval(req, decision: .approve)
    case .turnCompleted: break
    default: break
    }
}

// Codex thread operations
let thread = try await agent.startThread(cwd: "/path")
let turnId = try await agent.send("Fix the bug", to: thread.id, cwd: "/path")

// Claude query
try await agent.query("Explain this code")

// Stop
await agent.stop()
```

### View Integration

```swift
// Sidebar
ChatSidebarView(
    store: chatStore,
    onPreviewChat: { chat in /* preview in tab */ },
    onOpenChat: { chat in /* open permanent tab */ },
    onNewChat: { /* create new chat */ }
)

// Chat view
ChatSessionView(session: chatSession)

// Compose manually
ChatComposerView(
    text: $text,
    attachments: $attachments,
    isFocused: $focused,
    selectedHarness: .claudeCode,
    selectedModel: $model,
    isStreaming: false,
    onSend: { /* send */ },
    onStop: { /* stop */ }
)
```

## Configuration

### Agent Presets

| Preset | Sandbox | Approval | Use Case |
|--------|---------|----------|----------|
| `safeReadOnly` | readOnly | onRequest | Browsing untrusted code |
| `fullAuto` | workspaceWrite | onRequest | Default for trusted repos |
| `autoEdit` | workspaceWrite | untrusted | Edit freely, ask for commands |
| `ciReadOnly` | readOnly | never | CI/automation |
| `autonomous` | workspaceWrite | never | Full auto in workspace |
| `yolo` | dangerFullAccess | never | No limits |

### Risk Levels

- `low`: Read operations
- `medium`: Workspace writes
- `high`: Full access OR no approval
- `extreme`: Full access AND no approval

## Testing

Test target: `DevysAgentsTests`

Services use protocol injection for testability:

```swift
init(
    projectFolder: URL?,
    discoveryService: ChatDiscoveryService,  // injectable
    persistenceService: ChatPersistenceService  // injectable
)
```

## Logging

Enable debug logging:

```swift
// At app startup
AgentLogging.bootstrap(minLevel: .debug)
```

View logs:
```bash
log stream --predicate 'subsystem BEGINSWITH "devys"' --level debug
```

Subsystems:
- `devys.agent`
- `devys.chat-session`
- `devys.codex`
- `devys.claude`
- `devys.chat-discovery`
- `devys.chat-persistence`
- `devys.session-history`

## Platform Requirements

- macOS 14+
- Swift 6.0
- Requires `codex` and/or `claude` CLI binaries installed

## License

Copyright 2026 Devys. All rights reserved.
