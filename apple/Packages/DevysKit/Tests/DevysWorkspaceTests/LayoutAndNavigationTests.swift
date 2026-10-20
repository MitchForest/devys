import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@Suite("Workspace layout")
struct WorkspaceLayoutTests {
    private func layout(width: CGFloat, sidebar: Bool = true, inspector: Bool = true, preferred: CGFloat = 320) -> WorkspaceLayout {
        WorkspaceLayout(width: width, sidebarWidth: 236, sidebarVisible: sidebar, inspectorVisible: inspector, preferredInspector: preferred)
    }

    @Test("Columns always add up to the available width")
    func fillsExactly() {
        for width in stride(from: 300.0, through: 2000, by: 37) {
            let columns = layout(width: width)
            let used = columns.sidebar + (columns.sidebar > 0 ? 1 : 0) + columns.page + (columns.showsHandle ? WorkspaceLayout.handle : 0) + columns.inspector
            #expect(abs(used - max(width, columns.sidebar + 1)) < 0.001, "width \(width)")
        }
    }

    @Test("The page keeps its minimum; the panel narrows, then steps aside")
    func pageWins() {
        let roomy = layout(width: 1400, preferred: 600)
        #expect(roomy.inspector == 600)
        let tight = layout(width: 236 + 1 + 420 + 9 + 300, preferred: 600)
        #expect(tight.page == WorkspaceLayout.minimumPage)
        #expect(tight.inspector == 300)
        let narrow = layout(width: 236 + 1 + 420 + 9 + 279)
        #expect(!narrow.showsInspector)
        #expect(narrow.page == CGFloat(420 + 9 + 279))
    }

    @Test("Preferred widths are clamped to the allowed range")
    func clamps() {
        #expect(layout(width: 2000, preferred: 100).inspector == 280)
        #expect(layout(width: 2000, preferred: 2000).inspector == 640)
    }
}

@MainActor
@Suite("Navigation")
struct NavigationTests {
    private func makeStore() -> StoreOf<Workspace> {
        withDependencies {
            $0.runtimeClient = .fixture
            $0.sessionClient = .unimplemented
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
    }

    @Test("Opening a DM or a teammate from Home keeps the Home sidebar")
    func homeKeepsSidebar() {
        let store = makeStore()
        store.send(.pageSelected(.direct("growth")))
        #expect(store.destination == .home)
        store.send(.pageSelected(.employee("growth")))
        #expect(store.destination == .home)
        store.send(.pageSelected(.space("space-launch")))
        #expect(store.destination == .home)
    }

    @Test("Jumping to a page the sidebar doesn't list switches to its destination")
    func paletteSwitches() {
        let store = makeStore()
        store.send(.pageSelected(.money))
        #expect(store.destination == .money)
        store.send(.pageSelected(.employee("growth")))
        #expect(store.destination == .team)
        store.send(.pageSelected(.direct("growth")))
        #expect(store.destination == .home)
    }
}
