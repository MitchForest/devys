import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@MainActor
private func settle(_ what: String, until condition: @MainActor () -> Bool) async {
    for _ in 0..<8_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for \(what)")
}

@MainActor
@Suite("Command palette")
struct PaletteFeatureTests {
    private func makeStore() async -> StoreOf<Workspace> {
        let store = withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = .fixture
            $0.continuousClock = ContinuousClock()
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
        await settle("team and projects") { store.chiefOfStaff != nil && store.projects.value != nil }
        return store
    }

    @Test("With no query: the Chief of Staff, the actions, each Settings section, then the team and projects")
    func emptyOrder() async {
        let store = await makeStore()
        let rows = store.state.paletteRows("")
        let sections = PreferencesSection.allCases.map { "Settings: \($0.rawValue)" }
        let others = store.snapshot.employees.filter { !$0.isChiefOfStaff }.map(\.name)
        let projects = (store.projects.value ?? []).map(\.name)
        #expect(rows.map(\.title) == ["Chief of Staff", "New employee", "New project", "Connect apps", "Keyboard shortcuts"] + sections + others + projects)
        #expect(rows.first?.icon == .employee("ops"))
        #expect(rows.first?.detail == "Coordinates launch work and brings you decisions")
        #expect(rows.first?.command == .place(.home))
        #expect(rows.filter { $0.title.hasPrefix("Settings: ") }.allSatisfy { $0.detail == "Settings" })
        #expect(rows.contains { $0.command == .place(.project("launch")) })
        // Threads and pages only show once something is typed.
        #expect(!rows.contains { $0.detail == "Thread" || $0.detail == "Page" })
    }

    @Test("Typing filters titles and second lines")
    func filters() async {
        let store = await makeStore()
        #expect(store.state.paletteRows("grow").map(\.title) == ["Growth"])
        #expect(store.state.paletteRows("voice").map(\.title) == ["Settings: Voice"])
        #expect(store.state.paletteRows("  NEW ").map(\.title) == ["New employee", "New project"])
        #expect(store.state.paletteRows("settings").count == PreferencesSection.allCases.count)
        #expect(store.state.paletteRows("zzzz").isEmpty)
    }

    @Test("The first nine rows carry ⌘1…⌘9: each is the row at that index")
    func numberKeys() async {
        let store = await makeStore()
        let rows = store.state.paletteRows("")
        #expect(rows.count > 9)
        #expect(Array(rows.prefix(9)).map(\.id) == ["dm-ops", "new-employee", "new-project", "connect-apps", "shortcuts"] + PreferencesSection.allCases.prefix(4).map { "settings-\($0.rawValue)" })
    }

    @Test("A Settings row opens Settings at its section and closes the palette")
    func settingsRow() async {
        let store = await makeStore()
        for section in PreferencesSection.allCases {
            store.send(.paletteToggled(true))
            guard let row = store.state.paletteRows("").first(where: { $0.command == .settings(section) }) else {
                Issue.record("no row for \(section)")
                continue
            }
            store.send(.paletteRan(row.command))
            #expect(!store.isPaletteOpen)
            #expect(store.preferences?.section == section)
            #expect(store.preferences?.selectedBusinessID == "acme")
            store.send(.preferencesToggled(false))
        }
    }

    @Test("Action rows run what they say and close the palette")
    func actionRows() async {
        let store = await makeStore()
        store.send(.paletteToggled(true))
        store.send(.paletteRan(.newProject))
        #expect(!store.isPaletteOpen && store.newProject != nil)
        store.send(.newProjectDismissed)

        store.send(.paletteToggled(true))
        store.send(.paletteRan(.newEmployee))
        #expect(!store.isPaletteOpen && store.team.hiring != nil)
        store.send(.hireCancelled)

        store.send(.paletteToggled(true))
        store.send(.paletteRan(.shortcuts))
        #expect(!store.isPaletteOpen && store.isShowingShortcuts)
        store.send(.shortcutsToggled(false))
        #expect(!store.isShowingShortcuts)

        store.send(.paletteToggled(true))
        store.send(.paletteRan(.place(.direct("growth"))))
        #expect(!store.isPaletteOpen && store.place == .direct("growth"))
        store.send(.paletteRan(.place(.home)))
        #expect(store.place == .home)
        #expect(!KeyboardShortcutList.entries.isEmpty)
    }

    @Test("Connect apps opens from the palette; the backdrop's close closes it")
    func connectApps() async {
        let store = await makeStore()
        store.send(.paletteToggled(true))
        store.send(.paletteRan(.connectApps))
        #expect(!store.isPaletteOpen && store.isConnectingApps)
        // What the backdrop (and Esc) send.
        store.send(.connectAppsToggled(false))
        #expect(!store.isConnectingApps)
    }

    @Test("The sidebar has no search or + buttons: search is ⌘K and the title bar, New the menu bar")
    func noSidebarButtons() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/DevysWorkspace/Shell/Sidebar.swift").standardized
        let source = try String(contentsOf: file, encoding: .utf8)
        #expect(!source.contains("\"magnifyingglass\""))
        #expect(!source.contains("\"plus\""))
        #expect(!source.contains("paletteToggled"))
        #expect(!source.contains("NewMenu"))
    }
}
