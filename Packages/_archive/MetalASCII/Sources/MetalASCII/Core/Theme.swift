// Theme.swift
// MetalASCII - Simple theme system for ASCII art rendering
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import SwiftUI

// MARK: - ASCII Theme

/// Simple theme for ASCII art rendering.
/// Provides colors for foreground, background, and accents.
public struct ASCIITheme: Sendable {
    public let foreground: Color
    public let background: Color
    public let accent: Color
    public let text: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let base: Color
    public let surface: Color
    public let elevated: Color
    public let border: Color
    public let borderSubtle: Color
    public let hover: Color

    public init(
        foreground: Color = .white,
        background: Color = Color(red: 0.02, green: 0.02, blue: 0.03),
        accent: Color = .white,
        text: Color = .white,
        textSecondary: Color = Color(white: 0.7),
        textTertiary: Color = Color(white: 0.5),
        base: Color = Color(red: 0.02, green: 0.02, blue: 0.03),
        surface: Color = Color(red: 0.05, green: 0.05, blue: 0.06),
        elevated: Color = Color(red: 0.08, green: 0.08, blue: 0.09),
        border: Color = Color(white: 0.2),
        borderSubtle: Color = Color(white: 0.15),
        hover: Color = Color(white: 0.1)
    ) {
        self.foreground = foreground
        self.background = background
        self.accent = accent
        self.text = text
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.base = base
        self.surface = surface
        self.elevated = elevated
        self.border = border
        self.borderSubtle = borderSubtle
        self.hover = hover
    }

    // MARK: - Preset Themes

    /// Default dark terminal theme
    public static let terminal = ASCIITheme()

    /// Green terminal theme (classic)
    public static let greenTerminal = ASCIITheme(
        foreground: Color(red: 0.2, green: 1.0, blue: 0.2),
        accent: Color(red: 0.2, green: 1.0, blue: 0.2),
        text: Color(red: 0.2, green: 1.0, blue: 0.2),
        textSecondary: Color(red: 0.15, green: 0.7, blue: 0.15),
        textTertiary: Color(red: 0.1, green: 0.5, blue: 0.1)
    )

    /// Amber terminal theme (retro)
    public static let amberTerminal = ASCIITheme(
        foreground: Color(red: 1.0, green: 0.7, blue: 0.2),
        accent: Color(red: 1.0, green: 0.7, blue: 0.2),
        text: Color(red: 1.0, green: 0.7, blue: 0.2),
        textSecondary: Color(red: 0.8, green: 0.5, blue: 0.1),
        textTertiary: Color(red: 0.6, green: 0.4, blue: 0.1)
    )

    // MARK: - Compatibility Initializer (for migrated code)

    /// Compatibility initializer matching DevysUI API
    public init(isDark: Bool, accentColor: AccentColorCompat) {
        self.init(
            foreground: accentColor.color,
            accent: accentColor.color,
            text: isDark ? .white : .black,
            textSecondary: isDark ? Color(white: 0.7) : Color(white: 0.3),
            textTertiary: isDark ? Color(white: 0.5) : Color(white: 0.5),
            base: isDark ? Color(red: 0.02, green: 0.02, blue: 0.03) : .white
        )
    }
}

// MARK: - Accent Color Compatibility

public enum AccentColorCompat {
    case white
    case coral
    case cyan
    case mint
    case green
    case amber

    public var color: Color {
        switch self {
        case .white: return .white
        case .coral: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .cyan: return .cyan
        case .mint: return .mint
        case .green: return .green
        case .amber: return Color(red: 1.0, green: 0.7, blue: 0.2)
        }
    }
}

// MARK: - Environment Key

private struct ASCIIThemeKey: EnvironmentKey {
    static let defaultValue = ASCIITheme.terminal
}

public extension EnvironmentValues {
    var asciiTheme: ASCIITheme {
        get { self[ASCIIThemeKey.self] }
        set { self[ASCIIThemeKey.self] = newValue }
    }
}

// MARK: - DevysTheme Compatibility Layer

/// Compatibility layer for files migrated from DevysUI
public typealias DevysTheme = ASCIITheme

private struct DevysThemeKey: EnvironmentKey {
    static let defaultValue = ASCIITheme.terminal
}

public extension EnvironmentValues {
    var devysTheme: ASCIITheme {
        get { self[DevysThemeKey.self] }
        set { self[DevysThemeKey.self] = newValue }
    }
}

// MARK: - Typography (Compatibility)

public enum DevysTypography {
    public static let base = Font.system(size: 13, design: .monospaced)
    public static let sm = Font.system(size: 12, design: .monospaced)
    public static let xs = Font.system(size: 10, design: .monospaced)
    public static let label = Font.system(size: 12, weight: .medium, design: .monospaced)
    public static let heading = Font.system(size: 11, weight: .semibold, design: .monospaced)
    public static let xl = Font.system(size: 18, weight: .bold, design: .monospaced)
    public static let headerTracking: CGFloat = 2
}

// MARK: - Spacing (Compatibility)

public enum DevysSpacing {
    public static let space2: CGFloat = 4
    public static let space3: CGFloat = 8
    public static let space4: CGFloat = 12
    public static let space8: CGFloat = 24
    public static let space10: CGFloat = 32
    public static let radiusSm: CGFloat = 4
    public static let radiusMd: CGFloat = 8
}

#endif // os(macOS)
