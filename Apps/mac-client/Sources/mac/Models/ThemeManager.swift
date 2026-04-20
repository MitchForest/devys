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
    var appearanceMode: AppearanceMode
    
    /// Current accent color (default: white/monochrome for pure terminal look)
    var accentColor: AccentColor

    init(
        appearanceMode: AppearanceMode = .dark,
        accentColor: AccentColor = .graphite
    ) {
        self.appearanceMode = appearanceMode
        self.accentColor = accentColor
    }

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
        let theme = theme(systemColorScheme: systemColorScheme)
        let background = GhosttyTerminalColor(theme.terminalBackground)
        let foreground = GhosttyTerminalColor(theme.terminalText)
        let fallbackSelection = GhosttyTerminalColor(theme.active)
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
            selectionBackground: selectionBackground,
            palette: isDarkMode
                ? GhosttyTerminalAppearance.ghosttyDarkPalette
                : GhosttyTerminalAppearance.ghosttyLightPalette
        )
    }

    func resolvedColorScheme(systemColorScheme: ColorScheme) -> ColorScheme {
        appearanceMode.resolvedColorScheme(systemColorScheme: systemColorScheme)
    }

    func applyAppearance() {
        NSApp.appearance = nsAppearance
    }

    static func accentColor(from rawValue: String) -> AccentColor {
        AccentColor(rawValue: rawValue) ?? .graphite
    }

    static func bootstrapTheme(
        appearanceMode: AppearanceMode,
        accentColor: AccentColor,
        systemColorScheme: ColorScheme = currentSystemColorScheme()
    ) -> DevysTheme {
        DevysTheme(
            isDark: appearanceMode.resolvedColorScheme(systemColorScheme: systemColorScheme) == .dark,
            accentColor: accentColor
        )
    }
    
    /// Update accent color from settings string
    func setAccentColor(from rawValue: String) {
        accentColor = Self.accentColor(from: rawValue)
    }

    private static func currentSystemColorScheme() -> ColorScheme {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }
}

private extension GhosttyTerminalColor {
    init(_ color: Color) {
        let resolved = NSColor(color).usingColorSpace(.deviceRGB) ?? .black
        self.init(
            red: UInt8(clamping: Int((resolved.redComponent * 255).rounded())),
            green: UInt8(clamping: Int((resolved.greenComponent * 255).rounded())),
            blue: UInt8(clamping: Int((resolved.blueComponent * 255).rounded()))
        )
    }
}
