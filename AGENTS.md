# Devys Repo Guide

This file applies to the entire repository.

Follow any deeper `AGENTS.md` files for package-local details. Several package-level `AGENTS.md` files predate the TCA migration and are useful as local package context, but they are not the source of truth for app-domain ownership. If a package guide conflicts with the canonical reference docs, treat that mismatch as documentation debt and fix it.

Every `AGENTS.md` in this repo should have a sibling `CLAUDE.md` symlink pointing to `AGENTS.md`. Edit `AGENTS.md`, not `CLAUDE.md`.

## What Devys Is Building

Devys is a native macOS, AI-native development environment for working across multiple repositories and worktrees in parallel.

The target product shape is:

- repo rail for repository and worktree switching
- content sidebar with exactly two primary modes: Files and Agents
- reducer-owned tabs, panes, focus, and layout
- editor, terminal, agent, diff, settings, and welcome tab content
- command palette for low-frequency global actions
- floating status capsule for ambient git and agent state

The app should feel explicit, warm, and fast. Power users should be able to stay keyboard-first. New contributors should be able to identify state ownership, effect ownership, and UI ownership immediately.

## Canonical Docs

Read these before changing architecture, shell behavior, or shared UI.

### Stable Reference Docs

- `.docs/reference/architecture.md`
- `.docs/reference/ui-ux.md`
- `.docs/reference/legacy-inventory.md`
- `.docs/reference/terminal-runtime.md`

These are the canonical docs that define repo doctrine. Do not casually edit them. If repo doctrine changes, update them intentionally.

### Docs Taxonomy

- `.docs/README.md`
- `.docs/AGENTS.md`
- `.docs/active/README.md`

Rules:

- Do not create ADRs in this repo.
- Put stable doctrine in `reference/`.
- Put active work plans in `.docs/active/`.
- Put inactive design briefs in `.docs/future/`.
- Put research and investigations in `.docs/research/`.
- When a future brief becomes active, move it into `.docs/active/`.
- When active-plan work lands, update the relevant plan doc in the same change stream.
- Do not put immutable architecture rules in plan docs.

## Build And Validation Entry Points

Use the repo's Xcode schemes as the canonical app entrypoints.

Supported app builds:

