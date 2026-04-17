# ADR 0003: UI Rulebook — Dia-Modeled Design System

- Status: Accepted
- Date: 2026-04-15

## Context

The original Devys UI guidance established `Packages/UI` as the design-system home, but it left too many token variants and too many parallel surface treatments. The result was predictable drift: feature-local styling, repeated one-off components, and multiple visual systems coexisting in the same app.

The design reset is now complete enough that the repo needs one accepted rulebook for the current system, not a v2 transition note.

## Decision

`Packages/UI` remains the single design-system source of truth. The active Devys UI system is the Dia-modeled layered-surface design captured in `../reference/ui-ux.md`.

## Rules

### Surface Rules

1. The app has exactly three surface levels: `base`, `card`, `overlay`. There is no bg0-bg5 scale.
2. `base` is the window/app chrome: sidebar, rail, titlebar, and pane gaps.
3. `card` is the elevated content surface: each split pane is a card sitting on `base`.
4. `overlay` is for floating elements: command palette, sheets, menus, popovers, and modals. `popover` is a variant of overlay with lighter shadow.
5. Surfaces are applied via `.elevation()` so background, border, radius, and shadow stay coupled.

### Radius Rules

6. One radius: 12pt with `.continuous` curvature for standard interactive and container elements.
7. `radiusMicro` (4pt) exists only for tiny inline elements.
8. `radiusFull` exists only for circles, dots, toggle tracks, and capsules.
9. No other radius values belong in feature code.
10. All `RoundedRectangle` usage must specify `style: .continuous`.
11. Inner radii use `Spacing.innerRadius(padding:)` instead of ad hoc values.

### Color Rules

12. Feature modules must not hardcode hex colors, `Color.white`, `Color.black`, or custom `Color(hex:)`.
13. All app UI colors come from `Theme` or semantic status tokens.
14. The default theme is monochrome Graphite. The app must feel complete without a colored accent.
15. Accent color use is intentionally sparse: active indicators, focus, links, primary fills, and subtle focused-card treatment.

### Typography Rules

16. All UI chrome uses `Typography.*` tokens.
17. No `.system(size:)` calls belong in feature code for app UI.
18. Monospace is for code contexts only: editor, terminal, inline code, and diffs.

### Spacing Rules

19. All spacing uses `Spacing.*` tokens.
20. The pane gap (`Spacing.paneGap`) is a first-class token, not a local layout tweak.

### Animation Rules

21. One spring is used for structural transitions.
22. One micro timing is used for hover, press, and focus interactions.
23. Status animations are the only allowed exceptions.

### Component Rules

24. Feature modules must not hard-code colors, spacing, radii, borders, shadows, or typography.
25. Repeated visual patterns become shared UI components before they are copied again.
26. Shared UI primitives are the default path for interactive surfaces.
27. Buttons have two primary visual variants: filled and ghost. Destructive behavior is expressed through tone, not a third visual system.
28. Floating surfaces use `.elevation()` rather than manual composition.

### Deletion Rules

29. Terminal-aesthetic UI components and legacy shell visuals are deleted rather than preserved as alternate themes.
30. Bracket-style shortcut badges are replaced with chip-style badges.
31. Legacy token aliases and feature-local styling hacks are cleanup targets, not acceptable steady state.

## Required Shared Surfaces

- elevation modifier (`.elevation(.base / .card / .popover / .overlay)`)
- `DevysShape` convenience shape for `.continuous` curvature
- `Spacing.innerRadius(padding:)` for nested geometry

## Consequences

- `Packages/UI` is the only design-system source of truth.
- Feature code composes shared primitives instead of inventing parallel styles.
- Legacy token scales, terminal-aesthetic components, and feature-local visual systems are deletion targets.
- The canonical UI reference is `../reference/ui-ux.md`.
- Package-local UI guidance must stay aligned with this ADR and the canonical reference.
