# TerminalVT

`TerminalVT` owns the reusable Ghostty-backed terminal runtime and rendering-facing SwiftUI view.

The Phase 12 integration removed the temporary `Packages/GhosttyTerminal` compatibility package. Current `mac-client`, `ios-client`, and `TerminalProduct` call sites import `TerminalVT` directly and use canonical `Terminal*` façade names. The implementation files still use historical `Ghostty*` names where they describe the underlying VT engine.

- `TerminalVTRuntime`
- terminal projection and surface models
- `TerminalView`
- terminal appearance, session, renderer warmup, and Metal host support

The next cleanup pass should tighten internal visibility for renderer/runtime details that do not need cross-module consumers.
