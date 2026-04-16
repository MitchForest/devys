# Devys UI Package

## Overview

DevysUI is the shared design system and UI component library for the Devys IDE. It provides a warm, quiet, Dia-browser-inspired aesthetic with layered surfaces, one consistent corner radius, and monochrome warmth with optional accent tinting.

**Swift Tools Version:** 6.0
**Minimum Platform:** macOS 14
**Language Mode:** Swift 6 with Strict Concurrency enabled

## Design Philosophy

**Quiet confidence.** One radius everywhere. Three surface levels. Monochrome default with optional theme color. Everything consistent. No terminal-hacker aesthetic — warm, professional, native macOS.

Canonical design spec: `.docs/reference/ui-ux.md`
Canonical ADR: `.docs/adrs/0003-ui-rulebook.md`

## Architecture

### Package Structure

```
UI/
├── Package.swift
├── Sources/UI/
│   ├── Models/
│   │   └── DesignSystem/
│   │       ├── Colors.swift          # 3 surfaces, 3 text, 2 borders, 10 accents, semantic status
│   │       ├── Typography.swift      # 7 UI + 4 code + 4 chat sizes
│   │       ├── Spacing.swift         # 4px grid, 3 radii (micro/radius/full), layout constants
│   │       ├── Animations.swift      # 1 spring + 1 micro timing + status animations
│   │       ├── Shadows.swift         # 3 shadow presets (sm/md/lg)
│   │       ├── Density.swift         # comfortable/compact modes
│   │       ├── ChatTokens.swift      # Chat-specific geometry (bubbles, composer)
│   │       ├── AgentColor.swift      # 9-color agent identity palette
│   │       ├── Elevation.swift       # Surface recipes (.base/.card/.popover/.overlay)
│   │       └── DevysShape.swift      # Continuous-curvature shape primitive
│   └── Views/
│       └── Components/
│           ├── Common/               # 39 shared components
│           └── Gallery/              # Design system gallery (debug)
```

## Design System

### The Three Rules

1. **One radius (12pt).** Everything uses `Spacing.radius` with `.continuous` curvature. Micro (4pt) for tiny elements. Full (9999pt) for circles. Nothing else.
2. **Three surfaces.** `base` (window/sidebar/rail/gaps), `card` (split panes), `overlay` (modals/popovers). Applied via `.elevation()` modifier.
3. **Monochrome default.** Graphite accent = no color. 10 theme colors available for subtle tinting.

### Colors (`Colors` / `Theme`)

Three surface levels per mode:

```swift
// Dark                    // Light
base:    #121110           base:    #F5F3F0
card:    #1C1B19           card:    #FFFFFF
overlay: #252321           overlay: #FFFFFF
```

Three text levels: `text`, `textSecondary`, `textTertiary`
Two borders: `border` (standard), `borderFocus` (accent at 50%)

10 accent colors: Graphite (default), Blue, Teal, Green, Lime, Yellow, Orange, Red, Pink, Violet

```swift
@Environment(\.theme) private var theme

theme.base          // window background
theme.card          // split pane content
theme.overlay       // floating surfaces
theme.text          // primary text
theme.textSecondary // secondary text
theme.border        // standard border
theme.accent        // theme accent color
theme.primaryFill   // button fill (accent or text if monochrome)
```

### Spacing (`Spacing`)

4px base unit. Scale: 0, 4, 8, 12, 16, 20, 24, 32, 48.
Semantic aliases: `tight` (4), `normal` (8), `comfortable` (12), `relaxed` (16), `spacious` (24).

Corner radii:
```swift
Spacing.radius      // 12pt — the one radius for everything
Spacing.radiusMicro // 4pt — tiny inline elements only
Spacing.radiusFull  // 9999pt — circles only
Spacing.innerRadius(padding: 8) // computed nesting: 12 - 8 = 4pt
```

Pane gap: `Spacing.paneGap` (6pt) — visible gap between split-pane cards.

### Typography (`Typography`)

SF Pro for UI chrome, SF Mono for code:

```swift
Typography.display  // 24pt bold
Typography.title    // 18pt semibold
Typography.heading  // 14pt semibold
Typography.body     // 13pt regular
Typography.label    // 12pt medium
Typography.caption  // 11pt regular
Typography.micro    // 10pt medium

Typography.Code.base   // 13pt mono
Typography.Code.sm     // 12pt mono
Typography.Code.lg     // 14pt mono
Typography.Code.gutter // 11pt mono

Typography.Chat.body    // 15pt
Typography.Chat.heading // 17pt semibold
Typography.Chat.caption // 12pt
Typography.Chat.code    // 14pt mono
```

### Animations (`Animations`)

```swift
Animations.spring  // structural transitions (sidebar, modal, palette, splits)
Animations.micro   // all micro-interactions (hover, press, focus) — 120ms ease-out
Animations.heartbeat / .glow / .shake / .sweep  // status animations
```

### Elevation (`Elevation`)

Surface recipes applied as a single modifier:

```swift
.elevation(.base)    // flat, no border/shadow
.elevation(.card)    // card bg + 1pt border + sm shadow + 12pt radius
.elevation(.popover) // overlay bg + 1pt border + md shadow + 12pt radius
.elevation(.overlay) // overlay bg + 1pt border + lg shadow + 12pt radius
```

### DevysShape

Continuous-curvature shape primitive:

```swift
DevysShape()                     // 12pt standard
DevysShape(.micro)               // 4pt
DevysShape(.full)                // circle
DevysShape(innerPadding: 8)      // computed: 12 - 8 = 4pt

.devysCornerRadius()             // clip to 12pt continuous
.devysInnerCornerRadius(padding: 8)  // clip to computed inner
```

## Components (39)

All in `Views/Components/Common/`:

**Atoms:** ActionButton, Icon, TextField (TextInput + SearchInput), Toggle, Chip, Divider, ShortcutBadge, StatusDot, GitStatusIndicator, AgentIdentityStripe

**Containers:** ListRow, SectionHeader, EmptyState, Panel (+ SidebarSection), Popover, Sheet, SegmentedControl, Tooltip

**Feature:** TabPill, FileRow, FolderRow, ConnectorLine, AgentRow, DiffRow, RepoItem, WorktreeItem, NotificationToast, Breadcrumb, FABMenu, DropZoneOverlay, InsertionIndicator, DragPreview, InlineCommit, SavePromptPopover, Toolbar

**Composed:** CommandPalette, CommandPaletteRow, StatusCapsule, BranchPicker

## Usage

```swift
import UI

struct MyView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: Spacing.normal) {
            Text("Welcome")
                .font(Typography.title)
                .foregroundStyle(theme.text)

            ActionButton("Get Started", style: .primary) { }

            ShortcutBadge("⌘K")
        }
        .padding(Spacing.relaxed)
        .elevation(.card)
    }
}
```

## Rules

- Never hardcode colors, spacing, radii, or fonts in feature code
- All `RoundedRectangle` must use `style: .continuous`
- Use `.elevation()` instead of manual bg + border + shadow
- Two button variants only: `.primary` and `.ghost`
- Monospace is for code contexts only
- All public types are `Sendable`
