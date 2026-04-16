# Design System Overhaul — Dia-Modeled Execution Plan

Updated: 2026-04-15

## Purpose

This plan covers the complete redesign of the Devys design system to match the Dia browser's design language. It is the execution plan for `ui-ux-v2.md` and `0003-ui-rulebook-v2.md`.

## Guiding Constraint

Every step must leave the app building and launching. No big-bang rewrite. Each step is a self-contained commit that improves consistency without breaking the running app.

---

## Stream 1: Token Foundation

**Goal:** Rewrite the 7 token files in `Packages/UI/Sources/UI/Models/DesignSystem/` to match the v2 spec. Add `Elevation.swift` and `DevysShape`.

### Step 1.1: Rewrite `Colors.swift`

Current state: 6 dark backgrounds, 6 light backgrounds, 4 text levels, 3 border levels, 6 accent colors.

Target state:
- 3 surfaces (base/card/overlay) × 2 modes = 6 raw colors
- Hover/active computed from surfaces (not separate tokens)
- 3 text levels (text/textSecondary/textTertiary)
- 2 borders (border/borderFocus)
- 10 theme accent colors with solid/muted/subtle
- 4 semantic status colors with subtle variants
- Agent identity palette (9 colors = the 10 accents minus Graphite)

**Migration path:**
1. Add new token names alongside old ones
2. Alias old names to closest new equivalents (e.g., `darkBg0` → `base`, `darkBg2` → `card`)
3. Update `Theme` struct to expose new surface model
4. Old names become `@available(*, deprecated)` so compiler catches remaining usage
5. After all consumers migrate, delete old names

**Specific color values:**

Dark mode:
```
base:     #121110
card:     #1C1B19
overlay:  #252321
text:     #EDEDEB
textSec:  #9B9990
textTer:  #5E5C57
border:   #2A2826
```

Light mode:
```
base:     #F5F3F0
card:     #FFFFFF
overlay:  #FFFFFF
text:     #1C1B19
textSec:  #7A7772
textTer:  #AFACA6
border:   #E5E2DD
```

### Step 1.2: Rewrite `Spacing.swift`

Changes:
- Collapse 6 radius tokens to 3: `radius` (12), `radiusMicro` (4), `radiusFull` (9999)
- Add `paneGap: CGFloat = 6`
- Add `innerRadius(padding:) -> CGFloat` helper
- Remove `space10` (40) and `space16` (64)
- Update `repoRailWidth` from 44 to 48
- Update `tabBarHeight` from 34 to 36
- Deprecate old radius names (`radiusXs`, `radiusSm`, `radiusMd`, `radiusLg`, `radiusXl`)

### Step 1.3: Rewrite `Typography.swift`

Changes:
- Keep 7 UI chrome sizes (10, 11, 12, 13, 14, 18, 24) — same as current but rename `heading` to 14pt semibold
- Simplify `Code` to 4 sizes (base, sm, lg, gutter) — kill `micro` and `shortcut`
- Add `Chat` sub-enum with 4 sizes (body 15pt, heading 17pt, caption 12pt, code 14pt)
- Kill separate `ChatTokens` typography section

### Step 1.4: Rewrite `Animations.swift`

Changes:
- Update spring to `response: 0.35, dampingFraction: 0.86`
- Replace all micro-interaction timings (hover/press/focus) with one: `micro = easeOut(0.12)`
- Kill named aliases that just forward to spring (`sidebar`, `modal`, `palette`) — use `spring` directly
- Keep status animations (heartbeat, glow, shake, sweep)
- Kill `durationFast`, `durationDefault`, `durationSlow` raw values

### Step 1.5: Rewrite `Shadows.swift`

Changes:
- 3 presets instead of 5: `sm` (cards), `md` (popovers), `lg` (modals)
- Kill `xl` and `inset`
- Adjust values to new spec

### Step 1.6: Update `Density.swift`

Changes:
- Update `tabHeight` comfortable from 34 to 36
- Update `buttonHeight` comfortable from 34 to 36
- Update `repoRailWidth` comfortable from 44 to 48
- Add `paneGap` density value
- Minimal changes — density structure is fine

### Step 1.7: Rewrite `ChatTokens.swift`

