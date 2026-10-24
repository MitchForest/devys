import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

/// A business with one project, its work and conversations, as the server keeps them.
private actor PlacesServer {
    var messages: [String: [ConversationMessage]] = [:]
    var workItems = [WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Fix sitemap", state: .inProgress, projectID: "p1")]
    var projects = [Project(id: "p1", name: "Launch", leadEmployeeID: "ops")]
    var artifacts: [Artifact] = []
    var home = Home()
    var newItems: [NewWorkItem] = []
    var created: [ProjectChange] = []
    var posts: [NewMessage] = []
    private var count = 0

    @discardableResult
    func add(_ key: ConversationKey, _ author: String, _ text: String, kind: ConversationMessage.Kind = .message, ref: Ref? = nil, mentions: [String] = []) -> ConversationMessage {
        count += 1
        let message = ConversationMessage(
            id: "m\(count)",
            conversation: key.rawValue,
            author: author,
            kind: kind,
            text: text,
            mentions: mentions,
            ref: ref,
            createdAt: ServerDate.format(Date(timeIntervalSince1970: 1_792_400_000 + Double(count)))
        )
        messages[key.rawValue, default: []].append(message)
        return message
    }

    /// An employee publishes a page: the file, and its card in the conversation.
    func publish(_ id: String, _ filename: String, by employee: String, in key: ConversationKey) {
        artifacts.append(Artifact(id: id, filename: filename, contentType: "text/html", byteLength: 10, createdAt: "2026-10-20T10:00:0\(artifacts.count).000Z"))
        add(key, "employee:\(employee)", filename, kind: .event, ref: .artifact(id))
    }

    func setHome(_ value: Home) { home = value }

    func page(_ key: ConversationKey) -> ConversationPage {
        let messages = messages[key.rawValue] ?? []
        let fallback: String? = switch key.kind {
        case .direct: key.ref
        case .project: projects.first { $0.id == key.ref }?.leadEmployeeID
        case .work: workItems.first { $0.id == key.ref }?.ownerEmployeeID
        }
        return ConversationPage(messages: messages, respondent: messages.last { $0.employeeID != nil && !$0.isEvent }?.employeeID ?? fallback)
    }

    func post(_ key: ConversationKey, _ message: NewMessage) -> PostedMessage {
        posts.append(message)
        return PostedMessage(message: add(key, "person:person-preview", message.text), recipients: [])
    }

    func create(_ newItem: NewWorkItem) -> WorkItem {
        newItems.append(newItem)
        let item = WorkItem(id: "c\(workItems.count + 1)", ownerEmployeeID: newItem.owner, title: newItem.title, projectID: newItem.projectID)
        workItems.append(item)
        return item
    }

    func createProject(_ change: ProjectChange) -> Project {
        created.append(change)
        let project = Project(id: "p\(projects.count + 1)", name: change.name, goal: change.goal, leadEmployeeID: change.lead ?? "ops", memberIDs: change.members)
        projects.append(project)
        return project
    }

    func detail(_ id: String) -> BusinessDetail {
        let base = BusinessDetail.fixture(id)
        return BusinessDetail(business: base.business, employees: base.employees, artifacts: artifacts)
    }
}

@MainActor
@Suite("Places, layers and the right panel")
struct PlacesFeatureTests {
    private func makeStore(_ server: PlacesServer) async -> StoreOf<Workspace> {
        let store: StoreOf<Workspace> = withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { await server.detail($0) },
                status: { _ in EmployeeStatus(state: RuntimeState(run: nil, inbox: [], outbox: [])) },
                stop: { _ in true },
                memory: { _ in [] },
                conversation: { _, key, _ in await server.page(key) },
                postMessage: { _, key, message in await server.post(key, message) },
                work: { _ in await server.workItems },
                createWorkItem: { _, newItem in await server.create(newItem) },
                projects: { _ in await server.projects },
                createProject: { _, change in await server.createProject(change) },
                home: { _ in await server.home }
            )
            $0.continuousClock = InstantClock()
            $0.uuid = .incrementing
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
        await settle("team, work and projects") { store.chiefOfStaffScope != nil && store.projects.value != nil && store.work.value != nil }
        return store
    }

    private func settle(_ what: String, _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<20_000 {
            if await condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for \(what)")
    }

    private func open(_ place: Place, in store: StoreOf<Workspace>) async {
        store.send(.placeSelected(place))
        await settle("conversation") { store.main?.key == store.state.mainKey && store.main?.messages.value != nil }
    }

    @Test("Home is the direct chat with the Chief of Staff; work opens beside any conversation, with its own conversation open there")
    func placesAndWork() async {
        let store = await makeStore(PlacesServer())
        await settle("Home's conversation") { store.main?.key == .direct("ops") }
        #expect(store.place == .home)
        store.send(.placeSelected(.project("p1")))
        #expect(store.main?.key == .project("p1"))
        store.send(.workOpened("c1"))
        store.send(.workOpened("c1"))
        #expect(store.place == .project("p1") && store.layers.map(\.layer) == [.work("c1")])
        #expect(store.main?.key == .project("p1") && store.aside?.key == .work("c1"))
        // A page over the work keeps the work's conversation open; closing the panel lets it go.
        store.send(.layerOpened(.artifact("a1")))
        #expect(store.aside?.key == .work("c1"))
        store.send(.layersClosed)
        #expect(store.aside == nil)
        // The sidebar closes the work as it moves.
        store.send(.workOpened("c1"))
        store.send(.placeSelected(.direct("growth")))
        #expect(store.layers.isEmpty && store.aside == nil && store.main?.key == .direct("growth"))
    }

    @Test("Layers stack in the right panel: ‹ goes back one, × closes them all, a new place closes them")
    func layerStack() async {
        let store = await makeStore(PlacesServer())
        store.send(.placeSelected(.project("p1")))
        store.send(.layerOpened(.artifact("a1")))
        store.send(.layerOpened(.file("/acme/plan.md")))
        store.send(.layerOpened(.file("/acme/plan.md")))
        #expect(store.layers.map(\.layer) == [.artifact("a1"), .file("/acme/plan.md")])
        store.send(.layerReplaced(.file("/acme/brief.md")))
        #expect(store.layers.map(\.layer) == [.artifact("a1"), .file("/acme/brief.md")])
        store.send(.layerPopped)
        #expect(store.state.topLayer == .artifact("a1"))
        store.send(.wideToggled)
        #expect(store.state.isWideShown)
        store.send(.layersClosed)
        #expect(store.layers.isEmpty && !store.isWide && !store.state.isWideShown)
        store.send(.browserOpened("c1"))
        store.send(.layerPopped)
        #expect(store.layers.map(\.layer) == [.work("c1")], "closing the browser returns to the work")
        store.send(.layersClosed)
        // The panel is there only for layers.
        store.send(.layerOpened(.session(workID: "c1", sessionID: "s1")))
        #expect(store.state.isPanelOpen)
        store.send(.layersClosed)
        #expect(store.layers.isEmpty && !store.state.isPanelOpen)
    }

    @Test("A page that arrives in the conversation on screen opens on its own; its next version replaces it and says who")
    func pageArrives() async {
        let server = PlacesServer()
        // A page already in the conversation when it opens stays a card.
        await server.publish("a0", "old.html", by: "growth", in: .direct("growth"))
        let store = await makeStore(server)
        await open(.direct("growth"), in: store)
        #expect(store.layers.isEmpty)
        await server.publish("a1", "launch-plan.html", by: "growth", in: .direct("growth"))
        await settle("the page opened") { store.state.topLayer == .artifact("a1") }
        #expect(store.layers.first?.auto == true)
        await settle("the detail has it") { store.artifacts.contains { $0.id == "a1" } }
        await server.publish("a2", "launch-plan.html", by: "growth", in: .direct("growth"))
        await settle("the new version") { store.state.topLayer == .artifact("a2", updatedBy: "Growth") }
        #expect(store.layers.count == 1)
        // Once the owner opens a layer themselves, a new page arrives as a card only.
        store.send(.layerOpened(.file("/acme/plan.md")))
        await server.publish("a3", "pricing.html", by: "growth", in: .direct("growth"))
        await settle("the card arrived") { store.main?.messages.value?.last?.ref == .artifact("a3") }
        #expect(store.state.topLayer == .file("/acme/plan.md"))
    }

    @Test("What's on screen goes with the next message as its ref, until the owner removes it")
    func reference() async {
        let server = PlacesServer()
        let store = await makeStore(server)
        await open(.direct("growth"), in: store)
        let key = ConversationKey.direct("growth")
        store.send(.layerOpened(.file("/acme/launch plan.md")))
        #expect(store.state.reference == LayerReference(title: "launch plan.md", ref: .file("/acme/launch plan.md")))
        store.send(.draftChanged(key, "  Shorter, please  "))
        store.send(.sendTapped(key))
        await settle("posted") { await server.posts.count == 1 }
        // As the web sends it: the words as written, and the record as the message's ref.
        #expect(await server.posts.last?.text == "Shorter, please")
        #expect(await server.posts.last?.ref == .file("/acme/launch plan.md"))
        #expect(store.state.reference == nil)
        store.send(.layerOpened(.session(workID: "c1", sessionID: "s1")))
        #expect(store.state.reference?.ref == .codeSession("s1"))
        store.send(.referencingSet(false))
        store.send(.draftChanged(key, "Thanks"))
        store.send(.sendTapped(key))
        await settle("posted again") { await server.posts.count == 2 }
        #expect(await server.posts.last?.text == "Thanks")
        #expect(await server.posts.last?.ref == nil)
        // The browser is not a record: nothing goes with the message.
        store.send(.layerOpened(.browser(workID: "c1")))
        store.send(.referencingSet(true))
        store.send(.draftChanged(key, "Look"))
        store.send(.sendTapped(key))
        await settle("posted a third time") { await server.posts.count == 3 }
        #expect(await server.posts.last?.text == "Look")
        #expect(await server.posts.last?.ref == nil)
        store.send(.askTapped("line one\nline two"))
        #expect(store.main?.draft == "> line one\n> line two\n\n")
    }

    @Test("Make it work: owned by whoever the message addressed, in the project it was said in, and it opens beside the channel")
    func makeWork() async {
        let server = PlacesServer()
        let fromGrowth = await server.add(.project("p1"), "employee:growth", "The sitemap drops /blog.\n\nNeeds a fix.")
        let mentioning = await server.add(.project("p1"), "person:person-preview", "@Engineering can you check deploys?", mentions: ["engineering"])
        let plain = await server.add(.project("p1"), "person:person-preview", "Decide pricing", ref: .artifact("a1"))
        let store = await makeStore(server)
        await open(.project("p1"), in: store)

        store.send(.makeWorkTapped(fromGrowth.id))
        await settle("work from an employee's message") { store.state.topLayer == .work("c2") }
        #expect(store.place == .project("p1") && store.main?.key == .project("p1"))
        #expect(await server.newItems.last == NewWorkItem(title: "The sitemap drops /blog.", owner: "growth", objective: "The sitemap drops /blog.\n\nNeeds a fix.", projectID: "p1"))

        store.send(.makeWorkTapped(mentioning.id))
        await settle("work for the mentioned") { await server.newItems.count == 2 }
        #expect(await server.newItems.last?.owner == "engineering")

        store.send(.makeWorkTapped(plain.id))
        await settle("work for who answers here") { await server.newItems.count == 3 }
        // Nobody addressed: who answers in the channel (its lead), titled from its words.
        #expect(await server.newItems.last == NewWorkItem(title: "Decide pricing", owner: "growth", objective: "Decide pricing", projectID: "p1"))
    }

    @Test("A new project is created with its fields, and its channel opens")
    func createsProject() async {
        let server = PlacesServer()
        let store = await makeStore(server)
        store.send(.newProjectTapped)
        #expect(store.newProject != nil)
        store.send(.projectCreateTapped(ProjectChange(name: "  Hiring  ", goal: "Two engineers", lead: "ops", members: ["engineering"])))
        await settle("created") { store.place == .project("p2") && store.newProject == nil }
        #expect(await server.created == [ProjectChange(name: "Hiring", goal: "Two engineers", lead: "ops", members: ["engineering"])])
        #expect(store.state.project("p2")?.name == "Hiring")
        #expect(store.main?.key == .project("p2"))
    }
}
