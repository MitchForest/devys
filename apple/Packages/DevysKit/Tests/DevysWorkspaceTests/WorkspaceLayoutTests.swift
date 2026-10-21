import Foundation
import Testing
@testable import DevysWorkspace

/// The same cases as the web's "workspace columns, as native WorkspaceLayout".
@Suite("Workspace layout")
struct WorkspaceLayoutTests {
    private func layout(_ width: CGFloat, sidebar: Bool = true, panel: Bool = true, wide: Bool = false, preferred: CGFloat = 440) -> WorkspaceLayout {
        WorkspaceLayout(width: width, sidebarWidth: 236, sidebarVisible: sidebar, panelOpen: panel, wide: wide, preferredPanel: preferred)
    }

    @Test("The conversation keeps its minimum and the right panel is clamped to its range")
    func clamps() {
        let roomy = layout(1300)
        #expect(roomy.sidebar == 236 && roomy.conversation == 614 && roomy.panel == 440 && !roomy.overlay && roomy.showsHandle)
        #expect(layout(1300, preferred: 900).panel == 634)
        let closed = layout(1300, panel: false)
        #expect(closed.conversation == 1063 && closed.panel == 0 && !closed.showsHandle)
        #expect(layout(2000, preferred: 100).panel == 360)
        #expect(layout(2000, preferred: 2000).panel == 720)
    }

    @Test("Widened, the panel takes all but the conversation's minimum; too narrow, it lies over the conversation")
    func widensAndOverlays() {
        let wide = layout(1300, wide: true)
        #expect(wide.sidebar == 236 && wide.conversation == 420 && wide.panel == 634 && !wide.overlay && !wide.showsHandle)
        let narrow = layout(900)
        #expect(narrow.sidebar == 236 && narrow.conversation == 663 && narrow.panel == 440 && narrow.overlay && !narrow.showsHandle)
    }

    @Test("Side by side, columns always add up to the available width")
    func fillsExactly() {
        for width in stride(from: 300.0, through: 2000, by: 37) {
            let columns = layout(width)
            guard !columns.overlay else { continue }
            let used = columns.sidebar + 1 + columns.conversation + WorkspaceLayout.handle + columns.panel
            #expect(abs(used - width) < 0.001, "width \(width)")
            #expect(columns.conversation >= WorkspaceLayout.minimumConversation)
        }
    }
}
