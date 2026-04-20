import Testing
@testable import mac_client

@Suite("Terminal Host Warmup State Tests")
struct TerminalHostWarmupStateTests {
    @Test("Warmup is requested once per lifecycle")
    func beginIfNeeded() {
        var state = TerminalHostWarmupState()
        let first = state.beginIfNeeded()
        let second = state.beginIfNeeded()

        #expect(first)
        #expect(second == false)
        #expect(state.hasRequestedWarmup)
    }
}
