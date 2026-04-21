import Foundation
import GhosttyTerminal
import Testing
@testable import mac_client

@Suite("Hosted Local Terminal Controller Tests")
struct HostedLocalTerminalControllerTests {
    @Test("Output bursts stay buffered until the flush window drains")
    @MainActor
    func outputBurstsAreBufferedBeforeApplyingVTUpdates() async {
        let controller = makeController(outputBurstWindow: .seconds(1))

        await controller.handleOutput(Data("cod".utf8))
        await controller.handleOutput(Data("ex".utf8))

        #expect(controller.pendingOutput == Data("codex".utf8))
        #expect(controller.outputFlushTask != nil)
        #expect(controller.frameProjection.rowsByIndex.isEmpty)

        await controller.flushPendingOutputIfNeeded()

        #expect(controller.pendingOutput.isEmpty)
        #expect(controller.outputFlushTask == nil)
        #expect(controller.frameProjection.row(at: 0)?.cells.prefix(5).map(\.grapheme).joined() == "codex")
        #expect(controller.frameProjection.rowsByIndex.isEmpty == false)
    }
}

@MainActor
private func makeController(
    outputBurstWindow: Duration
) -> HostedLocalTerminalController {
    let session = GhosttyTerminalSession(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-FFFFFFFFFFFF") ?? UUID(),
        startupPhase: .startingShell
    )
    let controller = HostedLocalTerminalController(
        session: session,
        socketPath: "/tmp/devys-terminal-test.sock",
        appearance: .defaultDark,
        preferredViewportSize: HostedTerminalViewportSize(cols: 80, rows: 24),
        outputBurstWindow: outputBurstWindow
    )
    controller.updateViewport(cols: 80, rows: 24, cellWidthPx: 8, cellHeightPx: 16)
    return controller
}
