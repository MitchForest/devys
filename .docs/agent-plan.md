# Devys Agents Plan

Updated: 2026-04-07

## Goal

Introduce first-class `Agents` into Devys so users can talk to coding agents through a real IDE-native UI that is fully integrated with:

- windows
- repositories
- workspaces
- splits
- tabs
- terminals
- editor state
- drag and drop
- file and diff context

This is not a “chat widget” project. It is a workspace-native agent system for an agent-first IDE.

## Naming Decision

We will call this feature area `Agents`.

We will not call it:

- `Rich Agents`
- `Rich Text Agents`
- `Composer`
- `Assistant`

`Composer` remains a subcomponent name for the input surface only.

## Product Decisions

These decisions are the source of truth for implementation.

### 1. Devys will be a native Swift ACP client

Devys will implement the Agent Client Protocol client/runtime in native Swift.

That includes:

- ACP stdio transport
- JSON-RPC request/response correlation
- capability negotiation
- session lifecycle
- prompt streaming
- tool call updates
- permission requests
- config option changes
- terminal method handling
- session persistence and resume

### 2. Devys will not ship native Swift Codex or Claude adapters in v1

We will not write and maintain first-party Swift adapters for Codex or Claude in the first implementation.

Instead, v1 will launch upstream ACP adapters as subprocesses:

- Codex: `zed-industries/codex-acp`
- Claude: `agentclientprotocol/claude-agent-acp`

Reasons:

- ACP already expects the client to launch the agent subprocess over stdio
- upstream adapters already implement the hard agent-specific translation layer
- Codex ACP depends on internal/fast-moving Codex Rust crates
- Claude ACP depends on the official Claude Agent SDK
- Swift has no official ACP SDK today, so the highest-leverage code for us to own is the client side, not two separate adapter implementations

### 3. Terminal-mode agents and ACP agents are separate product modes

Devys already has plain terminal launch paths for Claude and Codex.

We will keep those as:

- raw CLI terminal mode

We will add:

- ACP-based `Agents` mode

These modes share:

- the same workspace
- the same worktree
- the same split/tab/window model
- the same auth/environment setup where possible

They do not need to share the exact same subprocess or transcript in v1.

### 4. Agents are workspace-owned runtime, not app-global runtime

Agent sessions belong to a workspace, parallel to terminals and editor sessions.

Consequences:

- agent tabs carry `workspaceID`
- switching workspace swaps active agent runtime
- agent state persists with workspace shell state
- agent session restore happens per workspace

### 5. Agents are split/tab-native, not sidebar-only

Conversations are first-class tabs and panes inside the split system.

We may add an `Agents` sidebar/rail entry for discovery and thread management, but the canonical place where a session lives is the split canvas.

### 6. The UI is transcript-plus-artifacts, not bubble-only chat

The conversation surface must render:

- user messages
- assistant messages
- tool calls
- tool progress
- approvals
- plan updates
- file diffs
- follow-along locations
- inline terminals
- errors
- session metadata

This is an IDE timeline, not a consumer messaging UI.

### 7. Context is explicit and inspectable

Users must be able to see what context they are sending:

- file chips
- diff chips
- image chips
- pasted snippets
- `@` mentions
- current workspace root
- active model/mode/reasoning selectors

Hidden context accumulation is not acceptable.

### 8. ACP config options are the primary control surface

If an agent exposes ACP `configOptions`, Devys will use those as the primary UI for:

- mode
- model
- reasoning / thought level
- any other session-level configuration

We will not build a mode-only abstraction that ignores ACP’s current direction.

### 9. Inline terminals are required

ACP terminal requests must render inline in the transcript and also support promotion into full terminal tabs when needed.

The terminal substrate should reuse Ghostty-backed terminal ownership already present in Devys.

### 10. File system operations must respect unsaved editor state

ACP file reads must be able to source unsaved editor buffers, not only disk state.

This is a core IDE integration advantage and should be treated as a requirement, not a polish item.

