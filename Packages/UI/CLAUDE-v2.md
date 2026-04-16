# UI Package — Devys Design System

## Overview

The UI package is the single source of truth for the Devys IDE design system — a warm, orientation-first visual language built for multi-agent development. It provides design tokens, semantic tokens, and 50+ reusable SwiftUI components.

**Version:** 2.0.0
**Swift Tools Version:** 6.0
**Minimum Platform:** macOS 14
**Language Mode:** Swift 6 with Strict Concurrency enabled
**Dependencies:** None (Apple frameworks only)

## Design Philosophy

1. **Warm, not cold.** Every gray has a hint of amber. The palette shifts from cold monochrome (#000000) to warm stone (#0C0B0A dark, #FAF8F5 light).
2. **Orientation over decoration.** Visual choices help users know where they are, what's happening, and what needs attention.
3. **Dual typography.** Proportional fonts (SF Pro) for UI chrome; monospace fonts (SF Mono) for code/terminal only.
4. **One accent, earned.** A configurable accent color (default: violet) marks "you are here" and "this needs you."
5. **Agent identity through color.** 8-color palette assigned per agent session for instant visual recognition.
6. **Progressive disclosure.** Three layers: ambient (peripheral), focus (on engagement), command (on summon).

## Token System

### Colors (`Colors.swift`)

**Dark mode warm stone neutrals:**
```
bg-0: #0C0B0A  bg-1: #141311  bg-2: #1C1A17  bg-3: #252320  bg-4: #2E2C28  bg-5: #383530
```

**Light mode warm linen neutrals:**
```
bg-0: #FAF8F5  bg-1: #F5F2ED  bg-2: #EDEAE4  bg-3: #E5E1DA  bg-4: #DDD9D1  bg-5: #D5D0C7
```

**Text:** warm off-white primary (#EDE8E0 dark), warm near-black (#1C1A17 light)
**Semantic status:** success #5CB87A, warning #D4A54A, error #D45C5C, info #6B8FBF (desaturated, calm)
**Accent colors:** coral, teal, violet (default), amber, slateBlue, rose — each with solid/muted/subtle/hover variants

### Theme (`Theme` struct)

Adaptive struct accessed via `@Environment(\.theme)`. Also available as `@Environment(\.devysTheme)` (backward-compatible alias).

Key properties: `base`, `content`, `surface`, `elevated`, `hover`, `active` (backgrounds); `text`, `textSecondary`, `textTertiary`, `textDisabled`; `accent`, `accentMuted`, `accentSubtle`; `success`, `warning`, `error`, `info`

**Semantic token families** (accessed via `theme.surfaceTokens`, `theme.stateTokens`, `theme.statusTokens`, `theme.navTokens`):
- Surface: primary, secondary, elevated, floating
- State: hover, pressed, focusRing, selected, disabledOpacity
- Status: running, complete, error, warning, idle
- Navigation: activeTab bg/fg/indicator, inactiveTab fg, activeSidebar bg, sidebarHover

### Typography (`Typography`)

**UI chrome (proportional, SF Pro):** display (24pt), title (18pt), heading (14pt), body (13pt), label (12pt), caption (11pt), micro (10pt)
**Code (monospace, SF Mono):** `Typography.Code.base` (13pt), `.sm` (12pt), `.lg` (14pt), `.gutter` (11pt), `.shortcut` (12pt medium)

### Other Tokens

- **Spacing** (`Spacing`): 4px base unit, semantic aliases (tight/normal/comfortable/relaxed/spacious), radii (xs 4pt through full)
- **Animations** (`Animations`): Signature spring (0.32 response, 0.82 damping), hover (100ms), press (60ms), focus (150ms), status (300ms)
- **Shadows** (`Shadows`): sm, md, lg, xl presets
- **Density** (`Density`): comfortable (default) and compact modes via `@Environment(\.densityLayout)`
- **Agent Colors** (`AgentColor`): 8-color palette (coral, teal, violet, amber, slateBlue, rose, sage, sienna) with solid/muted/subtle/text variants

## Components (~50)

### Atomic (Wave 1)
`ActionButton`, `Chip`, `Toggle`, `TextField`, `SearchField`, `StatusDot`, `GitStatusIndicator`, `AgentIdentityStripe`, `Icon`, `ShortcutBadge`, `Separator`

### Container (Wave 2)
`ListRow`, `SectionHeader`, `EmptyState`, `Panel`, `Toolbar`, `Sheet`, `SegmentedControl`, `Popover`, `Tooltip`

### Feature-Adjacent (Wave 3)
`TabPill`, `FileRow`, `FolderRow`, `AgentRow`, `DiffRow`, `RepoItem`, `WorktreeItem`, `BranchPicker`, `Breadcrumb`, `FABMenu`, `DragPreview`, `DropZoneOverlay`, `InsertionIndicator`, `ConnectorLine`, `InlineCommit`, `SavePromptPopover`, `NotificationToast`, `CommandPaletteRow`

### Composed (Wave 4)
`CommandPalette` (with keyboard nav + home state), `StatusCapsule` (floating pill with auto-hide)

### Debug
`DesignSystemGallery` (#if DEBUG — renders all tokens and components)

## Usage

```swift
import UI

struct MyView: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    var body: some View {
        VStack(spacing: Spacing.space4) {
            Text("Hello")
                .font(Typography.body)
                .foregroundStyle(theme.text)

            ActionButton("Save", style: .primary) { save() }
        }
        .padding(layout.sectionPadding)
        .surface(.secondary)
    }
}
```

## Backward Compatibility

Type aliases exist for the old `Devys`-prefixed names: `DevysColors`, `DevysTypography`, `DevysSpacing`, `DevysAnimation`, `DevysShadow`, `DevysDensity`, `DevysTheme`. The `\.devysTheme` environment key aliases to `\.theme`. Prefer the unprefixed names in new code.