- `xcodebuild -scheme mac-client -configuration Debug -destination 'platform=macOS' build`
- `xcodebuild -scheme ios-client -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Supported package verification:

- `swift test` from the package directory for package-local validation
- `xcodebuild -scheme <PackageName> -configuration Debug build` only when you specifically need the Xcode package scheme path

Do not use raw `xcodebuild -target ...` app builds as the primary validation path in this repo.

Reason:

- this repo uses many local Swift packages
- the `-target` path can route package products through per-package `build/` directories and surface false missing-module failures that do not reproduce on the supported scheme path
- recent examples were false dependency failures like `Split -> UI` and `Syntax -> Text` during `-target` builds while the package schemes and app schemes built successfully

Do not run multiple `xcodebuild` scheme builds in parallel against the same DerivedData location.

Reason:

- Xcode will lock `build.db`
- that produces misleading verification failures unrelated to source changes

## Core Architecture Rules

These are non-negotiable:

- TCA owns app-domain state, feature logic, navigation state, workflow state, lifecycle policy, and side-effect orchestration.
- Reducer state is the canonical source of truth for migrated app domains.
- SwiftUI views render state and send actions. Views do not coordinate app workflows or own business logic.
- App-domain side effects run through explicit dependency clients.
- One concern has one owner.
- One domain has one source of truth.
- No app-domain `NotificationCenter` command bus.
- No app-domain service locator pattern.
- No permanent migration shims.
- No mirrored ownership between reducers and legacy stores.
- No new singleton, registry, manager, or runtime introduced as an app-domain owner.
- No hard-coded design primitives in feature code.
- Strict Swift concurrency is the baseline for app-domain code.

## TCA Boundary Rule

TCA owns app behavior. Engines do not.

### TCA Must Own

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

### TCA Must Not Own

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
- Views may host narrow engine handles only when required for rendering or hosting, never as app-domain authorities.

## Package Roles

- `Apps/mac-client`
  Thin host and composition layer only. Bootstrap, live dependency wiring, host-framework integration, and migration bridges live here. It must not become the long-term owner of app-domain behavior.
- `Packages/AppFeatures`
  The home for app-domain reducers, shell state, feature logic, app-domain models, and explicit dependency clients.
- `Packages/UI`
  The only design-system source of truth. Tokens, shared styling, and stateless reusable components live here.
- `Packages/Split`
  Split rendering and interaction boundary. It may render and manage mechanics, but it must not own visible app-domain pane and tab truth.
- `Packages/Workspace`, `Packages/Git`, `Packages/Editor`, `Packages/GhosttyTerminal`, `Packages/Syntax`, `Packages/Text`, `Packages/Rendering`, `Packages/ACPClientKit`
  Capability and engine packages. Keep their boundaries narrow. They are not app-domain owners.
- `Apps/_archive` and `Packages/_archive`
  Archive material only. Do not route new production code through archived modules.

## UI Rules

- `Packages/UI` is the single design-system source of truth.
- Feature modules must not hard-code colors, spacing, radii, borders, shadows, motion, or typography tokens.
- Repeated visual patterns become shared UI components before they are copied again.
- Feature code may compose shared primitives, but it may not invent a parallel design system.
- Interaction policy belongs in reducer-owned features and shell logic, not in `Packages/UI`.
- Low-frequency global actions belong in the command layer, not permanent chrome.

The design system is Dia-browser-modeled with three core rules:

- **One radius (12pt, `.continuous` curvature).** All interactive and container elements use `Spacing.radius`. No exceptions.
- **Three surfaces.** `base` (window/sidebar/rail/gaps), `card` (split panes as elevated cards), `overlay` (modals/popovers). Applied via `.elevation()` modifier.
- **Monochrome default.** Graphite accent = no color. 10 theme colors available for subtle tinting.

All `RoundedRectangle` must use `style: .continuous`. Use `.elevation()` instead of manual background + border + shadow composition.

The canonical shell model is:

- repo rail (base surface)
- content sidebar (base surface)
- split-pane cards sitting on base surface with visible gaps
- command palette (overlay surface)
- floating status capsule

The content sidebar model is Files and Agents. Do not reintroduce the old four-mode sidebar framing.

## Simplicity Rules

We only accept code that is explicit, direct, and easy to reason about.

Reject or delete:

- magic behavior
- clever abstractions that hide ownership
- hidden control flow
- hidden fallback paths that silently change behavior
- broad convenience layers that blur boundaries
- wrapper types whose only job is preserving old architecture
- compatibility layers without a clear deletion path
- helper APIs that make side effects implicit
- ad hoc state mirrors
- "temporary" tech debt with no concrete removal plan

Prefer:

- direct reducer logic over managers and coordinators
- explicit state, action, and effect modeling
- small focused types with obvious ownership
- value-driven UI and rendering boundaries
- narrow adapters instead of broad facades
- deletion of obsolete code in the same stream as replacement

## Visibility And API Discipline

- `public` is opt-in only.
- Default to `internal`.
- Prefer `private` for file-local implementation detail.
- Every new public symbol should have a clear cross-module reason to exist.
- Cross-package composition should depend on focused interfaces, not convenience exports.

Treat unnecessary `public` surface as a design bug.

## Migration Discipline

- Replace structurally wrong abstractions instead of wrapping them.
- Delete dead code and obsolete owners as soon as their replacement lands.
- Do not preserve legacy shell ownership just because it exists today.
- Do not normalize the current bridge state between reducers and legacy owners into a permanent architecture.
- Treat notification routing, runtime registries, mutable shared stores, and legacy workspace shell copies as migration targets unless the canonical docs explicitly classify them as engine-only boundaries.
- If you touch migration status or the remaining ownership boundary, update the relevant active plan in `.docs/active/` or the affected canonical reference doc in `.docs/reference/`.

Current migration reality belongs in active plan docs while work is in flight and in canonical reference docs once it stabilizes. Read the relevant docs before touching shell ownership.

## Concurrency And Effects

- App-domain dependencies must be explicit.
- Dependency interfaces should be `Sendable` unless actor isolation is the intended design.
- Unsafe concurrency escape hatches are banned in app-domain code.
- Low-level unsafe types may exist only behind narrow, documented boundaries.
- Do not leak engine-owned mutable objects into reducer-owned domain state.

## Tests And Reviews

- Reducer behavior changes should come with reducer tests.
- Boundary changes should include coverage that proves ownership and effect flow are still explicit.
- UI work should reuse or extend `Packages/UI` instead of adding feature-local primitives.
- Reviews should reject code that makes ownership harder to see.

If you cannot explain who owns the state, who performs the effect, and why the boundary exists, the design is not finished.