### 11. Composer speech-to-text will use Apple SpeechAnalyzer APIs

The `Agents` composer will support speech-to-text using Apple’s Speech framework, centered on:

- `SpeechAnalyzer`
- `SpeechTranscriber`

When the preferred transcriber is unavailable for the current device, locale, or asset state, Devys may fall back to Apple’s dictation-compatible path through:

- `DictationTranscriber`

We will not add a third-party cloud speech-to-text dependency for v1.

## Non-Goals

These are explicitly out of scope for the first delivery unless a ticket below says otherwise.

- authoring a first-party Swift Codex ACP adapter
- authoring a first-party Swift Claude ACP adapter
- supporting remote ACP transport beyond stdio
- making raw terminal sessions and ACP sessions share one transcript
- generic “bring any agent” plugin architecture before Codex and Claude are solid
- iOS implementation
- browser-based agent UI
- cross-workspace mixed-agent panes in a single canvas state

## Relevant References

### Upstream ACP

- ACP repo: https://github.com/agentclientprotocol/agent-client-protocol
- ACP architecture: https://agentclientprotocol.com/get-started/architecture
- ACP initialization: https://agentclientprotocol.com/protocol/initialization
- ACP session setup: https://agentclientprotocol.com/protocol/session-setup
- ACP prompt/content: https://agentclientprotocol.com/protocol/content
- ACP tool calls: https://agentclientprotocol.com/protocol/tool-calls
- ACP file system: https://agentclientprotocol.com/protocol/file-system
- ACP terminals: https://agentclientprotocol.com/protocol/terminals
- ACP plan updates: https://agentclientprotocol.com/protocol/agent-plan
- ACP session config options: https://agentclientprotocol.com/protocol/session-config-options
- ACP slash commands: https://agentclientprotocol.com/protocol/slash-commands
- ACP transports: https://agentclientprotocol.com/protocol/transports
- ACP supported agents list: https://agentclientprotocol.com/get-started/agents

### Upstream Adapters

- Codex ACP: https://github.com/zed-industries/codex-acp
- Claude Agent ACP: https://github.com/agentclientprotocol/claude-agent-acp

### Apple Speech References

- Speech framework overview: https://developer.apple.com/documentation/Speech
- `SpeechTranscriber`: https://developer.apple.com/documentation/speech/speechtranscriber
- `DictationTranscriber`: https://developer.apple.com/documentation/speech/dictationtranscriber
- Live audio speech sample: https://developer.apple.com/documentation/Speech/recognizing-speech-in-live-audio
- SpeechAnalyzer guide: https://developer.apple.com/documentation/Speech/bringing-advanced-speech-to-text-capabilities-to-your-app
- Speech recognition permission: https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition

### Local Devys References

- Live tab content model:
  - `Apps/mac-client/Sources/mac/Models/TabContent.swift`
- Split/tab root configuration:
  - `Apps/mac-client/Sources/mac/Views/Window/ContentView.swift`
- Workspace-owned shell state:
  - `Apps/mac-client/Sources/mac/Models/WorkspaceShellState.swift`
- Workspace runtime registry:
  - `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`
- Workspace terminal registry:
  - `Apps/mac-client/Sources/mac/Services/WorkspaceTerminalRegistry.swift`
- Terminal relaunch/layout persistence:
  - `Apps/mac-client/Sources/mac/Views/Window/ContentView+TerminalPersistence.swift`
- Sidebar observation surfaces:
  - `Apps/mac-client/Sources/mac/Views/Window/ContentView+ObservationSurfaces.swift`
- File tree hooks for add-to-chat:
  - `Apps/mac-client/Sources/mac/Views/FileTree/FileTreeView.swift`
  - `Apps/mac-client/Sources/mac/Views/FileTree/FileTreeRow.swift`
- Shared drag/drop UTTypes:
  - `Packages/Workspace/Sources/Core/Models/DragDropTypes.swift`
- Split external drop delegate surface:
  - `Packages/Split/Sources/Split/Public/DevysSplitDelegate.swift`
  - `Packages/Split/Sources/Split/Public/Types/DropContent.swift`
