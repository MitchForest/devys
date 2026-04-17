import Testing
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

        #expect(manager.accentColor == .orange)
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
}
