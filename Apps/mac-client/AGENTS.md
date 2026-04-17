# mac-client Guide

This directory is the thin host and composition layer for the Devys macOS app.

Read these first before changing architecture, shell ownership, or shared UI:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/architecture.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/ui-ux.md`
- `/Users/mitchwhite/Code/devys/.docs/plan/implementation-plan.md`

## Role

`Apps/mac-client` owns:

- app bootstrap and scene wiring
- live dependency registration via `AppFeaturesBootstrap`
- host-framework integration (`AppKit`, SwiftUI scene glue, toolbar wiring)
- engine-backed view hosting for editor, terminal, agent, and diff surfaces
- narrow runtime/cache objects that retain engine handles only

`Apps/mac-client` does not own:

- app-domain source of truth
- shell, catalog, workflow, or lifecycle policy
- shared design-system primitives
- long-lived mirrored state between reducers and host runtimes

## Current Landmarks

- `Sources/mac/Services/AppFeaturesBootstrap.swift`
  - live wiring for reducer dependencies
- `Sources/mac/Services/AppContainer.swift`
  - temporary composition root and factory, not an app-domain owner
- `Sources/mac/Views/Window/AppFeatureHost.swift`
  - root store host
- `Sources/mac/Views/Window/ContentView*.swift`
  - host composition and one-shot execution surfaces
- `Sources/mac/Services/WorktreeRuntimeRegistry.swift`
  - host runtime cache only; not UI-visible truth
- `Sources/mac/Services/HostedWorkspaceContentBridge.swift`
  - focused host observation feeding reducer-owned summaries

## Working Rules

- If a change affects app behavior, policy, navigation, lifecycle, or visible shell truth, default to `Packages/AppFeatures`.
- If a change affects repeated styling or shared UI primitives, default to `Packages/UI`.
- If a change affects pane or tab truth, remember `Packages/Split` is a rendering boundary and the reducer owns canonical layout state.
- Host runtimes may cache engine handles, sessions, and adapters, but they must not become UI-facing authorities.
- Do not reintroduce app-domain `NotificationCenter` routing, service-locator ownership, or bidirectional reducer/runtime mirrors.
- When remaining migration boundaries change, update `/Users/mitchwhite/Code/devys/.docs/plan/implementation-plan.md` in the same stream.
