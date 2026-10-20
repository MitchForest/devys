// Shared timing helpers for every Terminal* suite. The terminal stack
// coalesces work on short (8ms) windows and streams PTY output, so
// tests never assert on a fixed sleep when the condition is observable.

import Foundation

/// Polls a condition instead of sleeping a fixed slice: the runtime's
/// 8ms coalescing windows race fixed sleeps on a loaded machine.
@MainActor
func terminalTestWait(
    attempts: Int = 200,
    until condition: @MainActor () async -> Bool
) async throws {
    for _ in 0..<attempts {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
}

/// A deliberate settle window for assertions on the *absence* of an
/// event (no PTY resize sent, no data written). Unlike terminalTestWait
/// this cannot poll - there is no positive condition to observe - so it
/// stays a fixed sleep and is named to keep that intent explicit.
func terminalTestSettle(for duration: Duration = .milliseconds(30)) async throws {
    try await Task.sleep(for: duration)
}

/// Observable byte counter for PTY stream consumers, so tests poll for
/// "output arrived" instead of sleeping a fixed slice of the stream.
actor TerminalTestByteCount {
    private(set) var value = 0

    func add(_ count: Int) {
        value += count
    }
}
