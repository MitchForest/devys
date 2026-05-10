import SwiftUI

public enum DevysThemeMode: String, CaseIterable, Codable, Sendable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    public var displayName: String { rawValue }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            nil
        }
    }

    public func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            systemColorScheme
        }
    }
}

public enum DevysThemeRegistry {
    public static let modes: [DevysThemeMode] = [.light, .dark, .system]

    public static func theme(
        for mode: DevysThemeMode,
        systemColorScheme: ColorScheme,
        accentColor: AccentColor = .graphite
    ) -> Theme {
        Theme(
            isDark: mode.resolvedColorScheme(systemColorScheme: systemColorScheme) == .dark,
            accentColor: accentColor
        )
    }
}