- Chat design tokens:
  - `Packages/UI/Sources/UI/Models/DesignSystem/ChatTokens.swift`
- Existing raw Claude/Codex launch paths:
  - `Apps/mac-client/Sources/mac/Views/Window/ContentView+LaunchActions.swift`
  - `Apps/mac-client/Sources/mac/Views/Window/ContentView+AgentNotifications.swift`
- Editor unsaved-buffer registry:
  - `Apps/mac-client/Sources/mac/Models/EditorSession.swift`

### Archived Prior Art To Reuse Selectively

These are references, not packages to restore wholesale.

- Archived chat tab wiring:
  - `Apps/mac-client/_archive/ContentView+Chat.swift`
- Archived unified agent event model:
  - `Packages/_archive/Agents/Sources/Agents/Models/AgentEvent.swift`
- Archived block rendering model:
  - `Packages/_archive/Agents/Sources/Agents/Models/ChatItemBlock.swift`
- Archived Codex / Claude wrappers:
  - `Packages/_archive/Agents/Sources/Agents/Services/Harness/CodexClient.swift`
  - `Packages/_archive/Agents/Sources/Agents/Services/Harness/ClaudeCodeClient.swift`
- Archived composer attachment model:
  - `Packages/_archive/Chat/Sources/ChatUI/Models/ComposerAttachment.swift`

## Current Snapshot

Current state in the live app:

- Devys already has workspace-owned terminals, editors, split panes, persisted layout, and drag/drop seams
- the live `TabContent` model does not currently include agent/chat tabs
- the live sidebar/file tree still exposes `onAddToChat` seams but they are not wired to an active agent surface
- the split system already supports custom external drops, which is the right seam for file/diff/image chips
- terminal launch buttons for `Claude` and `Codex` exist today, but they launch raw CLI sessions, not ACP sessions
- the repo contains archived agent/chat code that is useful as prior art but should not be restored wholesale

## Required User Experience

The first acceptable product bar is:

- user can open an `Agents` tab in any pane
- user can choose Codex or Claude
- user can talk to the selected agent in a workspace-rooted session
- user can drag files and diffs into the composer as chips
- user can attach images
- user can see tool execution, approvals, plans, diffs, and terminal output inline
- user can split, move, and persist agent tabs exactly like editor and terminal tabs
- user can leave a workspace and return without losing that workspace’s agent state
- user can restore previously open agent tabs on relaunch when the agent supports session loading

Anything less is not the target bar.

## Architecture Shape

### Core packages and responsibilities

#### `ACPClientKit` (new package)

Responsibilities:

- ACP transport and protocol client
- JSON-RPC message types
- request/response bookkeeping
- ACP session runtime
- adapter process launch/termination
- capability model
- error model

Key types:

- `ACPTransportStdio`
- `ACPConnection`
- `ACPAgentDescriptor`
- `ACPAdapterLauncher`
- `ACPSessionClient`
- `ACPEventStream`
- `ACPRequestID`
- `ACPSessionID`
- `ACPClientCapabilities`

#### `AgentsUI` or `Agents` (new package or app-local module)

Responsibilities:

- transcript view
- tool cards
- approval UI
- composer
- attachment chips
- slash command picker
- config option controls
- inline terminal cards
- follow mode

Key types:

- `AgentSessionView`
- `AgentTranscriptView`
- `AgentComposerView`
- `AgentAttachment`
- `AgentMessage`
- `AgentTimelineItem`
- `AgentToolCallViewModel`
- `AgentApprovalViewModel`

#### mac client integration

Responsibilities:

- `TabContent` integration
- split/drop wiring
- workspace runtime ownership
- persistence/restore
- toolbar/sidebar/command palette entry points
- editor/terminal bridge implementation for ACP methods

## Canonical Data Model

### New tab identity

Add a new live tab case:

```swift
case agentSession(workspaceID: Workspace.ID, sessionID: AgentSessionID)
```

