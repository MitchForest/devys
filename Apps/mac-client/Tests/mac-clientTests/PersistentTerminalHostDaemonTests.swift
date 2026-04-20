import Foundation
import Testing
@testable import mac_client

@Suite("Persistent Terminal Host Daemon Tests")
struct PersistentTerminalHostDaemonTests {
    private static let stableSessionID =
        UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        ?? UUID()

    @Test("Terminal sessions advertise Ghostty truecolor capabilities")
    func terminalSessionEnvironment() throws {
        let assignments = try terminalSessionEnvironmentAssignments()

        #expect(assignments["TERM"] == "xterm-ghostty")
        #expect(assignments["COLORTERM"] == "truecolor")
        #expect(assignments["COLORFGBG"] == "15;0")
        #expect(assignments["TERMINFO"] == terminalSessionTerminfoDirectory())
        #expect(assignments["TERM_PROGRAM"] == "ghostty")
        #expect(assignments["TERM_PROGRAM_VERSION"] == terminalSessionTermProgramVersion())
        #expect(terminalSessionEnvironmentKeysToUnset() == ["NO_COLOR"])
    }

    @Test("Compatibility shell launches use login and interactive semantics")
    func compatibilityShellLaunchConfigurationUsesLoginInteractiveShell() {
        let configuration = terminalShellLaunchConfiguration(
            launchProfile: .compatibilityShell,
            launchCommand: "claude",
            environment: ["SHELL": "/opt/homebrew/bin/zsh"]
        )

        #expect(configuration.executablePath == "/opt/homebrew/bin/zsh")
        #expect(configuration.arguments == ["zsh", "-i", "-l", "-c", "claude"])
    }

    @Test("Fast shell launches skip login semantics for blank tabs")
    func fastShellLaunchConfigurationSkipsLoginSemantics() {
        let configuration = terminalShellLaunchConfiguration(
            launchProfile: .fastShell,
            launchCommand: nil,
            environment: ["SHELL": "/opt/homebrew/bin/zsh"]
        )

        #expect(configuration.executablePath == "/opt/homebrew/bin/zsh")
        #expect(configuration.arguments == ["zsh", "-i"])
    }

    @Test("Fast shell command launches stay off the compatibility path")
    func fastShellCommandLaunchConfigurationSkipsLoginSemantics() {
        let configuration = terminalShellLaunchConfiguration(
            launchProfile: .fastShell,
            launchCommand: "claude",
            environment: ["SHELL": "/opt/homebrew/bin/zsh"]
        )

        #expect(configuration.executablePath == "/opt/homebrew/bin/zsh")
        #expect(configuration.arguments == ["zsh", "-i", "-c", "claude"])
    }

    @Test("Missing shell configuration falls back to zsh")
    func terminalShellLaunchConfigurationFallsBackToZsh() {
        let configuration = terminalShellLaunchConfiguration(
            launchProfile: .compatibilityShell,
            launchCommand: nil,
            environment: [:]
        )

        #expect(configuration.executablePath == "/bin/zsh")
        #expect(configuration.arguments == ["zsh", "-i", "-l"])
    }

    @Test("Terminal window sizes clamp to PTY-safe values")
    func terminalWindowSizeClampsValues() {
        let minimum = terminalWindowSize(cols: 0, rows: 0)
        #expect(minimum.ws_col == 1)
        #expect(minimum.ws_row == 1)

        let maximum = terminalWindowSize(cols: Int(UInt16.max) + 100, rows: Int(UInt16.max) + 100)
        #expect(maximum.ws_col == UInt16.max)
        #expect(maximum.ws_row == UInt16.max)
    }

