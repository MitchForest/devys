# UI Package Guide

`Packages/UI` is the single design-system source of truth for Devys.

Read these first:

- `/Users/mitchwhite/Code/devys/AGENTS.md`
- `/Users/mitchwhite/Code/devys/.docs/adrs/0003-ui-rulebook.md`
- `/Users/mitchwhite/Code/devys/.docs/reference/ui-ux.md`

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
  - tokens and styling primitives such as `Colors`, `Typography`, `Spacing`, `Animations`, `Shadows`, `Density`, `AgentColor`, `StatusHint`, `ChatTokens`, `DevysShape`, and `Elevation`
- `Sources/UI/Views/Components/Common/`
  - shared reusable components
- `Sources/UI/Views/Components/Gallery/`
  - design-system gallery/debug surfaces

## Working Rules

- New code should use the unprefixed design-system names (`Theme`, `Spacing`, `Typography`, etc.). Backward-compat aliases in `DesignSystem.swift` exist only as migration support.
- Shared component names follow the current public surface, for example `ActionButton` in `Button.swift` and `StatusDot` in `StatusIndicator.swift`.
- Feature modules must not hardcode colors, spacing, radii, borders, shadows, motion, or typography.
- Repeated UI patterns should become shared components here before they are copied again elsewhere.
- Keep this file short and aligned with the canonical UI docs. Do not recreate a second full design spec here.
