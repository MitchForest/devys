import Testing
@testable import TerminalVT

#if os(macOS)
import AppKit

@Suite("Ghostty Terminal Host View Tests")
@MainActor
struct GhosttyTerminalHostViewTests {
    @Test("Host view uses top-left coordinates to match terminal rendering")
    func hostViewIsFlipped() {
        let view = GhosttyTerminalHostView()

        #expect(view.isFlipped)
    }

    @Test("Host view hit testing uses AppKit-provided local coordinates")
    func hitTestUsesLocalCoordinates() {
        let view = GhosttyTerminalHostView()
        view.frame = NSRect(x: 50, y: 100, width: 200, height: 80)

        #expect(view.hitTest(NSPoint(x: 10, y: 10)) === view)
        #expect(view.hitTest(NSPoint(x: 250, y: 10)) == nil)
    }

    @Test("Host view reserves Ghostty-style terminal content padding")
    func hostViewReservesTerminalContentPadding() {
        let view = GhosttyTerminalHostView()
        view.frame = NSRect(x: 0, y: 0, width: 100, height: 50)
        view.layoutSubtreeIfNeeded()

        #expect(GhosttyTerminalHostView.terminalContentPadding == 2)
        #expect(view.terminalContentRect == CGRect(x: 2, y: 2, width: 96, height: 46))
        #expect(view.metalView.frame == view.terminalContentRect)
        #expect(view.terminalContentPoint(from: CGPoint(x: 2, y: 2)) == .zero)
    }
}
#endif
