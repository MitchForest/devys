// SplitColors.swift
// DevysSplit - Observable color state for theming

import SwiftUI

/// Observable container for split view colors.
/// Injected via environment to allow dynamic theming.
@Observable
final class SplitColors: @unchecked Sendable {
    var accent: Color
    var tabBarBackground: Color
    var activeTabBackground: Color
    var inactiveText: Color
    var activeText: Color
    var separator: Color
    var contentBackground: Color

    init(
        accent: Color = .accentColor,
        tabBarBackground: Color = Color(nsColor: .windowBackgroundColor),
        activeTabBackground: Color = Color(nsColor: .controlBackgroundColor),
        inactiveText: Color = .secondary,
        activeText: Color = .primary,
        separator: Color = Color(nsColor: .separatorColor),
        contentBackground: Color = Color(nsColor: .textBackgroundColor)
    ) {
        self.accent = accent
        self.tabBarBackground = tabBarBackground
        self.activeTabBackground = activeTabBackground
        self.inactiveText = inactiveText
        self.activeText = activeText
        self.separator = separator
        self.contentBackground = contentBackground
    }

    /// Update all colors from configuration
    func update(from config: DevysSplitConfiguration.Colors) {
        self.accent = config.accent
        self.tabBarBackground = config.tabBarBackground
        self.activeTabBackground = config.activeTabBackground
        self.inactiveText = config.inactiveText
        self.activeText = config.activeText
        self.separator = config.separator
        self.contentBackground = config.contentBackground
    }
}

// MARK: - Environment Key

private struct SplitColorsKey: EnvironmentKey {
    static let defaultValue = SplitColors()
}

extension EnvironmentValues {
    var splitColors: SplitColors {
        get { self[SplitColorsKey.self] }
        set { self[SplitColorsKey.self] = newValue }
    }
}
