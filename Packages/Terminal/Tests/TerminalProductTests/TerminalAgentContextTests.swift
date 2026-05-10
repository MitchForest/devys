import TerminalComposer
import TerminalHost
@testable import TerminalProduct
import XCTest

@MainActor
final class TerminalAgentContextTests: XCTestCase {
    func testStartsWithoutAgentContext() {
        let model = TerminalProductModel(agentRegistry: .default)

        XCTAssertNil(model.agentContext.match)
        XCTAssertEqual(model.composerSerializationStyle, .shell)
        XCTAssertNil(model.windowAgentStatus)
    }

    func testFocusComposerFocusesInputWithoutPresentationState() {
        let model = TerminalProductModel(agentRegistry: .default)

        model.focusComposer()

        XCTAssertTrue(model.composer.isFocused)
        XCTAssertEqual(model.composer.activeTargetID, model.terminalTargetID)
    }

    func testTerminalFocusLeavesComposerDraftVisibleButUnfocused() {
        let model = TerminalProductModel(agentRegistry: .default)
        model.focusComposer()
        model.composer.updateActiveDraft("status")

        model.focusTerminal()

        XCTAssertFalse(model.composer.isFocused)
        XCTAssertEqual(model.composer.activeDraft, "status")
        XCTAssertEqual(model.focusRequestID, 1)
    }

    func testAgentDetectionUpdatesContextAndSerialization() {
        let model = TerminalProductModel(agentRegistry: .default)

        model.applyForegroundProcess(claudeProcess())

        XCTAssertEqual(model.agentContext.match?.displayName, "Claude Code")
        XCTAssertEqual(model.agentContext.activity, .waiting)
        XCTAssertEqual(model.composerSerializationStyle, .claudeCode)
        XCTAssertEqual(model.windowAgentStatus?.agentName, "Claude Code")
        XCTAssertEqual(model.windowAgentStatus?.activity, .waiting)
        XCTAssertFalse(model.composer.isFocused, "Agent detection does not steal focus")
    }

    func testAgentLeavingClearsContext() {
        let model = TerminalProductModel(agentRegistry: .default)
        model.applyForegroundProcess(claudeProcess())

        model.applyForegroundProcess(shellProcess())

        XCTAssertNil(model.agentContext.match)
        XCTAssertEqual(model.agentContext.activity, .waiting)
        XCTAssertEqual(model.composerSerializationStyle, .shell)
        XCTAssertNil(model.windowAgentStatus)
    }

    func testAgentSwitchUpdatesMatchInPlace() {
        let model = TerminalProductModel(agentRegistry: .default)
        model.applyForegroundProcess(claudeProcess())

        model.applyForegroundProcess(codexProcess())

        XCTAssertEqual(model.agentContext.match?.displayName, "Codex")
        XCTAssertEqual(model.agentContext.activity, .waiting)
        XCTAssertEqual(model.composerSerializationStyle, .codex)
    }

    func testAgentOutputMarksWorkingThenQuietReturnsToWaiting() {
        let model = TerminalProductModel(agentRegistry: .default)
        let start = Date(timeIntervalSinceReferenceDate: 100)
        model.applyForegroundProcess(codexProcess())

        model.noteAgentOutput(at: start)
        XCTAssertEqual(model.agentContext.activity, .working)

        model.refreshAgentActivity(now: start.addingTimeInterval(model.agentWorkingQuietInterval + 0.1))
        XCTAssertEqual(model.agentContext.activity, .waiting)
    }

    func testMarkTerminalExitedMarksAgentExitedAndStopsProbe() {
        let model = TerminalProductModel(agentRegistry: .default)
        model.applyForegroundProcess(claudeProcess())

        model.markTerminalExited()

        XCTAssertEqual(model.agentContext.match?.displayName, "Claude Code")
        XCTAssertEqual(model.agentContext.activity, .exited)
        XCTAssertNil(model.foregroundProbeTask)
    }

    func testCustomRegistryDoesNotMatchDefaultAgents() {
        let custom = TerminalAgentRegistry(entries: [])
        let model = TerminalProductModel(agentRegistry: custom)

        model.applyForegroundProcess(claudeProcess())

        XCTAssertNil(model.agentContext.match)
        XCTAssertEqual(model.composerSerializationStyle, .shell)
        XCTAssertNil(model.windowAgentStatus)
    }

    private func claudeProcess() -> TerminalForegroundProcess {
        TerminalForegroundProcess(pid: 100, executableName: "claude", executablePath: "/usr/local/bin/claude")
    }

    private func codexProcess() -> TerminalForegroundProcess {
        TerminalForegroundProcess(pid: 101, executableName: "codex", executablePath: "/usr/local/bin/codex")
    }

    private func shellProcess() -> TerminalForegroundProcess {
        TerminalForegroundProcess(pid: 102, executableName: "zsh", executablePath: "/bin/zsh")
    }
}
