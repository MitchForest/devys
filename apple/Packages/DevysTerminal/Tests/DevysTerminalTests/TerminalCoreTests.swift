import Foundation
import TerminalCore
import Testing

/// Platform-neutral TerminalCore models: viewport clamping, launch
/// descriptors and their shell policy, text queries, and snapshots.
@Suite
struct TerminalCoreTests {
    @Test
    func viewportClampsToPositiveDimensions() {
        let size = TerminalViewportSize(cols: 0, rows: -4)

        #expect(size.cols == 1)
        #expect(size.rows == 1)
    }

    @Test
    func userShellUsesAbsoluteShellOrZshFallback() {
        let descriptor = TerminalLaunchDescriptor.userShell(
            workingDirectoryPath: "/tmp",
            environment: ["SHELL": "/bin/bash"]
        )

        #expect(descriptor.executablePath == "/bin/bash")
        #expect(descriptor.arguments == ["bash", "-i", "-l"])
        #expect(descriptor.workingDirectoryPath == "/tmp")
    }

    @Test
    func explicitCommandDescriptorHasNoAppDomainPolicy() {
        let descriptor = TerminalLaunchDescriptor.explicitCommand(
            executablePath: "/usr/bin/swift",
            arguments: ["swift", "test"],
            workingDirectoryPath: "/tmp/devys",
            environment: ["CUSTOM": "1"]
        )

        #expect(descriptor.executablePath == "/usr/bin/swift")
        #expect(descriptor.arguments == ["swift", "test"])
        #expect(descriptor.workingDirectoryPath == "/tmp/devys")
        #expect(descriptor.environment == ["CUSTOM": "1"])
    }

    @Test
    func textQueryClampsRowLimitAndKeepsRawText() {
        let query = TerminalTextQuery(text: "  hello  ", searchLimitRows: 0)

        #expect(query.text == "  hello  ")
        #expect(query.searchLimitRows == 1)
    }

    @Test
    func textRangeLookupResultModelsUnavailableReason() {
        let result = TerminalTextRangeLookupResult.unavailable(.alternateScreen)

        #expect(result == .unavailable(.alternateScreen))
        #expect(TerminalTextRangeUnavailableReason.alternateScreen.rawValue == "alternateScreen")
    }

    @Test
    func runtimeSnapshotCarriesNeutralTerminalFacts() {
        let snapshot = TerminalSnapshot(
            terminalID: TerminalID("terminal-1"),
            currentDirectoryPath: "/tmp/devys",
            title: "devys",
            shellProcessID: 10,
            foregroundProcess: TerminalProcessIdentity(
                processID: 12,
                parentProcessID: 10,
                executablePath: "/usr/bin/swift",
                executableName: "swift",
                arguments: ["swift", "test"]
            ),
            processTree: [
                TerminalProcessIdentity(processID: 10, executableName: "zsh"),
                TerminalProcessIdentity(processID: 12, parentProcessID: 10, executableName: "swift")
            ],
            listeningPorts: [
                TerminalListeningPort(port: 3000, address: "127.0.0.1", processID: 12)
            ],
            activity: .output,
            timestamp: Date(timeIntervalSince1970: 1)
        )

        #expect(snapshot.terminalID == TerminalID("terminal-1"))
        #expect(snapshot.currentDirectoryPath == "/tmp/devys")
        #expect(snapshot.foregroundProcess?.executableName == "swift")
        #expect(snapshot.listeningPorts.map(\.port) == [3000])
        #expect(snapshot.activity == .output)
    }
}
