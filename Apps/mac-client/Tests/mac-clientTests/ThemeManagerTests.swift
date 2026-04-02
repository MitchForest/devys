import Testing
import UI
@testable import mac_client

@Suite("ThemeManager Tests")
struct ThemeManagerTests {
    @Test("Accent colors update from valid raw values")
    @MainActor
    func setAccentColor() {
        let manager = ThemeManager()

        manager.setAccentColor(from: AccentColor.cyan.rawValue)

        #expect(manager.accentColor == .cyan)
        #expect(manager.colorScheme == .dark)
    }

    @Test("Invalid accent values do not change the current accent")
    @MainActor
    func invalidAccentColor() {
        let manager = ThemeManager()
        manager.accentColor = .amber

        manager.setAccentColor(from: "not-a-color")

        #expect(manager.accentColor == .amber)
    }
}
