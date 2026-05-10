# Terminal Package Guide

`Packages/Terminal` is the reusable terminal product package.

## Validation

- `swift test` from `/Users/mitchwhite/Code/devys/Packages/Terminal`
- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build`

## Role

Targets:

- `TerminalVT`
  - terminal engine, projection, rendering-facing surface models, and eventual Ghostty-backed VT runtime
- `TerminalHost`
  - PTY/session lifecycle, launch profiles, attach/detach, resize, input delivery, and host transport
- `TerminalComposer`
  - shared composer state machine, target-scoped drafts/queues, attachment chips, triggers, and serialization policies
- `TerminalProduct`
  - thin product composition for Devys Terminal inside the mac-client app

## Working Rules

- Do not depend on `Apps/mac-client` or app-domain reducer types.
- Keep public API opt-in and minimal.
- App-domain ownership remains outside this package; hosts own target selection and policy.
- `TerminalProduct` may compose lower targets for the standalone app, but broader Devys should depend on the lower targets directly unless it explicitly opts into product-level UI.
- Keep strict Swift concurrency enabled for all targets.

## Public API Boundary

Public API is limited to:

- `TerminalVT` engine/runtime/view/projection contracts required by terminal render hosts
- `TerminalHost` PTY/session/transport contracts required by host clients and persistent host control
- `TerminalComposer` composer state, attachment, serialization, speech, and view contracts required by terminal UI hosts
- `TerminalProductView`, `TerminalProductComposerPresentation`, `TerminalProductCommandSink`, and `TerminalProductCloseRisk` as the thin product-composition bridge currently consumed by `mac-client`

Internal-only API includes:

- AppKit/SwiftUI command menus, window/tab command policy, and shortcut help. Those belong in the app command layer.
- Product-local agent detection internals such as `TerminalAgentRegistry` and `TerminalAgentMatch`.
- Socket helper implementation details such as `TerminalHostSocketIO`; tests may use them through `@testable import`.

Before making a Terminal symbol public, identify the consuming target or package. Product command policy must not be reintroduced here.
