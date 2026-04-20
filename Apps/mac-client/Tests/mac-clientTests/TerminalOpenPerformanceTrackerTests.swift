import Testing
@testable import mac_client

@Suite("Terminal Open Performance Tracker Tests")
struct TerminalOpenPerformanceTrackerTests {
    @Test("Tracker emits each checkpoint once")
    func checkpointDeduplication() {
        var tracker = TerminalOpenPerformanceTracker()

        let first = tracker.record(.openRequest, context: ["source": "shell"])
        let second = tracker.record(.openRequest, context: ["source": "shell"])
        let third = tracker.record(.tabVisible)

        #expect(
            first == [
                .checkpoint(
                    name: "open_request",
                    context: ["source": "shell"]
                )
            ]
        )
        #expect(second.isEmpty)
        #expect(
            third == [
                .checkpoint(
                    name: "tab_visible",
                    context: [:]
                )
            ]
        )
    }

    @Test("Finish is emitted once and suppresses later checkpoints")
    func finishStopsFurtherEvents() {
        var tracker = TerminalOpenPerformanceTracker()

        let first = tracker.finish(
            outcome: "interactive",
            context: ["launch_profile": "compatibility_shell"]
        )
        let second = tracker.finish(outcome: "duplicate")
        let third = tracker.record(.firstInteractiveFrame)

        #expect(
            first == [
                .finish(
                    outcome: "interactive",
                    context: ["launch_profile": "compatibility_shell"]
                )
            ]
        )
        #expect(second.isEmpty)
        #expect(third.isEmpty)
    }
}
