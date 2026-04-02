# DevysUI Package

## Overview

DevysUI is the shared design system and UI component library for the Devys application - an artificial intelligence development environment. The package provides a cohesive, terminal-inspired monochrome aesthetic with configurable accent colors, supporting both light and dark modes.

**Version:** 1.0.0
**Swift Tools Version:** 6.0
**Minimum Platform:** macOS 14
**Language Mode:** Swift 6 with Strict Concurrency enabled

## Purpose

DevysUI serves as the single source of truth for:
- Design tokens (colors, typography, spacing, animations)
- Reusable SwiftUI components
- Terminal-themed visual effects
- Consistent styling across the Devys ecosystem

## Architecture

### Package Structure

```
DevysUI/
├── Package.swift
├── Sources/DevysUI/
│   ├── DevysUI.swift                    # Main entry point, type aliases
│   ├── Models/
│   │   └── DesignSystem/
│   │       ├── DevysColors.swift        # Color palette and theming
│   │       ├── DevysTypography.swift    # Font definitions
│   │       ├── DevysSpacing.swift       # Spacing tokens and layout constants
│   │       └── DevysAnimation.swift     # Animation presets
│   └── Views/
│       └── Components/
│           ├── Common/
│           │   ├── DevysButton.swift    # Terminal-style button
│           │   ├── DevysIcon.swift      # Styled icon wrapper
│           │   └── StatusIndicator.swift # Status dot with animations
│           └── Terminal/
│               ├── ASCIILogo.swift      # ASCII art logo variants
│               └── TerminalEffects.swift # Cursor, typewriter, glow effects
├── Tests/DevysUITests/
│   └── ColorsTests.swift                # Unit tests for design system
└── _deprecated/                         # Legacy Metal-based components
```

### Design Philosophy

1. **Terminal-First Aesthetic**: All text uses monospace fonts. The interface feels like a modern terminal/IDE.
2. **Monochrome with Configurable Accent**: Pure blacks and whites create depth through contrast, with a single accent color for emphasis.
3. **Adaptive Theming**: Full support for light/dark modes via the `DevysTheme` system.
4. **Swift 6 Ready**: Built with strict concurrency, all public types are `Sendable`.

## Dependencies

This package has **no external dependencies**. It only uses Apple frameworks:
- `SwiftUI` - Primary UI framework
- `AppKit` - macOS-specific functionality (typography)

## Design System

### Colors (`DevysColors`)

The color system provides a complete terminal-inspired palette.

#### Background Levels (Dark Mode)
```swift
DevysColors.darkBg0  // #000000 - True black, deepest background
DevysColors.darkBg1  // #0A0A0A - Editor background
DevysColors.darkBg2  // #121212 - Surface (sidebars, panels)
DevysColors.darkBg3  // #1A1A1A - Elevated surfaces
DevysColors.darkBg4  // #242424 - Hover states
DevysColors.darkBg5  // #2E2E2E - Active/selected states
```

#### Background Levels (Light Mode)
```swift
DevysColors.lightBg0  // #FFFFFF - Pure white
DevysColors.lightBg1  // #FAFAFA - Off-white
DevysColors.lightBg2  // #F5F5F5 - Light gray surface
DevysColors.lightBg3  // #EEEEEE - Elevated
DevysColors.lightBg4  // #E5E5E5 - Hover
DevysColors.lightBg5  // #DDDDDD - Active
```

#### Semantic Colors
```swift
DevysColors.success  // #34C759 - Success states
DevysColors.warning  // #FF9500 - Caution states
DevysColors.error    // #FF3B30 - Error states
```

#### Accent Colors (`AccentColor` enum)
```swift
AccentColor.white     // Default - pure monochrome terminal
AccentColor.coral     // #FF6B6B - Warm, approachable
AccentColor.amber     // #FFB347 - Classic terminal amber
AccentColor.cyan      // #00D4FF - Retro-futuristic
AccentColor.mint      // #7FE5A0 - Matrix-inspired
AccentColor.lavender  // #B19CD9 - Soft, modern
```

Each accent color provides:
- `.color` - The full color
- `.muted` - 12% opacity for backgrounds
- `.hover` - 85% opacity for hover states