This must be treated as a first-class peer of:

- terminal
- editor
- gitDiff

### Workspace-owned agent runtime

Add a workspace-owned registry parallel to the terminal registry:

- `WorkspaceAgentRuntimeRegistry`

Expected responsibilities:

- hold workspace-local ACP connections or session runtimes
- hold active session view models
- coordinate tab/session lookup
- preserve session state when workspace focus changes
- participate in restore and teardown

### Attachment model

Create a live attachment model that supersedes the archived one:

- files
- git diffs
- images
- URLs
- code snippets
- optional generated context blocks

The chip model must be serializable enough for drag/drop and local draft persistence if needed.

### Transcript model

Do not model the transcript as plain strings.

The transcript needs structured timeline items such as:

- `userMessage`
- `assistantMessage`
- `toolCall`
- `approvalRequest`
- `planUpdate`
- `terminalEmbed`
- `diffArtifact`
- `status`
- `error`

## UX Rules

### Composer

The composer must support:

- multiline text entry
- attachment chip tray
- drag/drop from tree, git sidebar, Finder, and image sources
- slash command completion
- `@` mention completion for workspace files
- keyboard send and stop flows
- visible current harness badge
- visible current model/mode/reasoning controls

### Transcript

The transcript must support:

- streaming text
- collapsible tool cards
- explicit approval affordances
- inline diffs
- inline terminals
- pinned system/status rows
- stable scroll behavior while streaming
- clear distinction between user-authored and agent-authored artifacts

### Follow mode

The user must be able to opt into “follow agent” behavior where active tool locations open or reveal files as the agent works.

This must be:

- explicit
- toggleable
- non-destructive to existing tab layout

### Error states

We need first-class UI for:

- missing adapter binary
- auth required
- incompatible ACP capability
- failed session restore
- adapter crash
- terminal method failure
- permission request timeout/cancel

## Delivery Phases

The delivery order below is mandatory unless a later ticket is explicitly pulled forward for a blocking reason.

### Phase 0: Foundation

- `AGNT-000`
- `AGNT-001`
- `AGNT-002`

### Phase 1: Session UI and runtime

- `AGNT-010`
- `AGNT-011`
- `AGNT-012`
- `AGNT-013`

### Phase 2: IDE integration

- `AGNT-020`
- `AGNT-021`
- `AGNT-022`
- `AGNT-023`

### Phase 3: Persistence and polish

- `AGNT-030`
- `AGNT-031`
- `AGNT-032`
- `AGNT-033`

## Tickets

Each ticket below is written to be implementable and testable. Acceptance criteria are strict.

### `AGNT-000` Create native Swift ACP client package

Scope:

- create a new package for ACP client/runtime code
- implement newline-delimited JSON-RPC stdio transport
- implement request/response correlation and notification dispatch
- implement initialize handshake and capability negotiation
- implement connection shutdown and process crash handling

Primary touch points:

- new package under `Packages/`
- app integration via `Apps/mac-client/Sources/mac/Services/AppContainer.swift`

Acceptance criteria:

- package builds independently with unit tests
- client can launch a fake ACP test process and complete `initialize`
- client correctly handles:
  - responses
  - notifications
  - stderr logging
  - EOF / process termination
- no message written to adapter stdin contains non-ACP payload
- transport enforces newline-delimited JSON messages
- process crash is surfaced as a typed error, not silent stream termination

### `AGNT-001` Add adapter descriptors and launcher strategy for Codex and Claude

Scope:

- define agent descriptors for Codex and Claude adapters
- support configured executable path, bundled helper path, and PATH resolution
- add environment preparation for auth and launch
- define user-facing diagnostics for missing adapters

Acceptance criteria:

- Devys can resolve and launch:
  - `codex-acp`
  - `claude-agent-acp`
- launcher failure distinguishes:
  - binary not found
  - spawn failed
  - initialize failed
  - unsupported protocol/capability
- there is one source of truth for supported agent kinds
- no raw shell-command string concatenation is used for ACP adapter launch
- adapter selection is available from code without UI dependency

