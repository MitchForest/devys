# ADR 0002: TCA Boundary Rule

- Status: Accepted
- Date: 2026-04-14

## Context

The migration will fail if TCA becomes a thin wrapper around the current runtime object graph. We need one explicit rule for what belongs inside reducers and what remains outside as an engine or integration layer.

## Decision

TCA owns app behavior. Engines do not.

### TCA Must Own

- app shell state
- window state
- feature state
- workflow state
- navigation and presentation state
- selection and focus state when it affects behavior
- tab and pane domain state
- reducer-owned persistence intent
- side-effect orchestration
- cross-feature coordination
- user intent handling

### TCA Must Not Own

- Metal renderer internals
- AppKit and SwiftUI bridge internals
- PTY or Ghostty engine internals
- text-buffer implementation internals
- syntax runtime internals
- parser execution internals
- filesystem watcher transport internals
- unmanaged OS resource handles
- protocol transport loops

### Allowed Boundary

- Reducers own IDs, lifecycle state, metadata, presentation state, policy, and intent.
- Dependency clients own low-level execution.
- Views may hold narrow engine handles only when required for rendering or hosting, never as the source of app behavior.

## Consequences

- `GitStore`, `AgentSessionRuntime`, `WorktreeRuntimeRegistry`, `WindowWorkspaceCatalogStore`, `WorkspaceAttentionStore`, `WorkspaceRunStore`, and related owners are migration targets because they currently hold app behavior.
- Packages such as `Editor`, `GhosttyTerminal`, `Syntax`, and low-level file watching stay as engine dependencies, but their app-facing coordination moves into reducers.
