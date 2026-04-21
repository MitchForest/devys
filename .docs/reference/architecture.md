# Devys Architecture Reference

Updated: 2026-04-20

## Purpose

This is the canonical architecture reference for Devys.

It defines ownership, boundaries, package roles, migration discipline, and the target repo shape.

Execution sequencing belongs in active plan docs under `../active/` when those exist. This file is stable reference, not a work log.

## Non-Negotiable Outcomes

- TCA owns app-domain state, feature logic, navigation state, workflow state, lifecycle policy, and side-effect orchestration.
- Reducer state is the canonical source of truth for migrated app domains.
- SwiftUI views render state and send actions. Views do not coordinate workflows or own business logic.
- App-domain side effects run through explicit dependency clients.
- The repo has one design system and one interaction model.
- Public APIs are minimal and intentional.
- Migrated app-domain code is concurrency-safe under Swift 6 strict concurrency expectations.
- The repo becomes simpler as migration work lands, not more layered.

## Ownership Model

### TCA Owns

- app shell state
- window state
- repository and workspace selection state
- sidebar, command palette, and presentation state
- pane and tab domain state
- workflow coordination state
- feature lifecycle state
- user intent handling
- cross-feature coordination
- persistence intent
- reducer-owned UI state that affects behavior

### TCA Does Not Own

- renderer internals
- AppKit and SwiftUI bridge internals
- Ghostty and PTY internals
- text-buffer and syntax engine internals
- parser execution internals
- filesystem watch transport internals
- unmanaged OS resource handles
- purely visual hover state that does not affect behavior

### Bridge Rule

- Reducers own IDs, metadata, lifecycle, presentation, policy, and intent.
- Dependency clients own low-level execution.
- Views may host narrow engine handles only where required for rendering, never as app-domain authorities.

## Source Of Truth Rules

- One concern has one owner.
- One migrated slice gets one source of truth immediately.
- No mirrored long-lived state between reducers and legacy stores.
- No permanent compatibility wrappers.
- No legacy owner survives just to preserve the old architecture story.

## Local Workspace Git Ownership

- Reducer-fed workspace operational snapshots are the only UI-visible git truth for local workspaces.
- Repo rail hints, floating status capsule data, files-sidebar counts, file-tree git badges, changes sidebar sections, and diff-tab reconciliation all derive from the same workspace snapshot.
- Host-side git watchers and refresh helpers may exist only as low-level invalidation and execution dependencies.
- `GitStore` may remain as a capability helper for explicit git operations and on-demand diff loading, but it must not own sidebar-visible state, selection state, or a second UI refresh path.
- `WorktreeRuntimeRegistry` must not own local-workspace git truth.

## Dependency And Concurrency Rules

- No app-domain service locator architecture.
- No implicit dependency access for app-domain logic.
- All side effects go through explicit dependency clients.
- Dependency interfaces are `Sendable` unless deliberate actor isolation is the design.
- Unsafe concurrency escape hatches are banned in app-domain code.
- Low-level unsafe types may exist only behind narrow, documented boundaries.

## Package Roles

### `Apps/mac-client`

- thin composition layer
- app bootstrap
- host-framework integration
- feature composition, not feature ownership

### `Packages/AppFeatures`

- app-domain reducers
- feature composition
- app-domain dependency clients
- reducer-backed shell state
- reducer-backed feature state

### `Packages/UI`

- tokens
- semantic colors
- typography
- spacing
- radii
- borders
- shadows
- motion tokens
- stateless shared components

### Low-Level Capability Packages

- `Packages/Workspace`
  - pure models and low-level workspace services
- `Packages/Git`
  - git parsing, operations, metadata, rendering helpers
- `Packages/Split`
  - split-layout engine and rendering boundary
- `Packages/Editor`
  - editor engine and rendering support
- `Packages/GhosttyTerminal`
  - terminal engine integration
- `Packages/Syntax`, `Packages/Text`, `Packages/Rendering`
  - engine and support libraries

These packages are not app-domain owners.

## UI And Interaction Ownership

- `Packages/UI` is the only design-system source of truth.
- Repeated visual patterns become shared UI components.
- Feature modules compose shared primitives but do not invent parallel styling systems.
- Interaction policy belongs in reducer-owned shell features, not in `Packages/UI`.
- Low-frequency global actions belong in the command layer, not permanent chrome.

## Module Visibility

- `public` is opt-in only.
- `internal` is the default.
- `private` is preferred for file-local detail.
- Reducers, helpers, mappers, utilities, and implementation details stay non-public unless cross-module use requires otherwise.

## Migration Discipline

- Replace structurally wrong abstractions instead of wrapping them.
- Delete dead code and obsolete owners as soon as their replacement lands.
- Do not preserve old shell layout assumptions just because they exist today.
- Do not treat the live bridge state between TCA and legacy owners as acceptable end state.

## Canonical Shell Model

- Repo rail for repository and worktree switching.
- Content sidebar for file and agent-oriented navigation.
- Main pane area for value-driven tabs and splits.
- Command palette for low-frequency global actions and navigation.
- Floating status capsule for ambient status.

The pane and tab shell is now reducer-owned and value-driven.
Empty panes render CTA surfaces directly; synthetic welcome tabs are not part of the canonical shell model.

## Contributor Heuristics

When deciding where code belongs:

- If it owns behavior the app depends on, it belongs in reducer state or a dependency client.
- If it exists to coordinate app workflows, it is not an engine.
- If it is reused UI shape or style, it belongs in `Packages/UI`.
- If it is a runtime, registry, or store retaining app-domain behavior, it is a migration target.

## Migration Completion Criteria

The architecture migration is only complete when all of the following are true:

- `Apps/mac-client` is a thin host/composition layer.
- `Packages/AppFeatures` owns app-domain shell and feature logic.
- No app-domain `NotificationCenter` routing remains.
- No app-domain singleton, registry, or store remains as a source of truth.
- The pane and tab shell is reducer-owned and value-driven.
- Side effects run through explicit dependency clients.
- Feature modules depend on `Packages/UI` for shared styling and common components.
- Public module boundaries are minimal.
- A contributor can identify state ownership, effect ownership, and UI ownership immediately.
