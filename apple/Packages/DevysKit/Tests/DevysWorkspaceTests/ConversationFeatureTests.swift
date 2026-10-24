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
    func add(
        _ key: ConversationKey, _ author: String, _ text: String, kind: ConversationMessage.Kind = .message,
        ref: Ref? = nil, replyTo: String? = nil, replies: [String] = [], question: String? = nil, pickMany: Bool = false
    ) -> ConversationMessage {
        count += 1
        let message = ConversationMessage(
            id: "m\(count)",
            conversation: key.rawValue,
            author: author,
            kind: kind,
            text: text,
            replyTo: replyTo,
            ref: ref,
            replies: replies,
            question: question,
            pickMany: pickMany,
            createdAt: ServerDate.format(Date(timeIntervalSince1970: 1_792_400_000 + Double(count)))
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
                uploadFile: { _, file in
                    guard file.name != "broken.pdf" else { throw DevysHTTPError.invalidResponse }
                    return .file("/acme/Uploads/\(file.name)")
                },
                projects: { _ in await server.projects }
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

    private func offered(_ store: StoreOf<Workspace>) -> [ChatTimeline.Question] {
        ChatTimeline(messages: store.main?.messages.value ?? [], pending: store.main?.pending ?? [], now: .now)
            .items.compactMap { item in if case .bubble(let bubble) = item { bubble.question } else { nil } }
    }

    @Test("A question card's answer is sent as the reply to it and leaves the draft; the card goes once the owner speaks")
    func questionCardSingle() async {
        let server = ConversationServer()
        let key = ConversationKey.direct("growth")
        await server.add(key, "person:person-preview", "We need a tagline.")
        let question = await server.add(key, "employee:growth", "Which way?", replies: ["Bold", "Calm"], question: "Bold or calm?")
        let store = await makeStore(server)
        await open(.direct("growth"), in: store)
        #expect(offered(store).map(\.answers) == [["Bold", "Calm"]] && offered(store).first?.title == "Bold or calm?")
        #expect(store.state.offeredQuestion(in: key)?.answer(forLetter: "b") == "Calm")
        store.send(.draftChanged(key, "Also the logo"))
        store.send(.answerPicked(key, question.id, "Calm"))
        #expect(offered(store).isEmpty)
        await settle("posted") { await server.posts.count == 1 }
        let sent = await server.posts.first?.message
        #expect(sent?.text == "Calm")
        #expect(sent?.replyTo == question.id)
        #expect(sent?.mentions.isEmpty == true)
        #expect(store.main?.draft == "Also the logo")
        await settle("shown") { store.main?.pending.isEmpty == true }
        #expect(offered(store).isEmpty)
    }

    @Test("Several answers are ticked and unticked, then Done sends them in the card's order as one reply")
    func questionCardMany() async {
        let server = ConversationServer()
        let key = ConversationKey.direct("growth")
        let question = await server.add(key, "employee:growth", "Which channels?", replies: ["Email", "Ads", "Posts"], question: "Which channels?", pickMany: true)
        let store = await makeStore(server)
        await open(.direct("growth"), in: store)
        store.send(.answersDone(key, question.id))
        #expect(await server.posts.isEmpty, "Done does nothing until something is ticked")
        store.send(.answerPicked(key, question.id, "Posts"))
        store.send(.answerPicked(key, question.id, "Email"))
        store.send(.answerPicked(key, question.id, "Ads"))
        store.send(.answerPicked(key, question.id, "Ads"))
        store.send(.answerPicked(key, question.id, "Not offered"))
        #expect(store.state.picked(in: key, for: question.id) == ["Posts", "Email"])
        #expect(await server.posts.isEmpty, "ticking sends nothing")
        store.send(.answersDone(key, question.id))
        await settle("posted") { await server.posts.count == 1 }
        let sent = await server.posts.first?.message
        #expect(sent?.text == "Email, Posts" && sent?.replyTo == question.id)
        #expect(store.state.picked(in: key, for: question.id).isEmpty)
        // "Something else" puts the cursor in the composer.
        let focus = store.composerFocus
        store.send(.somethingElseTapped(key))
        #expect(store.composerFocus == focus + 1)
    }

    @Test("Upload a file: it goes up, is attached, and goes with the next message as its ref; a failure says so")
    func uploadAttaches() async {
        let server = ConversationServer()
        let key = ConversationKey.direct("growth")
        let store = await makeStore(server)
        await open(.direct("growth"), in: store)
        store.send(.uploadChosen(key, ChosenFile(name: "broken.pdf", type: "application/pdf", data: Data([1]))))
        await settle("failed") { store.main?.error != nil }
        #expect(store.main?.isUploading == false && store.main?.attachment == nil)
        store.send(.uploadChosen(key, ChosenFile(name: "logo.png", type: "image/png", data: Data([1, 2]))))
        await settle("attached") { store.main?.attachment != nil }
        #expect(store.main?.attachment == .file("/acme/Uploads/logo.png") && store.main?.isUploading == false)
        store.send(.draftChanged(key, "Use this logo"))
        store.send(.sendTapped(key))
        await settle("posted") { await server.posts.count == 1 }
        #expect(await server.posts.first?.message.ref == .file("/acme/Uploads/logo.png"))
        #expect(store.main?.attachment == nil)
    }

    @Test("Select Messages copies the ticked messages oldest first, as Name: text, without events")
    func selectionCopies() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.snapshot.employees = BusinessDetail.fixture("acme").employees
        let key = ConversationKey.direct("growth")
        var open = OpenConversation(key: key)
        open.messages = .loaded([
            ConversationMessage(id: "m1", conversation: key.rawValue, author: "person:p1", text: "Which registrar?", createdAt: "2026-10-24T10:00:00.000Z"),
            ConversationMessage(id: "m2", conversation: key.rawValue, author: "system", kind: .event, text: "Growth started a work item.", createdAt: "2026-10-24T10:00:01.000Z"),
            ConversationMessage(id: "m3", conversation: key.rawValue, author: "employee:growth", text: "GoDaddy.", createdAt: "2026-10-24T10:00:02.000Z"),
            ConversationMessage(id: "m4", conversation: key.rawValue, author: "employee:growth", text: "Not this one.", createdAt: "2026-10-24T10:00:03.000Z")
        ])
        state.main = open
        state.main?.selection = ["m3", "m1", "m2"]
        #expect(state.selectionText(in: key) == "You: Which registrar?\n\nGrowth: GoDaddy.")
        #expect(state.selectableMessages(in: key) == ["m1", "m3", "m4"], "events aren't said, so they aren't selected")
    }

    @Test("Before anyone speaks, the conversation's default answers: the direct chat's employee, the project's lead")
    func defaults() {
        let team = BusinessDetail.fixture("acme").employees
        var conversation = OpenConversation(key: .direct("growth"))
        #expect(conversation.recipients(team: team, fallback: "growth") == ["growth"])
        conversation.respondent = "ops"
        #expect(conversation.recipients(team: team, fallback: "growth") == ["ops"])
        conversation.draft = "@Growth and @Admin"
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
        #expect(Mentions.suggestions(for: "@Chief of", team: team).map(\.id) == ["ops"])
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

    @Test("A work item's card moves the middle into its thread under the project; Back returns to the channel")
    func workCard() async throws {
        let server = ConversationServer()
        await server.add(.project("p1"), "system", "Write a tagline", kind: .card, ref: .workItem("c1"))
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
        #expect(!store.state.isPanelOpen, "the thread's card is pinned above its composer, not in the panel")
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
