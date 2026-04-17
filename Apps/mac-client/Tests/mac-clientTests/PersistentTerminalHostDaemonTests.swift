import Testing
@testable import mac_client

@Suite("Persistent Terminal Host Daemon Tests")
struct PersistentTerminalHostDaemonTests {
    @Test("Terminal sessions advertise Ghostty truecolor capabilities")
    func terminalSessionEnvironment() {
        let assignments = terminalSessionEnvironmentAssignments()

        #expect(assignments["TERM"] == "xterm-256color")
        #expect(assignments["COLORTERM"] == "truecolor")
        #expect(assignments["COLORFGBG"] == "15;0")
        #expect(assignments["TERM_PROGRAM"] == "ghostty")
        #expect(assignments["TERM_PROGRAM_VERSION"] == terminalSessionTermProgramVersion())
        #expect(terminalSessionEnvironmentKeysToUnset() == ["NO_COLOR"])
    }

    @Test("Command launches use the configured login shell with interactive semantics")
    func terminalShellLaunchConfigurationUsesLoginInteractiveShell() {
        let configuration = terminalShellLaunchConfiguration(
            launchCommand: "claude",
            environment: ["SHELL": "/opt/homebrew/bin/zsh"]
        )

        #expect(configuration.executablePath == "/opt/homebrew/bin/zsh")
        #expect(configuration.arguments == ["zsh", "-i", "-l", "-c", "claude"])
    }

    @Test("Missing shell configuration falls back to zsh")
    func terminalShellLaunchConfigurationFallsBackToZsh() {
        let configuration = terminalShellLaunchConfiguration(
            launchCommand: nil,
            environment: [:]
        )

        #expect(configuration.executablePath == "/bin/zsh")
        #expect(configuration.arguments == ["zsh", "-i", "-l"])
    }
}
