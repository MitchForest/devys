# UI Package Guide

`Packages/UI` is the single design-system source of truth for Devys.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/README.md`

## Role

This package owns:

- design tokens and semantic styling primitives
- adaptive theme values
- shared stateless SwiftUI components
- shared surface treatments such as `DevysShape` and `.elevation()`

This package does not own:

- app-domain workflow policy
- feature coordination
- host-framework behavior

## Current Structure

- `Sources/UI/Models/DesignSystem/`
  - tokens and styling primitives such as `Colors`, `Typography`, `Spacing`, `Animations`, `Shadows`, `Density`, `AgentColor`, `ChatTokens`, `DevysShape`, and `Elevation`
- `Sources/UI/Views/Components/Common/`
  - shared reusable components
- `Sources/UI/Views/Components/Gallery/`
  - design-system gallery/debug surfaces

## Working Rules

- Use the unprefixed design-system names (`Theme`, `Spacing`, `Typography`, etc.).
- Shared component names follow the current public surface, for example `ActionButton` in `Button.swift` and `StatusDot` in `StatusIndicator.swift`.
- Feature modules must not hardcode colors, spacing, radii, borders, shadows, motion, or typography.
- Repeated UI patterns should become shared components here before they are copied again elsewhere.
- Keep this file short and aligned with the root product and UI guidance. Do not recreate a second full design spec here.

## Public API Boundary

Public API is limited to:

- design-system namespaces, tokens, surfaces, modifiers, and semantic value types
- stateless primitives with active cross-module consumers, such as `ActionButton`, `IconButton`, `GlassSegmentedControl`, `InputChip`, `DiffRow`, text fields, status primitives, panels, sheets, command palette primitives, and surface modifiers
- small value types required by public primitives, such as `GitFileStatus`, `StatusIcon`, `SheetAction`, and `GlassSegmentedControl.Option`

Internal-only API includes:

- debug/demo surfaces such as `DesignSystemGallery`
- app/product-specific candidates without active cross-module consumers, including old repo/worktree/agent/file/folder/notification/FAB components
- helper views used only to implement a retained public primitive, such as `GitStatusIndicator`

Before making a UI symbol public, identify its external consumer or write the cross-module reason in this file. Treat public UI without a consumer or explicit reason as an architecture bug.
