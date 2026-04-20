import Testing
@testable import GhosttyTerminal

@Suite("Ghostty Terminal Surface Tests")
struct GhosttyTerminalSurfaceTests {
    @Test("Default appearance matches the canonical dark terminal tokens")
    func defaultAppearance() {
        #expect(GhosttyTerminalAppearance.defaultDark.background.packedRGB == 0x282C34)
        #expect(GhosttyTerminalAppearance.defaultDark.foreground.packedRGB == 0xFFFFFF)
        #expect(GhosttyTerminalAppearance.defaultDark.cursorColor == GhosttyTerminalAppearance.defaultDark.foreground)
        #expect(GhosttyTerminalAppearance.defaultDark.selectionBackground.packedRGB == 0x3F638B)
        #expect(GhosttyTerminalAppearance.defaultDark.palette == GhosttyTerminalAppearance.ghosttyDarkPalette)
    }

    @Test("Session focus requests advance monotonically")
    @MainActor
    func sessionFocusRequestsIncrement() {
        let session = GhosttyTerminalSession()
        #expect(session.focusRequestID == 0)

        session.requestKeyboardFocus()
        #expect(session.focusRequestID == 1)

        session.requestKeyboardFocus()
        #expect(session.focusRequestID == 2)
    }

    @Test("Staged commands preserve execution newlines")
    @MainActor
    func stagedCommandsPreserveExecutionNewlines() {
        let session = GhosttyTerminalSession(stagedCommand: "claude --dangerously-skip-permissions\n")
        #expect(session.stagedCommand == "claude --dangerously-skip-permissions\n")
    }
}
