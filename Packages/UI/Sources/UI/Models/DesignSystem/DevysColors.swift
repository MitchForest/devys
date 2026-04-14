// DevysColors.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// The Devys color palette.
///
/// A terminal-inspired monochrome palette with configurable accent.
/// Pure blacks and whites create depth through contrast, not color.
/// Supports both light and dark modes with adaptive colors.
public enum DevysColors {
    
    // MARK: - Dark Mode Background Levels (Pure Monochrome)
    
    /// Dark: Level 0 - True black, deepest background
    public static let darkBg0 = Color(hex: "#000000")
    
    /// Dark: Level 1 - Near black, editor background
    public static let darkBg1 = Color(hex: "#0A0A0A")
    
    /// Dark: Level 2 - Surface background (sidebar, panels)
    public static let darkBg2 = Color(hex: "#121212")
    
    /// Dark: Level 3 - Elevated surfaces
    public static let darkBg3 = Color(hex: "#1A1A1A")
    
    /// Dark: Level 4 - Hover states
    public static let darkBg4 = Color(hex: "#242424")
    
    /// Dark: Level 5 - Active/selected states
    public static let darkBg5 = Color(hex: "#2E2E2E")
    
    // MARK: - Light Mode Background Levels
    
    /// Light: Level 0 - Pure white
    public static let lightBg0 = Color(hex: "#FFFFFF")
    
    /// Light: Level 1 - Off-white
    public static let lightBg1 = Color(hex: "#FAFAFA")
    
    /// Light: Level 2 - Light gray surface
    public static let lightBg2 = Color(hex: "#F5F5F5")
    
    /// Light: Level 3 - Elevated
    public static let lightBg3 = Color(hex: "#EEEEEE")
    
    /// Light: Level 4 - Hover
    public static let lightBg4 = Color(hex: "#E5E5E5")
    
    /// Light: Level 5 - Active
    public static let lightBg5 = Color(hex: "#DDDDDD")
    
    // MARK: - Dark Mode Borders
    
    /// Dark: Subtle border
    public static let darkBorderSubtle = Color(hex: "#1A1A1A")
    
    /// Dark: Default border
    public static let darkBorder = Color(hex: "#2A2A2A")
    
    /// Dark: Strong border
    public static let darkBorderStrong = Color(hex: "#3A3A3A")
    
    // MARK: - Light Mode Borders
    
    /// Light: Subtle border
    public static let lightBorderSubtle = Color(hex: "#E8E8E8")
    
    /// Light: Default border
    public static let lightBorder = Color(hex: "#D5D5D5")
    
    /// Light: Strong border
    public static let lightBorderStrong = Color(hex: "#C0C0C0")
    
    // MARK: - Dark Mode Text (High Contrast)
    
    /// Dark: Primary text - bright white
    public static let darkText = Color(hex: "#EFEFEF")
    
    /// Dark: Secondary text
    public static let darkTextSecondary = Color(hex: "#A0A0A0")
    
    /// Dark: Tertiary text
    public static let darkTextTertiary = Color(hex: "#666666")
    
    /// Dark: Disabled text
    public static let darkTextDisabled = Color(hex: "#444444")
    
    // MARK: - Light Mode Text
    
    /// Light: Primary text - near black
    public static let lightText = Color(hex: "#1A1A1A")
    
    /// Light: Secondary text
    public static let lightTextSecondary = Color(hex: "#555555")
    
    /// Light: Tertiary text
    public static let lightTextTertiary = Color(hex: "#888888")
    
    /// Light: Disabled text
    public static let lightTextDisabled = Color(hex: "#AAAAAA")
    
    // MARK: - Semantic (Status Only)
    
    /// Success (explicit success states only)
    public static let success = Color(hex: "#34C759")
    
    /// Warning (caution states)
    public static let warning = Color(hex: "#FF9500")
    
    /// Error (errors only)
    public static let error = Color(hex: "#FF3B30")
    
    // MARK: - Static Dark Palette
    
    public static let bg0 = darkBg0
    public static let bg1 = darkBg1
    public static let bg2 = darkBg2
    public static let bg3 = darkBg3
    public static let bg4 = darkBg4
    
    public static let borderSubtle = darkBorderSubtle
    public static let border = darkBorder
    public static let borderStrong = darkBorderStrong
    
    public static let text = darkText
    public static let textSecondary = darkTextSecondary
    public static let textTertiary = darkTextTertiary
    
    public static let base = darkBg0
    public static let surface = darkBg2
    public static let elevated = darkBg3
    public static let textPrimary = darkText
}

// MARK: - Accent Color

/// Configurable accent colors for the terminal aesthetic.
/// Users can choose their preferred accent from this curated palette.
/// Default is white for pure monochrome terminal look.
public enum AccentColor: String, CaseIterable, Codable, Sendable {
    case white = "#FFFFFF"      // Default - pure monochrome terminal
    case coral = "#FF6B6B"      // Warm, approachable
    case amber = "#FFB347"      // Classic terminal amber
    case cyan = "#00D4FF"       // Retro-futuristic
    case mint = "#7FE5A0"       // Matrix-inspired (subtle)
    case lavender = "#B19CD9"   // Soft, modern
    
    /// The SwiftUI Color for this accent
    public var color: Color {
        Color(hex: self.rawValue)
    }
    
