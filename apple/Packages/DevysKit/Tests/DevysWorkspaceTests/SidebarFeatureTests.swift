import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

/// The sidebar marks and conversations as the server keeps them for one person.
private actor SidebarServer {
    var summaries: [String: ConversationSummary] = [:]
    var marks: [(key: String, mark: SidebarMark)] = []
    var paused: [(id: String, paused: Bool)] = []
    var renamed: [ProfileChange] = []
    var workItems: [WorkItem] = []
    var projects: [Project] = []

    func set(_ summary: ConversationSummary) { summaries[summary.key] = summary }
    func setWork(_ items: [WorkItem], projects: [Project]) {
        workItems = items
        self.projects = projects
    }

    func mark(_ key: ConversationKey, _ mark: SidebarMark) {
        marks.append((key.rawValue, mark))
        let current = summaries[key.rawValue] ?? ConversationSummary(key: key.rawValue, last: nil, unread: 0)
        summaries[key.rawValue] = current.with(unread: mark.unread.map { $0 ? 1 : 0 }, pinned: mark.pinned, hidden: mark.hidden)
    }

    func pause(_ id: String, _ value: Bool) { paused.append((id, value)) }
    func rename(_ change: ProfileChange) { renamed.append(change) }
}

private func said(_ key: ConversationKey, _ text: String, at seconds: Double) -> ConversationMessage {
    ConversationMessage(
        id: "\(key.rawValue)-\(seconds)",
        conversation: key.rawValue,
        author: key.kind == .direct ? "employee:\(key.ref)" : "employee:ops",
        text: text,
        createdAt: ServerDate.format(Date(timeIntervalSince1970: 1_792_400_000 + seconds))
    )
}

