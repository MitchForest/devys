// Colors.swift
// Devys Design System — Dia-modeled: layered surfaces, monochrome warmth
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Color Extension

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Raw Palette

/// Raw color values. Three surface levels per mode, not six.
/// Use `Theme` for adaptive access, not these directly.
public enum Colors {

    // MARK: - Dark Mode Surfaces

    /// Window background, sidebar, rail, gaps between panes
    public static let darkBase = Color(hex: "#121110")

    /// Split pane content areas, elevated cards
    public static let darkCard = Color(hex: "#1C1B19")

    /// Popovers, dropdowns, command palette, modals
    public static let darkOverlay = Color(hex: "#252321")

    // MARK: - Light Mode Surfaces

    public static let lightBase = Color(hex: "#F5F3F0")
    public static let lightCard = Color(hex: "#FFFFFF")
    public static let lightOverlay = Color(hex: "#FFFFFF")

    // MARK: - Dark Mode Text

    public static let darkText = Color(hex: "#EDEDEB")
    public static let darkTextSecondary = Color(hex: "#9B9990")
    public static let darkTextTertiary = Color(hex: "#5E5C57")
    public static let darkTerminalText = Color(hex: "#FFFFFF")

    // MARK: - Light Mode Text

    public static let lightText = Color(hex: "#1C1B19")
    public static let lightTextSecondary = Color(hex: "#7A7772")
    public static let lightTextTertiary = Color(hex: "#AFACA6")
    public static let lightTerminalText = Color(hex: "#000000")

    // MARK: - Borders

    public static let darkBorder = Color(hex: "#2A2826")
    public static let lightBorder = Color(hex: "#E5E2DD")

    // MARK: - Semantic Status (Fixed, not theme-dependent)

    public static let success = Color(hex: "#5AAE6B")
    public static let warning = Color(hex: "#D4A54A")
    public static let error = Color(hex: "#D45C5C")
    public static let info = Color(hex: "#4A7FD4")

}

// MARK: - Accent Color

/// Theme accent colors. Graphite is the monochrome default.
public enum AccentColor: String, CaseIterable, Codable, Sendable {
    case graphite = "#8B8885"
    case blue = "#4A7FD4"
    case teal = "#3DBDA7"
    case green = "#5AAE6B"
    case lime = "#8BBD5A"
    case yellow = "#D4B44A"
    case orange = "#D48A4A"
    case red = "#D45C5C"
    case pink = "#D46B96"
    case violet = "#9B7FD4"

    public var color: Color { Color(hex: rawValue) }
    public var muted: Color { color.opacity(0.15) }
    public var subtle: Color { color.opacity(0.06) }

    /// Whether this accent is the monochrome default.
    public var isMonochrome: Bool { self == .graphite }

    public var displayName: String {
        switch self {
        case .graphite: "Graphite"
        case .blue: "Blue"
        case .teal: "Teal"
        case .green: "Green"
        case .lime: "Lime"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .red: "Red"
        case .pink: "Pink"
        case .violet: "Violet"
        }
    }

    public var isPerceptuallyLight: Bool {
        let hex = rawValue.dropFirst()
        guard hex.count == 6,
              let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(4).prefix(2), radix: 16)
        else { return false }

        func linearize(_ c: UInt8) -> Double {
            let s = Double(c) / 255.0
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
        return luminance > 0.5
    }

}

// MARK: - Theme

public struct Theme: Sendable {
    public let isDark: Bool
    public let accentColor: AccentColor

    public init(isDark: Bool, accentColor: AccentColor = .graphite) {
        self.isDark = isDark
        self.accentColor = accentColor
    }

    // MARK: Surfaces

    /// Window background, sidebar, rail, gaps between panes.
    public var base: Color { isDark ? Colors.darkBase : Colors.lightBase }

    /// Split pane content, elevated cards.
    public var card: Color { isDark ? Colors.darkCard : Colors.lightCard }

    /// Popovers, dropdowns, command palette, modals.
    public var overlay: Color { isDark ? Colors.darkOverlay : Colors.lightOverlay }

    /// Terminal surface background.
    public var terminalBackground: Color { isDark ? Colors.darkCard : Colors.lightCard }

    // MARK: Derived States

    /// Hover state — base lightened/darkened slightly.
    public var hover: Color {
        isDark ? Color(hex: "#1A1918") : Color(hex: "#ECEAE6")
    }

    /// Active/pressed state.
    public var active: Color {
        isDark ? Color(hex: "#222120") : Color(hex: "#E4E1DC")
    }

    /// Hover within a card context.
    public var cardHover: Color {
        isDark ? Color(hex: "#242321") : Color(hex: "#F9F8F6")
    }

    // MARK: Text

    public var text: Color { isDark ? Colors.darkText : Colors.lightText }
    public var textSecondary: Color { isDark ? Colors.darkTextSecondary : Colors.lightTextSecondary }
    public var textTertiary: Color { isDark ? Colors.darkTextTertiary : Colors.lightTextTertiary }
    public var terminalText: Color { isDark ? Colors.darkTerminalText : Colors.lightTerminalText }

    // MARK: Borders

    /// Standard border for cards, inputs, dividers.
    public var border: Color { isDark ? Colors.darkBorder : Colors.lightBorder }

    /// Focus ring — accent at 50% opacity.
    public var borderFocus: Color { accentColor.color.opacity(0.5) }

    // MARK: Accent

    public var accent: Color { accentColor.color }
    public var accentMuted: Color { accentColor.muted }
    public var accentSubtle: Color { accentColor.subtle }
    public var accentForeground: Color {
        if accentColor.isMonochrome {
            return isDark ? Colors.darkBase : Colors.lightBase
        }
        return accentColor.isPerceptuallyLight ? Color(hex: "#121110") : .white
    }

    /// Primary button background: accent if colored, text color if monochrome.
    public var primaryFill: Color {
        accentColor.isMonochrome ? text : accent
    }

    /// Primary button foreground: base if monochrome, contrast color if colored.
    public var primaryFillForeground: Color {
        accentColor.isMonochrome ? base : accentForeground
    }

    // MARK: Semantic Status

    public var success: Color { Colors.success }
    public var warning: Color { Colors.warning }
    public var error: Color { Colors.error }
    public var info: Color { Colors.info }

    public var successSubtle: Color { Colors.success.opacity(0.10) }
    public var warningSubtle: Color { Colors.warning.opacity(0.10) }
    public var errorSubtle: Color { Colors.error.opacity(0.10) }
    public var infoSubtle: Color { Colors.info.opacity(0.10) }

}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(isDark: true, accentColor: .graphite)
}

public extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }

    var devysTheme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