    /// A muted version for backgrounds/highlights
    public var muted: Color {
        color.opacity(0.12)
    }
    
    /// A hover state variant
    public var hover: Color {
        color.opacity(0.85)
    }
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .white: return "Monochrome"
        case .coral: return "Coral"
        case .amber: return "Amber"
        case .cyan: return "Cyan"
        case .mint: return "Mint"
        case .lavender: return "Lavender"
        }
    }
    
    /// Icon/emoji for visual picker
    public var icon: String {
        switch self {
        case .white: return "⚪"
        case .coral: return "🔴"
        case .amber: return "🟠"
        case .cyan: return "🔵"
        case .mint: return "🟢"
        case .lavender: return "🟣"
        }
    }

    /// Whether this accent is perceptually light (needs dark text on it).
    /// Uses WCAG 2.1 relative luminance from the hex raw value.
    public var isPerceptuallyLight: Bool {
        let hex = rawValue.dropFirst() // drop "#"
        guard hex.count == 6,
              let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.dropFirst(4).prefix(2), radix: 16)
        else { return false }

        func linearize(_ component: UInt8) -> Double {
            let s = Double(component) / 255.0
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
        return luminance > 0.5
    }
}

// MARK: - Adaptive Theme Colors

/// Adaptive colors that respond to the current color scheme and accent preference.
/// Use these in views to get automatic light/dark mode support.
public struct DevysTheme: Sendable {
    public let isDark: Bool
    public let accentColor: AccentColor
    
    public init(isDark: Bool, accentColor: AccentColor = .coral) {
        self.isDark = isDark
        self.accentColor = accentColor
    }
    
    // MARK: - Backgrounds
    
    /// Main content background (editor, canvas) - true black/white
    public var base: Color {
        isDark ? DevysColors.darkBg0 : DevysColors.lightBg0
    }
    
    /// Content area background (slightly elevated from base)
    public var content: Color {
        isDark ? DevysColors.darkBg1 : DevysColors.lightBg1
    }
    
    /// Surface background (sidebar, tab bar, panels)
    public var surface: Color {
        isDark ? DevysColors.darkBg2 : DevysColors.lightBg2
    }
    
    /// Elevated surface (cards, popovers)
    public var elevated: Color {
        isDark ? DevysColors.darkBg3 : DevysColors.lightBg3
    }
    
    /// Hover state
    public var hover: Color {
        isDark ? DevysColors.darkBg4 : DevysColors.lightBg4
    }
    
    /// Active/pressed state
    public var active: Color {
        isDark ? DevysColors.darkBg5 : DevysColors.lightBg5
    }
    
    // MARK: - Borders
    
    /// Subtle border (use most often)
    public var borderSubtle: Color {
        isDark ? DevysColors.darkBorderSubtle : DevysColors.lightBorderSubtle
    }
    
    /// Default border
    public var border: Color {
        isDark ? DevysColors.darkBorder : DevysColors.lightBorder
    }
    
    /// Strong border (rare, for emphasis)
    public var borderStrong: Color {
        isDark ? DevysColors.darkBorderStrong : DevysColors.lightBorderStrong
    }
    
    // MARK: - Text
    
    /// Primary text - high contrast
    public var text: Color {
        isDark ? DevysColors.darkText : DevysColors.lightText
    }
    
    /// Secondary text (descriptions, labels)
    public var textSecondary: Color {
        isDark ? DevysColors.darkTextSecondary : DevysColors.lightTextSecondary
    }
    
    /// Tertiary text (placeholders, hints)
    public var textTertiary: Color {
        isDark ? DevysColors.darkTextTertiary : DevysColors.lightTextTertiary
    }
    
    /// Disabled text
    public var textDisabled: Color {
        isDark ? DevysColors.darkTextDisabled : DevysColors.lightTextDisabled
    }
    
    // MARK: - Accent (Configurable)
    
    /// Primary accent color - use sparingly
    public var accent: Color {
        accentColor.color
    }
    
    /// Accent for hover states
    public var accentHover: Color {
        accentColor.hover
    }
    
    /// Accent muted for subtle highlights
    public var accentMuted: Color {
        accentColor.muted
    }

    /// Foreground color that ensures contrast on the accent background.
    public var accentForeground: Color {
        accentColor.isPerceptuallyLight ? DevysColors.darkBg0 : DevysColors.lightBg0
    }

    /// Accent color guaranteed visible against the current background.
    /// Non-white accents are returned unchanged. White accent in light mode
    /// would be invisible, so it falls back to the primary text color.
    public var visibleAccent: Color {
        if !isDark && accentColor == .white {
            return text
        }
        return accent
    }
}

// MARK: - Environment Key

private struct DevysThemeKey: EnvironmentKey {
    // Default to dark mode with white/monochrome accent for pure terminal aesthetic
    static let defaultValue = DevysTheme(isDark: true, accentColor: .white)
}

public extension EnvironmentValues {
    var devysTheme: DevysTheme {
        get { self[DevysThemeKey.self] }
        set { self[DevysThemeKey.self] = newValue }
    }
}

// MARK: - Color Extension

public extension Color {
    /// Initialize a Color from a hex string.
    /// - Parameter hex: Hex string (with or without #)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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