@MainActor
@Suite("Sidebar")
struct SidebarFeatureTests {
    private func makeStore(_ server: SidebarServer) async -> StoreOf<Workspace> {
        let store: StoreOf<Workspace> = withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                updateProfile: { _, change in await server.rename(change) },
                status: { _ in EmployeeStatus(state: RuntimeState(run: nil, inbox: [], outbox: [])) },
                stop: { _ in true },
                memory: { _ in [] },
                conversations: { _ in await server.summaries.values.sorted { $0.key < $1.key } },
                conversation: { _, _, _ in ConversationPage(messages: [], respondent: nil) },
                markSidebar: { _, key, mark in await server.mark(key, mark) },
                setPaused: { scope, value in await server.pause(scope.employeeID, value) },
                work: { _ in await server.workItems },
                projects: { _ in await server.projects },
                listedApps: { _ in [ListedApp(app: "https://mcp.ramp.com/mcp", name: "Ramp", description: "Cards", category: "Payments and finance", logo: "/ramp")] }
            )
            $0.continuousClock = InstantClock()
            $0.uuid = .incrementing
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
        await settle("team and projects") { store.chiefOfStaffScope != nil && store.projects.value != nil && store.work.value != nil }
        return store
    }

    private func settle(_ what: String, _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<20_000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for \(what)")
    }

    @Test("Pinned are tiles, the Chief of Staff first; chats go most recent first, untalked-to after; hidden rows are left out")
    func rows() async {
        let server = SidebarServer()
        await server.set(ConversationSummary(key: "direct:ops", last: said(.direct("ops"), "Morning", at: 1), unread: 0, pinned: true))
        await server.set(ConversationSummary(key: "direct:growth", last: said(.direct("growth"), "Drafted the tagline\nSecond line", at: 30), unread: 2))
        await server.set(ConversationSummary(key: "direct:engineering", last: said(.direct("engineering"), "Deployed", at: 20), unread: 0))
        await server.set(ConversationSummary(key: "direct:business-ops", last: nil, unread: 0, hidden: true))
        let store = await makeStore(server)
        await settle("summaries") { store.summaries.count == 4 }
        let layout = store.state.sidebar
        #expect(layout.pinned.map(\.title) == ["Chief of Staff"] && layout.pinned.first?.place == .home)
        #expect(layout.chats.map(\.title) == ["Growth", "Engineering"])
        #expect(layout.chats.first?.preview == "Drafted the tagline" && layout.chats.first?.unread == 2)
        #expect(layout.projects.isEmpty)
    }

    @Test("An employee not yet talked to still has a row; projects show only while active")
    func projectsOnlyWhenActive() async {
        let server = SidebarServer()
        await server.setWork(
            [
                WorkItem(id: "w1", ownerEmployeeID: "growth", title: "Write it", state: .inProgress, projectID: "p1"),
                WorkItem(id: "w2", ownerEmployeeID: "growth", title: "Ship it", state: .completed, projectID: "p2")
            ],
            projects: [Project(id: "p1", name: "Launch"), Project(id: "p2", name: "Spring"), Project(id: "p3", name: "New")]
        )
        let store = await makeStore(server)
        let layout = store.state.sidebar
        #expect(layout.chats.map(\.title) == ["Chief of Staff", "Engineering", "Growth", "Admin"], "the team's order with nothing said")
        #expect(layout.projects.map(\.title) == ["Launch", "New"], "a project whose work is all done leaves the sidebar")
        #expect(layout.projects.first?.place == .project("p1"))
    }

    @Test("Pin, Mark as Unread and Hide change the sidebar at once and post the one mark; hiding the open chat goes Home")
    func marks() async {
        let server = SidebarServer()
        await server.set(ConversationSummary(key: "direct:growth", last: said(.direct("growth"), "Hi", at: 5), unread: 0))
        let store = await makeStore(server)
        await settle("summaries") { store.summaries["direct:growth"] != nil }
        store.send(.sidebarMarked(.direct("growth"), SidebarMark(pinned: true)))
        #expect(store.state.sidebar.pinned.map(\.title) == ["Growth"])
        await settle("pinned") { await server.marks.count == 1 }
        let first = await server.marks.first
        #expect(first?.key == "direct:growth" && first?.mark == SidebarMark(pinned: true))

        store.send(.sidebarMarked(.direct("engineering"), SidebarMark(unread: true)))
        #expect(store.state.sidebar.chats.first { $0.title == "Engineering" }?.unread == 1)
        await settle("marked unread") { await server.marks.count == 2 }

        store.send(.placeSelected(.direct("growth")))
        store.send(.sidebarMarked(.direct("growth"), SidebarMark(hidden: true)))
        #expect(store.place == .home)
        #expect(!store.state.sidebar.pinned.contains { $0.title == "Growth" } && !store.state.sidebar.chats.contains { $0.title == "Growth" })
        await settle("hidden") { await server.marks.count == 3 }
        #expect(await server.marks.last?.mark == SidebarMark(hidden: true))
        await settle("summaries again") { store.summaries["direct:growth"]?.hidden == true }
    }

    @Test("Rename… saves the name alone; Pause toggles the employee")
    func renameAndPause() async {
        let server = SidebarServer()
        let store = await makeStore(server)
        store.send(.employeeRenamed("growth", " Gail "))
        #expect(store.state.employee("growth")?.name == "Gail")
        await settle("renamed") { await server.renamed.count == 1 }
        #expect(await server.renamed.first == ProfileChange(name: "Gail", responsibilities: nil))
        store.send(.pauseToggled("growth"))
        await settle("paused") { await server.paused.count == 1 }
        let paused = await server.paused.first
        #expect(paused?.id == "growth" && paused?.paused == true)
    }

    @Test("Connect apps opens with the listed apps; the button shows their logos until one is connected")
    func connectApps() async {
        let store = await makeStore(SidebarServer())
        await settle("listed") { store.listedApps.value != nil }
        #expect(store.state.connectLogos.map(\.name) == ["Ramp"])
        store.send(.connectAppsToggled(true))
        #expect(store.isConnectingApps)
        store.send(.connectAppsToggled(false))
        #expect(!store.isConnectingApps)
    }
}
