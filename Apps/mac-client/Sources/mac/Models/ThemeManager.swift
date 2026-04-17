// ThemeManager.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import GhosttyTerminal
import UI
import Observation
import SwiftUI
import Workspace

// MARK: - Theme Manager

@MainActor
@Observable
final class ThemeManager {
    /// Appearance mode preference (default: dark for terminal aesthetic)
    var appearanceMode: AppearanceMode = .dark
    
    /// Current accent color (default: white/monochrome for pure terminal look)
    var accentColor: AccentColor = .graphite

    var preferredColorScheme: ColorScheme? {
        appearanceMode.preferredColorScheme
    }

    var nsAppearance: NSAppearance? {
        switch appearanceMode {
        case .auto:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    /// Returns the DevysTheme based on current mode and accent
    func theme(systemColorScheme: ColorScheme) -> DevysTheme {
        DevysTheme(
            isDark: resolvedColorScheme(systemColorScheme: systemColorScheme) == .dark,
            accentColor: accentColor
        )
    }

    func ghosttyAppearance(systemColorScheme: ColorScheme) -> GhosttyTerminalAppearance {
        let isDarkMode = resolvedColorScheme(systemColorScheme: systemColorScheme) == .dark
        let background = GhosttyTerminalColor(hex: isDarkMode ? "#0C0B0A" : "#FAF8F5")
        let foreground = GhosttyTerminalColor(hex: isDarkMode ? "#EDE8E0" : "#1C1A17")
        let fallbackSelection = GhosttyTerminalColor(hex: isDarkMode ? "#2E2C28" : "#DDD9D1")
        let accent = GhosttyTerminalColor(hex: accentColor.rawValue)

        let cursorColor = accent.contrastRatio(with: background) >= 2.5 ? accent : foreground
        let selectionCandidate = accent.blended(
            over: background,
            opacity: isDarkMode ? 0.22 : 0.18
        )
        let selectionBackground = selectionCandidate.contrastRatio(with: background) >= 1.12
            ? selectionCandidate
            : fallbackSelection

        return GhosttyTerminalAppearance(
            colorScheme: isDarkMode ? .dark : .light,
            background: background,
            foreground: foreground,
            cursorColor: cursorColor,
            cursorText: cursorColor.idealTextColor(),
            selectionBackground: selectionBackground,
            selectionForeground: foreground,
            palette: isDarkMode ? Self.darkTerminalPalette : Self.lightTerminalPalette
        )
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        appearanceMode.resolvedColorScheme(systemColorScheme: systemColorScheme)
    }

    func applyAppearance() {
        NSApp.appearance = nsAppearance
    }
    
    /// Update accent color from settings string
    func setAccentColor(from rawValue: String) {
        if let color = AccentColor(rawValue: rawValue) {
            accentColor = color
        }
    }

    private static let darkTerminalPalette: [GhosttyTerminalColor] = [
        GhosttyTerminalColor(hex: "#121212"),
        GhosttyTerminalColor(hex: "#E06C75"),
        GhosttyTerminalColor(hex: "#98C379"),
        GhosttyTerminalColor(hex: "#E5C07B"),
        GhosttyTerminalColor(hex: "#61AFEF"),
        GhosttyTerminalColor(hex: "#C678DD"),
        GhosttyTerminalColor(hex: "#56B6C2"),
        GhosttyTerminalColor(hex: "#A0A0A0"),
        GhosttyTerminalColor(hex: "#666666"),
        GhosttyTerminalColor(hex: "#FF8A93"),
        GhosttyTerminalColor(hex: "#B4E28F"),
        GhosttyTerminalColor(hex: "#FFD08A"),
        GhosttyTerminalColor(hex: "#7BC3FF"),
        GhosttyTerminalColor(hex: "#D19AEE"),
        GhosttyTerminalColor(hex: "#7BDFF2"),
        GhosttyTerminalColor(hex: "#EFEFEF"),
    ]

    private static let lightTerminalPalette: [GhosttyTerminalColor] = [
        GhosttyTerminalColor(hex: "#1A1A1A"),
        GhosttyTerminalColor(hex: "#C43E1C"),
        GhosttyTerminalColor(hex: "#2F6F44"),
        GhosttyTerminalColor(hex: "#9A6700"),
        GhosttyTerminalColor(hex: "#005CC5"),
        GhosttyTerminalColor(hex: "#8250DF"),
        GhosttyTerminalColor(hex: "#0A7F7F"),
        GhosttyTerminalColor(hex: "#555555"),
        GhosttyTerminalColor(hex: "#888888"),
        GhosttyTerminalColor(hex: "#D84A26"),
        GhosttyTerminalColor(hex: "#3E8A52"),
        GhosttyTerminalColor(hex: "#B27D12"),
        GhosttyTerminalColor(hex: "#1F6FEB"),
        GhosttyTerminalColor(hex: "#A371F7"),
        GhosttyTerminalColor(hex: "#1B9AAA"),
        GhosttyTerminalColor(hex: "#FFFFFF"),
    ]
}