#### Adaptive Theme (`DevysTheme`)

Use `DevysTheme` for automatic light/dark mode support:

```swift
struct MyView: View {
    @Environment(\.devysTheme) private var theme

    var body: some View {
        Text("Hello")
            .foregroundStyle(theme.text)
            .background(theme.surface)
    }
}
```

Theme Properties:
- **Backgrounds:** `base`, `content`, `surface`, `elevated`, `hover`, `active`
- **Borders:** `borderSubtle`, `border`, `borderStrong`
- **Text:** `text`, `textSecondary`, `textTertiary`, `textDisabled`
- **Accent:** `accent`, `accentHover`, `accentMuted`

#### Color Extension
```swift
// Initialize color from hex string
Color(hex: "#FF6B6B")
Color(hex: "AABBCC")      // Without hash
Color(hex: "#FFAABBCC")   // With alpha
```

### Typography (`DevysTypography`)

**All fonts are monospace** for terminal aesthetic consistency.

#### Size Scale
```swift
DevysTypography.micro   // 10px - Timestamps, metadata
DevysTypography.xs      // 11px - Labels, hints
DevysTypography.sm      // 12px - Secondary text
DevysTypography.base    // 13px - Body text, UI elements
DevysTypography.md      // 14px - Emphasized text
DevysTypography.lg      // 16px - Section headers (medium weight)
DevysTypography.xl      // 20px - Page titles (semibold)
DevysTypography.xxl     // 24px - Hero (semibold)
DevysTypography.display // 32px - ASCII art, logos (bold)
```

#### Semantic Fonts
```swift
DevysTypography.body    // Standard readable (13px)
DevysTypography.label   // Buttons (13px medium)
DevysTypography.heading // Section headers (11px semibold)
DevysTypography.title   // Page titles (18px semibold)
DevysTypography.caption // Smallest readable (11px)
DevysTypography.mono    // Same as base (all mono!)
```

#### Text Style Helpers
```swift
Text("HEADER").terminalHeader()   // ALL_CAPS with letter spacing
Text("command").terminalCommand() // Base mono font
Text("hint").terminalDim()        // 60% opacity
```

### Spacing (`DevysSpacing`)

Based on a **4px base unit** for precise, consistent spacing.

#### Scale
```swift
DevysSpacing.space0  // 0px
DevysSpacing.space1  // 4px - Tight gaps (icon + label)
DevysSpacing.space2  // 8px - Default element gap
DevysSpacing.space3  // 12px - Related groups
DevysSpacing.space4  // 16px - Section padding
DevysSpacing.space5  // 20px - Card padding
DevysSpacing.space6  // 24px - Large section gaps
DevysSpacing.space8  // 32px - Page margins
DevysSpacing.space10 // 40px - Major section breaks
DevysSpacing.space12 // 48px - Canvas gutters
DevysSpacing.space16 // 64px - Hero spacing
```

#### Semantic Aliases
```swift
DevysSpacing.tight       // 4px
DevysSpacing.normal      // 8px
DevysSpacing.comfortable // 12px
DevysSpacing.relaxed     // 16px
DevysSpacing.spacious    // 24px
```

#### Layout Constants
```swift
DevysSpacing.sidebarCollapsed  // 48px
DevysSpacing.sidebarExpanded   // 240px
DevysSpacing.tabBarHeight      // 36px
DevysSpacing.toolbarHeight     // 44px
DevysSpacing.statusBarHeight   // 24px
DevysSpacing.minPaneWidth      // 300px
DevysSpacing.minPaneHeight     // 200px
```

#### Corner Radii
```swift
DevysSpacing.radiusSm  // 4px
DevysSpacing.radiusMd  // 6px
DevysSpacing.radius    // 8px (default)
DevysSpacing.radiusLg  // 12px
DevysSpacing.radiusXl  // 16px
```

#### Icon Sizes
```swift
DevysSpacing.iconSm  // 12px
DevysSpacing.iconMd  // 16px
DevysSpacing.iconLg  // 20px
DevysSpacing.iconXl  // 24px
```

#### EdgeInsets Helpers
```swift
EdgeInsets.all(16)
EdgeInsets.horizontal(8)
EdgeInsets.vertical(12)
EdgeInsets.symmetric(horizontal: 16, vertical: 8)
```