### `AGNT-002` Define live agent domain models and workspace runtime ownership

Scope:

- add live agent runtime/state models
- add workspace-owned agent registry
- add `TabContent.agentSession`
- add tab metadata support for agent tabs
- define transcript item and attachment models

Primary touch points:

- `Apps/mac-client/Sources/mac/Models/TabContent.swift`
- `Apps/mac-client/Sources/mac/Models/WorkspaceShellState.swift`
- `Apps/mac-client/Sources/mac/Services/WorktreeRuntimeRegistry.swift`

Acceptance criteria:

- agent tabs are first-class `TabContent`
- workspace shell state can hold agent tab/session ownership without global singleton leakage
- workspace switching preserves inactive workspace agent state in memory
- tab titles/icons update from live session metadata rather than frozen creation state
- new models compile without depending on archived packages
- tests cover stable tab identity and workspace isolation for agent sessions

### `AGNT-010` Build minimal `Agents` tab UI with transcript and composer

Scope:

- create the first live agent tab content view
- render transcript rows for user and assistant text
- render a composer with multiline input and send/stop behavior
- allow creating a new Codex or Claude session from UI

Acceptance criteria:

- user can open an agent tab from within Devys
- user can select Codex or Claude for a new session
- user can send a prompt and receive streamed text
- stop cancels the in-flight prompt through ACP `session/cancel`
- the tab works inside existing split panes and supports pane moves
- UI does not block the main thread during streaming
- the transcript remains readable during long streaming responses

### `AGNT-011` Render ACP artifacts: tool calls, approvals, plans, diffs, statuses

Scope:

- map ACP notifications into structured timeline items
- render tool call cards with status changes
- render approval requests
- render plan updates
- render diff artifacts
- render system/status rows

Acceptance criteria:

- `tool_call` and `tool_call_update` notifications render as one evolving card, not duplicate rows
- approval requests expose all provided options and preserve the selected result
- plan updates replace the prior plan state as ACP expects
- diff artifacts are visually distinct from plain text
- location metadata is preserved on tool rows for follow mode
- transcript rendering uses structured state, not string parsing

### `AGNT-012` Add session config options and slash command UX

Scope:

- render ACP `configOptions`
- support setting config options during idle and active sessions
- surface slash commands advertised by the adapter
- support command insertion/selection from the composer

Acceptance criteria:

- session config options render in agent-provided order
- `category: mode`, `category: model`, and `category: thought_level` receive first-class UI treatment
- config changes call `session/set_config_option` and reconcile with returned full state
- Devys does not build new UX on top of deprecated ACP modes when config options are present
- slash commands update dynamically when the agent sends `available_commands_update`
- the composer can insert and send slash commands without freeform string guessing

### `AGNT-013` Add speech-to-text input to the `Agents` composer using Apple SpeechAnalyzer

Scope:

- add microphone input to the live `Agents` composer
- use Apple Speech framework APIs centered on `SpeechAnalyzer`
- prefer `SpeechTranscriber` for general-purpose transcription
- fall back to `DictationTranscriber` only when the preferred path is unavailable
- support live insertion into the active composer draft
- handle permission, availability, and locale/asset failures explicitly

Acceptance criteria:

- the composer has a microphone affordance that starts and stops speech capture
- recognized text is inserted into the current draft without destroying existing typed content
- partial/live transcription updates are visible while recording
- ending capture produces stable final text in the draft
- the app declares the required speech recognition usage description in `Info.plist`
- microphone permission denial produces explicit UX and does not leave the composer in a broken state
- speech recognition unavailability produces explicit UX and does not silently fail
- locale/model availability is checked before starting capture
- the implementation uses Apple Speech framework APIs and does not depend on third-party cloud STT services
- automated coverage exists for:
  - permission-denied state
  - unavailable-transcriber state
  - successful transcript insertion into an existing non-empty draft

### `AGNT-020` Implement attachment chips and drag/drop from files, diffs, and images

Scope:

