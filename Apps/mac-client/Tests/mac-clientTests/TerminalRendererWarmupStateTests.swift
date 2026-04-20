import Testing
@testable import mac_client

@Suite("Terminal Renderer Warmup State Tests")
struct TerminalRendererWarmupStateTests {
    @Test("Renderer warmup is requested once per lifecycle")
    func beginIfNeeded() {
        var state = TerminalRendererWarmupState()
        let first = state.beginIfNeeded()
        let second = state.beginIfNeeded()

        #expect(first)
        #expect(second == false)
        #expect(state.hasRequestedWarmup)
    }
}
