import Testing
import GhosttyTerminal
import UI
@testable import mac_client

@Suite("ThemeManager Tests")
struct ThemeManagerTests {
    @Test("Accent colors update from valid raw values")
    @MainActor
    func setAccentColor() {
        let manager = ThemeManager()

        manager.setAccentColor(from: AccentColor.teal.rawValue)

        #expect(manager.accentColor == .teal)
        #expect(manager.resolvedColorScheme(systemColorScheme: .light) == .dark)
    }

    @Test("Invalid accent values do not change the current accent")
    @MainActor
    func invalidAccentColor() {
        let manager = ThemeManager()
        manager.accentColor = .orange

        manager.setAccentColor(from: "not-a-color")

        #expect(manager.accentColor == .graphite)
    }

    @Test("Auto mode follows the current system appearance")
    @MainActor
    func autoModeResolvesFromSystemAppearance() {
        let manager = ThemeManager()
        manager.appearanceMode = .auto

        #expect(manager.preferredColorScheme == nil)
        #expect(manager.nsAppearance == nil)
        #expect(manager.resolvedColorScheme(systemColorScheme: .light) == .light)
        #expect(manager.resolvedColorScheme(systemColorScheme: .dark) == .dark)
    }

    @Test("Bootstrap theme uses explicit appearance mode instead of current system scheme")
    @MainActor
    func bootstrapThemeUsesPersistedAppearanceMode() {
        let lightTheme = ThemeManager.bootstrapTheme(
            appearanceMode: .light,
            accentColor: .teal,
            systemColorScheme: .dark
        )
        let darkTheme = ThemeManager.bootstrapTheme(
            appearanceMode: .dark,
            accentColor: .orange,
            systemColorScheme: .light
        )

        #expect(lightTheme.isDark == false)
        #expect(lightTheme.accentColor == .teal)
        #expect(darkTheme.isDark == true)
        #expect(darkTheme.accentColor == .orange)
    }

    @Test("Terminal appearance maps dark mode to canonical theme tokens")
    @MainActor
    func terminalAppearanceUsesDarkThemeTokens() {
        let manager = ThemeManager(appearanceMode: .dark, accentColor: .graphite)

        let appearance = manager.ghosttyAppearance(systemColorScheme: .light)

        #expect(appearance.colorScheme == .dark)
        #expect(appearance.background.packedRGB == 0x1C1B19)
        #expect(appearance.foreground.packedRGB == 0xFFFFFF)
        #expect(appearance.cursorColor.packedRGB == 0x8B8885)
        #expect(appearance.selectionBackground != appearance.background)
        #expect(appearance.palette == GhosttyTerminalAppearance.ghosttyDarkPalette)
    }

    @Test("Terminal appearance maps light mode to canonical theme tokens")
    @MainActor
    func terminalAppearanceUsesLightThemeTokens() {
        let manager = ThemeManager(appearanceMode: .light, accentColor: .graphite)

        let appearance = manager.ghosttyAppearance(systemColorScheme: .dark)

        #expect(appearance.colorScheme == .light)
        #expect(appearance.background.packedRGB == 0xFFFFFF)
        #expect(appearance.foreground.packedRGB == 0x000000)
        #expect(appearance.cursorColor.packedRGB == 0x8B8885)
        #expect(appearance.selectionBackground != appearance.background)
        #expect(appearance.palette == GhosttyTerminalAppearance.ghosttyLightPalette)
    }
}
