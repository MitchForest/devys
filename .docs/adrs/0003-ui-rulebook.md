# ADR 0003-v2: UI Rulebook — Dia-Modeled Design System

- Status: Proposed (supersedes 0003)
- Date: 2026-04-15

## Context

The v1 design system (ADR 0003) established `Packages/UI` as the single source of truth but left too many tokens, too many variants, and too little enforcement. The result: 6 corner radii, 6 background levels, 4 button variants, 4 shadow levels, 3 border colors, and 4 micro-interaction timings — all technically "correct" but producing visual incoherence in practice. Feature code adopted tokens inconsistently, and the app shipped with 52 hardcoded corner radii, 81 hardcoded spacing values, and 54 hardcoded font sizes in `Apps/mac-client` alone.

The new direction: model the Devys design system on Dia browser's approach. Fewer tokens, absolute consistency, layered surfaces, one corner radius.

## Decision

`Packages/UI` remains the single design-system source of truth. The token set is dramatically simplified.

## Rules

### Surface Rules

1. The app has exactly three surface levels: `base`, `card`, `overlay`. There is no bg0–bg5 scale.
2. `base` is the window/app chrome: sidebar, rail, gaps between panes, titlebar.
3. `card` is the elevated content surface: each split pane is a card with rounded corners sitting on `base`.
4. `overlay` is for floating elements: modals, command palette, sheets. `popover` is a variant of overlay with lighter shadow.
5. Surfaces are applied via `.elevation()` modifier, which sets background, border, shadow, and corner radius as a single unit.

### Radius Rules

6. **One radius: 12pt, `.continuous` style.** All interactive and container elements use this.
7. `radiusMicro` (4pt) exists only for: checkbox corners, inline code spans, progress bar tracks.
8. `radiusFull` (9999pt) exists only for: circles (dots, avatars, toggle tracks, capsule).
9. No other radius values exist. If code contains a hardcoded `cornerRadius:` that is not one of these three, it is a bug.
10. All `RoundedRectangle` must use `style: .continuous`. Non-continuous corners are a bug.
11. **Nesting rule**: inner radius = outer radius − padding. The system provides `Spacing.innerRadius(padding:)`.

### Color Rules

12. Feature modules must not hardcode hex colors, `Color.white`, `Color.black`, or any `Color(hex:)`.
13. All colors come from `Theme` (adaptive light/dark) or semantic tokens.
14. The default theme is monochrome (Graphite accent). The app must look complete with no accent color.
15. Accent colors tint — they don't dominate. Maximum accent usage: toggles, active indicators, focus rings, links, primary button fill, and a subtle 6% gradient wash on focused cards.

### Typography Rules

16. All UI text uses `Typography.*` tokens. No `.system(size:)` in feature code.
17. No font sizes between the defined stops (10, 11, 12, 13, 14, 18, 24).
18. Monospace is for code contexts only: editor, terminal, inline code, git diffs.

### Spacing Rules

19. All spacing uses `Spacing.*` tokens. No raw numeric padding/spacing in feature code.
20. The pane gap (`Spacing.paneGap`, 6pt) is a first-class token, not an afterthought.

### Animation Rules

21. One spring for structural transitions. One ease-out for micro-interactions. No ad-hoc timings.
22. Status animations (pulse, glow, shake) are the only exceptions — they communicate information.

### Component Rules

23. Feature modules must not hard-code colors, spacing, radii, borders, shadows, or typography tokens.
24. Repeated visual patterns must become shared components before they are copied.
25. Shared UI primitives are the default path for all interactive surfaces.
26. **Two button variants: Primary and Ghost.** Destructive is a color parameter, not a variant.
27. **All floating surfaces use `.elevation()`.** No manual background + border + shadow composition.

### Deletion Rules

28. `TerminalEffects.swift` and `ASCIILogo.swift` are deleted. Terminal-aesthetic components are dead.
29. `ChatTokens` blue bubble (`#0A84FF`) is replaced with accent color.
30. Bracket-style shortcut badges (`[CMD+S]`) are replaced with chip-style badges.

## Required Shared Surfaces

Same as v1, plus:

- elevation modifier (`.elevation(.base / .card / .popover / .overlay)`)
- `DevysShape` convenience shape (enforces `.continuous` curvature)
- `Spacing.innerRadius(padding:)` nesting helper

## Consequences

- The v1 token files (`Colors.swift`, `Spacing.swift`, `Typography.swift`, `Animations.swift`, `Shadows.swift`, `Density.swift`, `ChatTokens.swift`) are rewritten to match this spec.
- All 39 existing components are updated to use the simplified token set.
- Terminal-aesthetic components are deleted.
- A new `Elevation.swift` token file provides the surface recipes.
- All hardcoded styling in `Apps/mac-client` is migrated to tokens.
- `Packages/UI/CLAUDE.md` is rewritten.
- `ui-ux-v2.md` is the canonical UI reference.
