import Foundation
import Testing
import TerminalHost

@Suite("TerminalForegroundProcess Tests", .serialized)
struct TerminalForegroundProcessTests {
    @Test("Probe resolves the foreground process for a live PTY child")
    func resolvesForegroundProcess() async throws {
        #if os(macOS)
        // `cat` with no arguments blocks on stdin forever, which makes it a stable
        // foreground process to inspect without races against an `exec` from a wrapper
        // shell.
        let client = TerminalHostClient()
        let handle = try await client.create(
            profile: TerminalLaunchProfile(
                executablePath: "/bin/cat",
                arguments: ["cat"]
            )
        )
        _ = try await client.attach(handle)

        let process = try await pollForForegroundProcess(
            client: client,
            handle: handle,
            expectedName: "cat"
        )
        #expect(process.pid > 0)
        #expect(process.executableName == "cat")
        #expect(process.executablePath.hasSuffix("/cat"))

        await client.terminate(handle)
        #else
        #expect(true)
        #endif
    }

    @Test("Probe returns nil for unknown session handles")
    func returnsNilForUnknownHandle() async {
        #if os(macOS)
        let client = TerminalHostClient()
        let unknown = TerminalSessionHandle(id: UUID())

        let process = await client.foregroundProcess(unknown)

        #expect(process == nil)
        #else
        #expect(true)
        #endif
    }
}

#if os(macOS)
private enum TerminalForegroundProcessTestError: Error {
    case timedOutWaitingForForegroundProcess
}

/// Polls `foregroundProcess` until it resolves to a process matching `expectedName` or
/// the timeout fires. There is a brief window between `forkpty` returning in the child
/// and `execv` replacing the process image where the probe will resolve to whichever
/// runtime spawned the test (e.g., `swiftpm-testing-helper`); we ignore those readings
/// and wait for the real exec to land.
private func pollForForegroundProcess(
    client: TerminalHostClient,
    handle: TerminalSessionHandle,
    expectedName: String,
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(50)
) async throws -> TerminalForegroundProcess {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < timeout {
        if let process = await client.foregroundProcess(handle),
           process.executableName == expectedName {
            return process
        }
        try await Task.sleep(for: interval)
    }
    throw TerminalForegroundProcessTestError.timedOutWaitingForForegroundProcess
}
#endif