- build live attachment chip UI
- wire file tree “add to chat” flows into live agent tabs
- wire git diff “add to chat” flows into live agent tabs
- support external file/image drops into agent tabs and panes
- support creating a new agent tab when dropping onto an empty pane/edge

Primary touch points:

- `Apps/mac-client/Sources/mac/Views/FileTree/FileTreeView.swift`
- `Apps/mac-client/Sources/mac/Views/Window/ContentView+ObservationSurfaces.swift`
- `Packages/Workspace/Sources/Core/Models/DragDropTypes.swift`
- `Packages/Split/Sources/Split/Public/DevysSplitDelegate.swift`

Acceptance criteria:

- file chips can be added from context menu and drag/drop
- git diff chips can be added from context menu and drag/drop
- image files dropped into the composer become image attachments
- dropping onto a pane edge can create a split and open an agent tab there
- duplicate attachments are handled intentionally:
  - either deduplicated
  - or rendered distinctly with a clear rule
- drag/drop behavior works across panes in the same window

### `AGNT-021` Implement ACP prompt content for files, diffs, images, and mentions

Scope:

- translate attachment chips into ACP prompt content blocks
- use `resource` embedded context where appropriate
- use `resource_link` where full embedding is not appropriate
- support image prompt blocks
- add workspace file mention resolution for `@`

Acceptance criteria:

- text prompts remain plain text blocks
- file context can be sent as ACP embedded resources with path and content
- large/binary/unsupported files fall back to `resource_link` or a rejected attachment state with explicit UX
- images are sent as ACP image content only when the selected agent advertises image prompt capability
- mention insertion resolves against the active workspace root only
- the user can inspect which exact resources will be sent before sending

### `AGNT-022` Bridge ACP filesystem methods to editor truth and disk truth

Scope:

- implement `fs/read_text_file`
- implement `fs/write_text_file`
- prefer unsaved editor buffer reads
- reconcile writes with open editor sessions

Primary touch points:

- `Apps/mac-client/Sources/mac/Models/EditorSession.swift`
- editor session registry

Acceptance criteria:

- reads return unsaved editor content when the file is currently open and dirty
- reads fall back to disk when there is no open editor buffer
- writes update disk and any open editor session for the same file without desynchronizing the editor
- writes to unopened files still succeed
- unsupported writes are surfaced as typed ACP errors, not generic failures
- tests cover:
  - dirty buffer read
  - clean buffer read
  - write to open file
  - write to unopened file

### `AGNT-023` Bridge ACP terminals to Ghostty-backed workspace terminals

Scope:

- implement ACP `terminal/create`
- implement `terminal/output`
- implement `terminal/wait_for_exit`
- implement `terminal/kill`
- implement `terminal/release`
- render inline terminal transcript rows
- support promotion from inline terminal to full terminal tab

Primary touch points:

- `Apps/mac-client/Sources/mac/Services/WorkspaceTerminalRegistry.swift`
- Ghostty terminal integration

Acceptance criteria:

- terminal commands launched from ACP are workspace-owned
- inline terminal rows stream live output while the command runs
- release preserves rendered output in the transcript after terminal teardown
- promotion opens the existing terminal session in a standard terminal tab when still available
- if the command has already exited, promotion still gives the user access to the captured output
- terminal lifecycle edge cases are covered:
  - running
  - exited
  - killed
  - truncated output

### `AGNT-030` Add agent session persistence and restore

Scope:

- persist agent tabs in workspace layout snapshots
- store enough session metadata to attempt ACP `session/load`
- restore agent tabs on relaunch when enabled in settings
- handle unsupported restore gracefully

Primary touch points:

- `Apps/mac-client/Sources/mac/Views/Window/ContentView+TerminalPersistence.swift`
- workspace shell state persistence

Acceptance criteria:

- agent tabs persist alongside editor/diff/terminal tabs in workspace layout
- restore attempts to load previous ACP sessions when the agent supports `loadSession`
- failed restore degrades to an explicit failed/restoration-needed row, not a silent empty tab
- restored tabs preserve pane placement and selected tab state
- turning restore off prevents agent session restore
- tests cover snapshot round-trip for agent tabs