    @Test("Detached daemon lookup includes the current executable resource directory")
    func terminfoCandidatesIncludeCurrentExecutableResources() {
        let candidateURLs = terminalSessionCandidateResourceURLs(
            environment: [:],
            currentExecutablePath: "/tmp/Devys.app/Contents/MacOS/Devys",
            bundleResourceURLs: [],
            appBundleResourceURL: nil
        )

        #expect(
            candidateURLs.contains(
                URL(fileURLWithPath: "/tmp/Devys.app/Contents/Resources", isDirectory: true)
            )
        )
    }

    @Test("Detached daemon lookup honors the explicit app resource directory")
    func terminfoCandidatesIncludeExplicitResourceDirectory() {
        let candidateURLs = terminalSessionCandidateResourceURLs(
            environment: ["DEVYS_RESOURCE_DIR": "/tmp/Devys.app/Contents/Resources"],
            currentExecutablePath: nil,
            bundleResourceURLs: [],
            appBundleResourceURL: nil
        )

        #expect(
            candidateURLs.contains(
                URL(fileURLWithPath: "/tmp/Devys.app/Contents/Resources", isDirectory: true)
            )
        )
    }

    @Test("Daemon metadata invalidates stale executable fingerprints")
    func daemonMetadataDetectsStaleBuilds() {
        let metadata = TerminalHostDaemonMetadata(
            executablePath: "/tmp/Devys.app/Contents/MacOS/Devys",
            executableFingerprint: "old-build"
        )

        #expect(
            metadata.matches(
                executablePath: "/tmp/Devys.app/Contents/MacOS/Devys",
                executableFingerprint: "old-build"
            )
        )
        #expect(
            metadata.matches(
                executablePath: "/tmp/Devys.app/Contents/MacOS/Devys",
                executableFingerprint: "new-build"
            ) == false
        )
    }

    @Test("Attach replay budgets cap the replay payload to the explicit recent-output window")
    func attachReplayBudgetCapsReplayPayload() {
        let outputBuffer = Data((0..<128).map(UInt8.init))
        let replayBudget = TerminalHostAttachReplayBudget(recentOutputBytes: 32)

        let replayPayload = replayBudget.replayPayload(from: outputBuffer)

        #expect(replayPayload.count == 32)
        #expect(Array(replayPayload) == Array(outputBuffer.suffix(32)))
    }

    @Test("Attach replay budgets can disable replay entirely for already-primed controllers")
    func attachReplayBudgetCanDisableReplay() {
        let replayPayload = TerminalHostAttachReplayBudget.none.replayPayload(
            from: Data("terminal-output".utf8)
        )

        #expect(replayPayload.isEmpty)
    }

    @Test("Attach requests preserve the explicit replay budget through transport coding")
    func attachRequestCodingPreservesReplayBudget() throws {
        let request = TerminalHostControlRequest.attach(
            sessionID: Self.stableSessionID,
            cols: 120,
            rows: 40,
            replayBudget: TerminalHostAttachReplayBudget(recentOutputBytes: 24 * 1024)
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(TerminalHostControlRequest.self, from: encoded)

        guard case .attach(let sessionID, let cols, let rows, let replayBudget) = decoded else {
            Issue.record("Decoded request did not preserve the attach case.")
            return
        }

        #expect(sessionID == Self.stableSessionID)
        #expect(cols == 120)
        #expect(rows == 40)
        #expect(replayBudget == TerminalHostAttachReplayBudget(recentOutputBytes: 24 * 1024))
    }

    @Test("Create session requests preserve the explicit initial PTY size")
    func createSessionRequestCodingPreservesInitialSize() throws {
        let request = TerminalHostControlRequest.createSession(
            id: Self.stableSessionID,
            workspaceID: "workspace",
            workingDirectoryPath: "/tmp/workspace",
            launchCommand: nil,
            initialSize: HostedTerminalViewportSize(cols: 132, rows: 42),
            launchProfile: .fastShell,
            persistOnDisconnect: true
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(TerminalHostControlRequest.self, from: encoded)

        guard case .createSession(
            let id,
            let workspaceID,
            let workingDirectoryPath,
            let launchCommand,
            let initialSize,
            let launchProfile,
            let persistOnDisconnect
        ) = decoded else {
            Issue.record("Decoded request did not preserve the createSession case.")
            return
        }

        #expect(id == Self.stableSessionID)
        #expect(workspaceID == "workspace")
        #expect(workingDirectoryPath == "/tmp/workspace")
        #expect(launchCommand == nil)
        #expect(initialSize == HostedTerminalViewportSize(cols: 132, rows: 42))
        #expect(launchProfile == .fastShell)
        #expect(persistOnDisconnect)
    }
}