Changes:
- Kill `userBubble` (#0A84FF) — replace with accent color reference
- Kill `userBubbleText` (.white) — replaced with `accentForeground`
- Kill separate typography tokens — point to `Typography.Chat.*`
- Update `bubbleRadius` from 18 to `Spacing.radius` (12)
- Update `composerRadius` from 20 to `Spacing.radius` (12)
- Significantly slimmed down — most tokens merged into main system

### Step 1.8: Create `Elevation.swift` (NEW)

New file providing surface-level recipes:

```swift
enum Elevation: Sendable {
    case base
    case card
    case popover
    case overlay
}
```

ViewModifier that applies: background color + corner radius + border + shadow for each level.

### Step 1.9: Create `DevysShape` (NEW)

Convenience shape enforcing `.continuous` curvature:

```swift
struct DevysShape: Shape {
    let radiusToken: RadiusToken  // .standard, .micro, .full
    // Always uses .continuous style
}
```

Add alongside a `.devysCornerRadius()` modifier that prevents raw `cornerRadius:` usage.

### Step 1.10: Delete `AgentColor.swift` agent palette

No deletion — update to derive from the 10 theme accent colors (minus Graphite). The 8-color custom palette becomes 9 colors drawn from the shared accent set.

---

## Stream 2: Component Refresh

**Goal:** Update all 39 components in `Packages/UI` to use new tokens. Delete terminal-aesthetic components.

### Step 2.1: Delete terminal-aesthetic components

- Delete `Views/Components/Terminal/TerminalEffects.swift`
- Delete `Views/Components/Terminal/ASCIILogo.swift`
- Delete the `Terminal/` directory
- Remove any imports/references in other components

### Step 2.2: Update atomic components (13 files)

Each component update follows the same pattern:
1. Replace old token references with new names
2. Replace `cornerRadius: Spacing.radiusSm` etc. with `Spacing.radius`
3. Add `style: .continuous` to all `RoundedRectangle`
4. Replace manual background/border/shadow with `.elevation()` where applicable
5. Ensure hover uses `Animations.micro` (not `Animations.hover`)
6. Ensure press uses `Animations.micro` (not `Animations.press`)

Files to update:
- `Button.swift` — collapse to 2 variants (primary + ghost), add destructive color param
- `Icon.swift` — minimal changes, update to new icon size tokens
- `TextField.swift` — update radius, focus ring to use `borderFocus`
- `Chip.swift` — update radius from `radiusXs` to `radius` (12pt)
- `Divider.swift` — simplify, ensure using `border` token
- `ShortcutBadge.swift` — redesign from bracket `[⌘K]` to chip style
- `StatusIndicator.swift` — update animation references
- `GitStatusIndicator.swift` — minimal changes
- `AgentIdentityStripe.swift` — minimal changes
- `Toggle.swift` — update to use accent color for on-state track

New files:
- `DevysShape.swift` — the continuous-curvature shape primitive
- `ElevationModifier.swift` — the `.elevation()` view modifier
- `SearchField.swift` — if it doesn't exist, extract from TextField

### Step 2.3: Update container components (8 files)

- `ListRow.swift` — update hover to `hover` surface
- `SectionHeader.swift` — update styling
- `EmptyState.swift` — update styling
- `Panel.swift` — use `.elevation(.card)` instead of manual styling
- `Popover.swift` — use `.elevation(.popover)`
- `Sheet.swift` — use `.elevation(.overlay)`
- `SegmentedControl.swift` — update radius, animation to spring
- `Tooltip.swift` — use `.elevation(.popover)`, update appear timing to `Animations.micro`

### Step 2.4: Update feature components (16 files)

These need the most visual work:

- `TabPill.swift` — radius → 12pt, active state → `base` background (below card), agent stripe stays
- `FileRow.swift` / `FolderRow.swift` / `ConnectorLine.swift` — update spacing/color tokens
- `AgentRow.swift` — update identity dot to use new agent palette
- `DiffRow.swift` — update tokens
- `RepoItem.swift` — radius → 12pt, size → 34pt, update active indicator
- `WorktreeItem.swift` — update tokens
- `NotificationToast.swift` — use `.elevation(.popover)`
- `Breadcrumb.swift` — update tokens
- `FABMenu.swift` — use `.elevation(.popover)`
- `DropZoneOverlay.swift` — update accent usage
- `InsertionIndicator.swift` — update accent usage
- `DragPreview.swift` — update shadow to `md`, radius to 12pt
- `InlineCommit.swift` — update tokens
- `SavePromptPopover.swift` — use `.elevation(.popover)`

### Step 2.5: Update composed surfaces (4 files)

- `CommandPalette.swift` — use `.elevation(.overlay)`, update internal field to `base` bg
- `CommandPaletteRow.swift` — update hover/active to new tokens
- `StatusCapsule.swift` — keep `radiusFull`, use `.elevation(.popover)` treatment
- `BranchPicker.swift` — use `.elevation(.popover)`

---

## Stream 3: App View Migration

**Goal:** Replace every hardcoded style value in `Apps/mac-client/Sources/` with design tokens.

### Step 3.1: Audit and fix `AgentSessionView.swift` (CRITICAL)

This file has 28 hardcoded cornerRadius, 25+ hardcoded spacing, 10+ hardcoded fonts, and 1 hardcoded color.

Approach: systematic find-and-replace pass:
1. Replace all `cornerRadius: 8` → `Spacing.radius`
2. Replace all `cornerRadius: 12` → `Spacing.radius`
3. Replace all `cornerRadius: 10` → `Spacing.radius`
4. Replace all `.system(size: N)` → `Typography.*` equivalent
5. Replace all `.padding(N)` → `.padding(Spacing.*)`
6. Replace all `spacing: N` → `Spacing.*`
7. Replace `Color.white` → `theme.text` or appropriate token
8. Replace manual bg+border+shadow combos → `.elevation()`

### Step 3.2: Fix `AgentHarnessPickerSheet.swift`

2 hardcoded cornerRadius values. Small file, quick fix.

### Step 3.3: Fix `ContentView+ObservationSurfaces.swift`

2 hardcoded cornerRadius values. Quick fix.

### Step 3.4: Fix `SettingsView.swift`

20+ hardcoded spacing values. Systematic pass.

### Step 3.5: Fix `RepositoryNavigatorView.swift`

15+ hardcoded spacing values. Systematic pass.

### Step 3.6: Fix `RepositoryManagementSheet.swift`

Hardcoded spacing values. Quick fix.

### Step 3.7: Fix `RepositoryPortLabelsEditorView.swift`

Hardcoded spacing values. Quick fix.

### Step 3.8: Fix `ProjectPickerView.swift`

Already partially migrated (uses `Spacing.radiusSm`). Update to new token names.

### Step 3.9: Implement the layered surface model in shell views

This is the big visual change — making split panes render as elevated cards on a base surface:

1. The `ContentView` composition layer must set `base` as the window background
2. The sidebar must use `base` background (not `card`)
3. The rail must use `base` background
4. Each split pane must be wrapped in a card with `.elevation(.card)` — 12pt radius, 1pt border, sm shadow
5. The gap between panes must be `paneGap` (6pt) filled with `base`
6. The focused pane gets the subtle accent gradient wash at top

This may require changes to `Packages/Split` rendering or the shell composition layer. The split dividers become the gaps — they don't have a visible line, just a gap of `base` between two card surfaces.

### Step 3.10: Update titlebar

Replace any remaining legacy titlebar buttons with the (+) FAB + breadcrumb + `⌘K` pattern from the v1 spec (this hasn't changed).

---

## Stream 4: Documentation & Cleanup

### Step 4.1: Rewrite `Packages/UI/CLAUDE.md`

Current CLAUDE.md describes "terminal-inspired monochrome aesthetic" with colors that don't match the code (lists `white`, `cyan`, `mint`, `lavender` as accents). Rewrite to match the Dia-modeled system.

### Step 4.2: Promote v2 docs

Once all code changes are complete:
1. Move `ui-ux.md` → `ui-ux-v1-archive.md`
2. Move `ui-ux-v2.md` → `ui-ux.md`
3. Move `0003-ui-rulebook.md` → `0003-ui-rulebook-v1-archive.md`
4. Move `0003-ui-rulebook-v2.md` → `0003-ui-rulebook.md`
5. Update `CLAUDE.md` references

### Step 4.3: Update `CLAUDE.md` (repo root)

Update the "UI Rules" section to reference the new radius/surface rules. Remove references to "four-mode sidebar framing" or other v1 patterns that no longer apply.

### Step 4.4: Clean up deprecated token aliases

After all consumers have migrated:
1. Remove `@available(*, deprecated)` aliases from `Colors.swift`
2. Remove deprecated radius names from `Spacing.swift`
3. Remove terminal component references from any re-exports

---

## Execution Order

### Phase A: Token Foundation (Stream 1)

Steps 1.1 through 1.10 in order. Each step is a commit. The old token names are deprecated but still compile. No component or view changes yet.

**Acceptance criteria:** Token files match the v2 spec. Old names emit deprecation warnings. App still builds and runs with old names.

### Phase B: Component Refresh (Stream 2)

Steps 2.1 through 2.5. Terminal components deleted first, then atoms, containers, features, composed surfaces.

**Acceptance criteria:** All 41 components use new tokens. No deprecated token usage in `Packages/UI`. Terminal components deleted.

### Phase C: App Migration (Stream 3)

Steps 3.1 through 3.10. AgentSessionView first (biggest offender), then smaller files, then the layered surface model.

**Acceptance criteria:** Zero hardcoded style values in `Apps/mac-client`. The layered surface model is visible — panes are cards on a base. App looks like Dia.

### Phase D: Documentation (Stream 4)

Steps 4.1 through 4.4. Promote v2 docs, clean up deprecated aliases.

**Acceptance criteria:** All docs reference the v2 system. No deprecated token names remain in the codebase. CLAUDE.md is accurate.

---

## Risk: The Split Rendering

The biggest unknown is Step 3.9 — making split panes render as elevated cards. This touches `Packages/Split` (the split rendering boundary) and the shell composition in `Apps/mac-client`. The current split system may not have a concept of "gaps between panes" or "rounded corners on individual panes."

**Mitigation:** Read the current `Packages/Split` rendering code before starting Step 3.9. If it requires significant Split-package changes, create a sub-plan and integrate with the main implementation plan. This should not block Streams 1-2 or Steps 3.1-3.8.

---

## What This Plan Does NOT Cover

- Editor theme/syntax colors (those are a separate system)
- Terminal rendering (Ghostty owns that)
- Icon design (staying with SF Symbols)
- Marketing website / branding
- Welcome screen redesign (needs design work beyond "delete ASCII art")

These are follow-up work after the design system overhaul lands.
