import ComposableArchitecture2
import Dependencies
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

/// The business's shared conversations as the server keeps them.
private actor ConversationServer {
    var messages: [String: [ConversationMessage]] = [:]
    var unread: [String: Int] = [:]
    var posts: [(key: String, message: NewMessage)] = []
    var reads: [(key: String, seen: String)] = []
    var paused: Set<String> = []
    var running: Set<String> = []
    var workItems = [WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Write a tagline", state: .inProgress, projectID: "p1")]
    var projects = [Project(id: "p1", name: "Launch", goal: "Ship Acme", leadEmployeeID: "ops")]
    private var count = 0

    @discardableResult
    func add(_ key: ConversationKey, _ author: String, _ text: String, kind: ConversationMessage.Kind = .message, ref: Ref? = nil, replyTo: String? = nil) -> ConversationMessage {
        count += 1
        let message = ConversationMessage(
            id: "m\(count)",
            conversation: key.rawValue,
            author: author,
            kind: kind,
            text: text,
            replyTo: replyTo,
            ref: ref,
            createdAt: Date(timeIntervalSince1970: 1_792_400_000 + Double(count)).formatted(.iso8601)
        )
        messages[key.rawValue, default: []].append(message)
        return message
    }

    func setUnread(_ key: ConversationKey, _ value: Int) { unread[key.rawValue] = value }
    func setPaused(_ id: String) { paused.insert(id) }
    func setRunning(_ ids: Set<String>) { running = ids }

    func summaries() -> [ConversationSummary] {
        messages.keys.sorted().map { ConversationSummary(key: $0, last: messages[$0]?.last, unread: unread[$0] ?? 0) }
    }

    /// Whoever spoke last answers next, else the conversation's default.
    func page(_ key: ConversationKey) -> ConversationPage {
        let messages = messages[key.rawValue] ?? []
        let last = messages.last { $0.employeeID != nil && !$0.isEvent }?.employeeID
        let fallback: String? = switch key.kind {
        case .direct: key.ref
        case .project: projects.first { $0.id == key.ref }?.leadEmployeeID
        case .work: workItems.first { $0.id == key.ref }?.ownerEmployeeID
        }
        return ConversationPage(messages: messages, respondent: last ?? fallback)
    }

    func post(_ key: ConversationKey, _ message: NewMessage) throws -> PostedMessage {
        let all = self.messages[key.rawValue] ?? []
        let replied = message.replyTo.flatMap { id in all.first { $0.id == id }?.employeeID }
        let recipients = message.mentions.isEmpty ? [replied ?? page(key).respondent].compactMap(\.self) : message.mentions
        if !recipients.isEmpty, recipients.allSatisfy(paused.contains) {
            throw DevysHTTPError.rejected(status: 409, message: "Growth is paused. Resume them to send.")
        }
        posts.append((key.rawValue, message))
        return PostedMessage(message: add(key, "person:person-preview", message.text, replyTo: message.replyTo), recipients: recipients)
    }

    func read(_ key: ConversationKey, _ seen: String) {
        reads.append((key.rawValue, seen))
        unread[key.rawValue] = 0
    }

    func status(_ id: String) -> EmployeeStatus {
        EmployeeStatus(state: RuntimeState(run: running.contains(id) ? .init(id: "r", stopped: false, deadline: nil) : nil, inbox: [], outbox: []))
    }
}

@MainActor
@Suite("Conversations")
struct ConversationFeatureTests {
    private func makeStore(_ server: ConversationServer) async -> StoreOf<Workspace> {
        let store: StoreOf<Workspace> = withDependencies {
            $0.sessionClient = .unimplemented
            $0.runtimeClient = RuntimeClient(
                account: { .fixture },
                business: { BusinessDetail.fixture($0) },
                status: { scope in await server.status(scope.employeeID) },
                stop: { _ in true },
                memory: { _ in [] },
                conversations: { _ in await server.summaries() },
                conversation: { _, key, _ in await server.page(key) },
                postMessage: { _, key, message in try await server.post(key, message) },
                markRead: { _, key, seen in await server.read(key, seen) },
                work: { _ in await server.workItems },
                projects: { _ in await server.projects }
            )
            $0.continuousClock = InstantClock()
            $0.uuid = .incrementing
        } operation: {
            Store(initialState: Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)) { Workspace() }
        }
        await settle("team and projects") { store.operationsScope != nil && store.projects.value != nil && store.work.value != nil }
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
        await settle("conversation") { store.main?.messages.value != nil }
    }

    @Test("The To chip shows who spoke last, a reply's author, the mentioned, and the picked responder")
    func toChip() async {
        let server = ConversationServer()
        let key = ConversationKey.project("p1")
        let ops = await server.add(key, "employee:ops", "Launch is Tuesday.")
        await server.add(key, "employee:growth", "The tagline is drafted.")
        let store = await makeStore(server)
        await open(.project("p1"), in: store)
        #expect(store.state.recipients(in: key) == ["growth"])
        store.send(.replyTapped(key, ops.id))
        #expect(store.state.recipients(in: key) == ["ops"])
        // Mentions answer instead, even over a reply.
        store.send(.draftChanged(key, "@Engineering can you check?"))
        #expect(store.state.recipients(in: key) == ["engineering"])
        store.send(.responderPicked(key, "business-ops"))
        #expect(store.state.recipients(in: key) == ["business-ops"])
        store.send(.responderPicked(key, nil))
        #expect(store.state.recipients(in: key) == ["engineering"])
    }

    @Test("Before anyone speaks, the conversation's default answers: the direct chat's employee, the project's lead")
    func defaults() {
        let team = BusinessDetail.fixture("acme").employees
        var conversation = OpenConversation(key: .direct("growth"))
        #expect(conversation.recipients(team: team, fallback: "growth") == ["growth"])
        conversation.respondent = "ops"
        #expect(conversation.recipients(team: team, fallback: "growth") == ["ops"])
        conversation.draft = "@Growth and @Business Operations"
        #expect(conversation.recipients(team: team, fallback: "growth") == ["growth", "business-ops"])
    }

    @Test("Picking from the To chip sends that employee as the sole mention")
    func pickerSends() async {
        let server = ConversationServer()
        let store = await makeStore(server)
        let key = ConversationKey.project("p1")
        await open(.project("p1"), in: store)
        store.send(.draftChanged(key, "Who owns the domain?"))
        store.send(.responderPicked(key, "engineering"))
        store.send(.sendTapped(key))
        await settle("posted") { await server.posts.count == 1 }
        #expect(await server.posts.first?.message.mentions == ["engineering"])
        #expect(store.main?.responderOverride == nil)
        #expect(store.main?.draft.isEmpty == true)
    }

    @Test("@ suggests matching names; picking one completes it and mentions the employee")
    func mentionInsertion() async {
        let server = ConversationServer()
        let store = await makeStore(server)
        let key = ConversationKey.project("p1")
        await open(.project("p1"), in: store)
        let team = store.snapshot.employees
        store.send(.draftChanged(key, "Ask @gro"))
        let typing = store.main?.draft ?? ""
        #expect(Mentions.suggestions(for: typing, team: team).map(\.id) == ["growth"])
        store.send(.mentionPicked(key, "growth"))
        #expect(store.main?.draft == "Ask @Growth ")
        #expect(store.main?.mentions == ["growth"])
        let completed = store.main?.draft ?? ""
        #expect(Mentions.suggestions(for: completed, team: team).isEmpty)
        #expect(store.state.recipients(in: key) == ["growth"])
        store.send(.draftChanged(key, "Ask @Growth for the tagline"))
        store.send(.sendTapped(key))
        await settle("posted") { await server.posts.count == 1 }
        #expect(await server.posts.first?.message.mentions == ["growth"])
        #expect(store.main?.mentions.isEmpty == true)
    }

    @Test("Mention text helpers: complete the typed name, append otherwise, ignore an @ inside a word")
    func mentionText() {
        #expect(Mentions.insert("Growth", into: "Hi @Gr") == "Hi @Growth ")
        #expect(Mentions.insert("Growth", into: "Hi") == "Hi @Growth ")
        #expect(Mentions.insert("Growth", into: "") == "@Growth ")
        #expect(Mentions.query(in: "mail me@example") == nil)
        #expect(Mentions.query(in: "@")?.isEmpty == true)
        let team = BusinessDetail.fixture("acme").employees
        #expect(Mentions.suggestions(for: "@", team: team).count == team.count)
        #expect(Mentions.suggestions(for: "@Head of", team: team).map(\.id) == ["ops"])
    }

    @Test("Sending shows the message at once, posts it, and shows who's working until they answer")
    func sending() async {
        let server = ConversationServer()
        await server.setRunning(["growth"])
        let store = await makeStore(server)
        let key = ConversationKey.direct("growth")
        await open(.direct("growth"), in: store)
        store.send(.draftChanged(key, "  How is the tagline?  "))
        store.send(.sendTapped(key))
        #expect(store.main?.pending.map(\.text) == ["How is the tagline?"])
        #expect(store.main?.draft.isEmpty == true)
        await settle("posted") { store.main?.pending.isEmpty == true && store.main?.messages.value?.count == 1 }
        let posted = await server.posts.first
        #expect(posted?.key == "direct:growth")
        #expect(posted?.message.id.count == 36)
        #expect(store.main?.awaiting == ["growth"])
        await settle("running") { store.state.isWorking("growth") }
        await server.add(key, "employee:growth", "Two options are ready.")
        await server.setRunning([])
        await settle("answered") { store.main?.awaiting.isEmpty == true }
        #expect(store.main?.messages.value?.last?.text == "Two options are ready.")
    }

    @Test("Replying quotes the message and goes to its author")
    func replyTo() async {
        let server = ConversationServer()
        let key = ConversationKey.project("p1")
        let growth = await server.add(key, "employee:growth", "Draft ready.")
        await server.add(key, "employee:ops", "Domain is booked.")
        let store = await makeStore(server)
        await open(.project("p1"), in: store)
        store.send(.replyTapped(key, growth.id))
        #expect(store.main?.replyingTo == growth.id)
        store.send(.draftChanged(key, "Shorter please"))
        store.send(.sendTapped(key))
        #expect(store.main?.replyingTo == nil)
        await settle("posted") { await server.posts.count == 1 }
        #expect(await server.posts.first?.message.replyTo == growth.id)
        await settle("waiting on the author") { store.main?.awaiting == ["growth"] }
    }

    @Test("A hand-off card moves the middle into its thread under the project; Back returns to the channel")
    func handOffCard() async throws {
        let server = ConversationServer()
        await server.add(.project("p1"), "system", "Growth took on \"Write a tagline\".", kind: .event, ref: .workItem("c1"))
        await server.add(.work("c1"), "employee:growth", "Starting with three options.")
        let store = await makeStore(server)
        await open(.project("p1"), in: store)
        let timeline = ChatTimeline(messages: store.main?.messages.value ?? [], pending: [], now: .now)
        let card = try #require(timeline.items.compactMap { if case .event(let event) = $0 { event } else { nil } }.first)
        let ref = try #require(card.ref)
        #expect(ref == .workItem("c1"))
        store.send(.threadOpened(ref.id))
        #expect(store.place == .thread("c1"))
        #expect(store.history == [.project("p1")])
        #expect(store.state.title(of: store.place).title == "Write a tagline")
        #expect(store.state.title(of: store.place).parent?.place == .project("p1"))
        await settle("work thread") { store.main?.key == .work("c1") && store.main?.messages.value?.count == 1 }
        #expect(store.state.isPanelOpen)
        store.send(.draftChanged(.work("c1"), "Make them shorter"))
        store.send(.sendTapped(.work("c1")))
        await settle("posted to the work thread") { await server.posts.count == 1 }
        #expect(await server.posts.first?.key == "work:c1")
        #expect(store.main?.draft.isEmpty == true)
        store.send(.backTapped)
        #expect(store.place == .project("p1"))
        #expect(store.history.isEmpty)
        #expect(store.main?.key == .project("p1"))
    }

    @Test("Unread counts come from the server and clear while the conversation is on screen")
    func unread() async {
        let server = ConversationServer()
        let key = ConversationKey.project("p1")
        await server.add(key, "employee:ops", "One")
        let newest = await server.add(key, "employee:growth", "Two")
        await server.setUnread(key, 2)
        await server.add(.direct("growth"), "employee:growth", "Ping")
        await server.setUnread(.direct("growth"), 1)
        let store = await makeStore(server)
        await settle("unread") { store.state.unread(key) == 2 && store.state.unread(.direct("growth")) == 1 }
        store.send(.placeSelected(.project("p1")))
        await settle("loaded") { store.main?.messages.value != nil }
        #expect(store.state.unread(key) == 0)
        await settle("read") { await server.reads.contains { $0.key == "project:p1" } }
        #expect(await server.reads.first { $0.key == "project:p1" }?.key == "project:p1")
        #expect(await server.reads.first { $0.key == "project:p1" }?.seen == newest.createdAt)
        #expect(store.state.unread(.direct("growth")) == 1)
    }

    @Test("When everyone who'd answer is paused, the server's words show inline and the draft comes back")
    func paused() async {
        let server = ConversationServer()
        await server.setPaused("growth")
        let store = await makeStore(server)
        let key = ConversationKey.direct("growth")
        await open(.direct("growth"), in: store)
        store.send(.draftChanged(key, "Hello"))
        store.send(.sendTapped(key))
        await settle("refused") { store.main?.error != nil }
        #expect(store.main?.error == "Growth is paused. Resume them to send.")
        #expect(store.main?.pending.isEmpty == true)
        #expect(store.main?.draft == "Hello")
        #expect(store.main?.awaiting.isEmpty == true)
        store.send(.draftChanged(key, "Hello again"))
        #expect(store.main?.error == nil)
    }
}

/// Sleeps return at once, so polling and the refresh loop run without real delays.
struct InstantClock: Clock {
    typealias Duration = Swift.Duration
    struct Instant: InstantProtocol {
        var offset: Duration = .zero
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    var now: Instant { Instant() }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}
