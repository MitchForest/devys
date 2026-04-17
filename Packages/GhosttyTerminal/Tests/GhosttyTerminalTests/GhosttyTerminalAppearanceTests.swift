import Testing
@testable import GhosttyTerminal

@Suite("Ghostty Terminal Appearance Tests")
struct GhosttyTerminalAppearanceTests {
    @Test("Appearance config preserves Devys palette defaults")
    func configTextIncludesPaletteEntries() {
        let configText = GhosttyTerminalAppearance.defaultDark.configText

        #expect(configText.contains("background = #000000"))
        #expect(configText.contains("foreground = #EFEFEF"))
        #expect(configText.contains("palette = 0=#121212"))
        #expect(configText.contains("palette = 15=#EFEFEF"))
    }

    @Test("Launch environment config enables rich color output")
    func launchEnvironmentConfigText() {
        let configText = ghosttyTerminalLaunchEnvironmentConfigText(
            colorScheme: .dark,
            termProgramVersion: "1.2.3"
        )

        #expect(configText.contains("env = TERM=xterm-256color"))
        #expect(configText.contains("env = COLORTERM=truecolor"))
        #expect(configText.contains("env = TERM_PROGRAM=ghostty"))
        #expect(configText.contains("env = TERM_PROGRAM_VERSION=1.2.3"))
        #expect(configText.contains("env = COLORFGBG=15;0"))
        #expect(configText.contains("env = NO_COLOR="))
    }
}
