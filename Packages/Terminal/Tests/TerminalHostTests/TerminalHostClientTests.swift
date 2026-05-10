import Foundation
import Testing
import TerminalHost

@Suite("TerminalHostClient Tests", .serialized)
struct TerminalHostClientTests {
    @Test("Attach replays process output")
    func attachReplaysProcessOutput() async throws {
        #if os(macOS)
        let client = TerminalHostClient()
        let handle = try await client.create(
            profile: interactiveEchoProfile()
        )
        let events = try await client.attach(handle)
        _ = try await output(containing: "terminal-host-child-ready", from: events)
        try await client.sendText("terminal-host-ready\n", to: handle)
        let output = try await output(containing: "terminal-host-ready", from: events)
        #expect(output.contains("terminal-host-ready"))
        await client.terminate(handle)
        #else
        #expect(true)
        #endif
    }

    @Test("Session create, send, paste, resize, and terminate")
    func localPTYLifecycle() async throws {
        #if os(macOS)
        let client = TerminalHostClient()
        let handle = try await client.create(
            profile: interactiveEchoProfile(),
            size: TerminalHostSize(cols: 24, rows: 4)
        )
        let events = try await client.attach(handle)
        _ = try await output(containing: "terminal-host-child-ready", from: events)
        try await client.resize(handle, cols: 32, rows: 8)
        try await client.sendText("hello\n", to: handle)
        try await client.pasteText("world\n", to: handle)
        await client.terminate(handle)
        #else
        #expect(true)
        #endif
    }
}

#if os(macOS)
private enum TerminalHostTestError: Error {
    case timedOutWaitingForOutput(String)
}

private func interactiveEchoProfile() -> TerminalLaunchProfile {
    TerminalLaunchProfile(
        executablePath: "/bin/sh",
        arguments: ["sh", "-c", "printf 'terminal-host-child-ready\\n'; exec /bin/cat"]
    )
}

private func output(
    containing needle: String,
    from events: AsyncStream<TerminalHostEvent>,
    timeout: Duration = .seconds(2)
) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
            var iterator = events.makeAsyncIterator()
            var transcript = ""
            while !transcript.contains(needle) {
                guard let event = await iterator.next() else {
                    throw TerminalHostTestError.timedOutWaitingForOutput(needle)
                }
                if case .output(let data) = event {
                    transcript += String(decoding: data, as: UTF8.self)
                }
            }
            return transcript
        }

        group.addTask {
            try await Task.sleep(for: timeout)
            throw TerminalHostTestError.timedOutWaitingForOutput(needle)
        }

        let output = try await group.next() ?? ""
        group.cancelAll()
        return output
    }
}
#endif