### `AGNT-031` Add `Agents` discovery surfaces and command routing

Scope:

- add toolbar / command palette / sidebar entry points for Agents
- add an Agents sidebar surface for thread discovery and status
- route “new agent session” and “open agent tab” actions consistently

Acceptance criteria:

- user can create a new agent session from:
  - toolbar
  - command palette
  - sidebar
- existing agent sessions for the active workspace are discoverable without scanning tabs manually
- the sidebar is workspace-scoped, not app-global
- session selection opens/focuses the correct tab instead of duplicating tabs unnecessarily

### `AGNT-032` Add approvals, follow mode, and professional workflow affordances

Scope:

- implement approval action UI
- implement allow/reject flows
- implement follow mode based on tool locations
- add affordances expected in a professional IDE:
  - retry
  - stop
  - copy transcript item
  - reveal file from tool call
  - open diff artifact in dedicated diff tab when appropriate

Acceptance criteria:

- approval options are rendered exactly as provided by the agent
- user selection sends the correct ACP permission outcome
- follow mode can be toggled per session
- follow mode does not steal focus when disabled
- tool call file locations can open editor tabs or diff tabs as appropriate
- no workflow affordance relies on parsing rendered strings from the UI

### `AGNT-033` Test, harden, and document the feature to production quality

Scope:

- add unit tests, integration tests, and regression tests
- add fake ACP adapter fixtures for deterministic tests
- document installation requirements and operational behavior
- update stale local docs that describe old chat tab assumptions

Acceptance criteria:

- automated tests cover:
  - ACP handshake
  - session creation
  - prompt streaming
  - cancel
  - config options
  - permissions
  - inline terminals
  - workspace switching
  - split/tab movement
  - persistence/restore
- test fixtures do not depend on live Codex or Claude services
- local product docs no longer describe removed/stale chat architecture as current architecture
- there is a clear operator-facing doc for adapter installation and failure diagnostics
- closeout includes verification commands for the active mac client target and relevant packages

## Definition of Done

This project is only done when all of the following are true:

- Devys has a first-class `Agents` surface in the live app
- Codex ACP and Claude ACP both work end to end in a workspace
- agent tabs behave like real Devys tabs in splits and restore
- file, diff, and image chips work
- ACP artifacts render as structured IDE-native transcript items
- filesystem reads respect unsaved buffers
- ACP terminal execution renders inline and can be promoted to full terminal UI
- config options and slash commands are surfaced correctly
- the feature is covered by deterministic automated tests

## Implementation Rules

These rules are non-negotiable for this roadmap.

- no compatibility shim that treats raw terminal sessions as ACP sessions
- no revival of archived chat packages as the live architecture
- no app-global singleton agent store
- no stringly-typed transcript model
- no hidden context injection
- no agent tab type that bypasses existing split/tab systems
- no deprecated ACP mode-first UI when config options are available
- no shipping UX that cannot represent approvals, tool calls, and terminals

## Suggested Verification Commands

These should be refined as implementation lands, but this is the expected shape:

- `swift test` for any new package under `Packages/`
- targeted `xcodebuild test -project Devys.xcodeproj -scheme mac-client -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- targeted tests for:
  - ACP client transport
  - workspace shell state
  - tab content identity
  - persistence snapshots
  - terminal bridge behavior

## Open Questions To Resolve During Implementation

These are valid implementation questions, but they do not block the current architecture decision.

- whether `ACPClientKit` should live as a standalone package or inside `Apps/mac-client` first
- whether session list/history should be sidebar-only or also exposed in a dedicated tab
- whether image attachment processing should include automatic compression/thumbnail generation before send
- whether adapter binaries should be bundled, user-installed, or both
- whether model selectors should allow agent-specific custom UI when ACP metadata is insufficient

These questions must be resolved in implementation tickets without changing the core decisions above.