### Animations (`DevysAnimation`)

Consistent, subtle animations that feel responsive but not distracting.

#### Duration Presets
```swift
DevysAnimation.fast         // 100ms - Micro-interactions
DevysAnimation.default      // 200ms - Standard transitions
DevysAnimation.slow         // 300ms - Larger movements
DevysAnimation.spring       // Bouncy feel for emphasis
DevysAnimation.smoothSpring // Subtle spring
```

#### Named Animations
```swift
DevysAnimation.hover   // Fast - hover changes
DevysAnimation.focus   // 150ms - focus transitions
DevysAnimation.sidebar // 250ms ease-in-out
DevysAnimation.resize  // 200ms - panel resize
DevysAnimation.modal   // Spring - modal appear/disappear
DevysAnimation.tab     // 150ms - tab switch
```

#### Transition Helpers
Internal-only helpers; use standard SwiftUI transitions outside DevysUI.

## UI Components

### Public Components (exported)

#### DevysLogoBlock
```swift
DevysLogoBlock(showTypewriter: true)  // Logo + tagline
```

#### TerminalCommandButton
```swift
TerminalCommandButton("open folder", icon: "folder", isAccent: true) {
    // action
}
```

#### KeyboardShortcutBadge
```swift
KeyboardShortcutBadge("CMD+S")  // Displays: [CMD+S]
```

#### TerminalDivider
```swift
TerminalDivider(useDashes: false)  // Solid line
TerminalDivider(useDashes: true)   // ────── dashed
```

### Internal Components (not exported)

- DevysButton, DevysIcon, StatusIndicator
- ASCIILogo, AnimatedASCIILogo
- BlinkingCursor, TypewriterText, TerminalGlow, ScanlineOverlay, TerminalPrompt

## Public API Surface

### Main Entry Point
```swift
public enum DevysUI {
    public static let version: String
}

// Type aliases for convenience
public typealias Colors = DevysColors
public typealias Typography = DevysTypography
public typealias Spacing = DevysSpacing
public typealias Anim = DevysAnimation
```

### Environment
```swift
@Environment(\.devysTheme) var theme: DevysTheme
```

### Usage Example

```swift
import DevysUI

struct MyView: View {
    @Environment(\.devysTheme) private var theme

    var body: some View {
        VStack(spacing: Spacing.normal) {
            DevysLogoBlock(showTypewriter: true)

            Text("Welcome")
                .font(Typography.title)
                .foregroundStyle(theme.text)

            TerminalCommandButton("get started", icon: "play") {}
            KeyboardShortcutBadge("CMD+ENTER")
            TerminalDivider(useDashes: true)
        }
        .padding(Spacing.relaxed)
        .background(theme.surface)
    }
}
```

## Testing

Tests use Swift Testing framework (`@Test`, `@Suite`).

```swift
import Testing
@testable import DevysUI

@Suite("DevysColors Tests")
struct ColorsTests {
    @Test("Color from hex creates valid color")
    func colorFromHex() {
        let color = Color(hex: "#FF0000")
        // ...
    }
}
```

Run tests:
```bash
swift test
```

## Deprecated Code

The `_deprecated/` folder contains legacy Metal-based ASCII rendering components that have been replaced with simpler SwiftUI implementations:

- Metal shaders for ASCII art effects
- Complex render pipelines
- Welcome image processing with Metal

These are preserved for reference but are not part of the active codebase.

## Conventions

### Naming
- Design tokens use `Devys` prefix (e.g., `DevysColors`, `DevysSpacing`)
- Exported components use stable names (e.g., `DevysLogoBlock`, `TerminalCommandButton`)

### File Organization
- Design system files in `Models/DesignSystem/`
- UI components in `Views/Components/`
- Components grouped by domain (`Common/`, `Terminal/`)

### SwiftUI Patterns
- Use `@Environment(\.devysTheme)` for adaptive theming
- All components include `#Preview` macros
- Button styles use `.buttonStyle(.plain)` with custom hover handling

### Concurrency
- All public enums and structs are `Sendable`
- No actors needed (all state is UI-bound)
- Strict concurrency checking enabled in Package.swift
