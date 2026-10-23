import DevysCharacter
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@Suite("Chat timeline and who is working")
struct ChatTimelineTests {
    private let start = Date(timeIntervalSince1970: 1_792_400_000)

    private func message(
        _ id: Int, _ author: String, after seconds: TimeInterval, kind: ConversationMessage.Kind = .message,
        replyTo: String? = nil, replies: [String] = [], question: String? = nil, pickMany: Bool = false
    ) -> ConversationMessage {
        ConversationMessage(
            id: "m\(id)",
            conversation: "project:p1",
            author: author,
            kind: kind,
            text: "m\(id)",
            replyTo: replyTo,
            ref: kind == .event ? .workItem("c1") : nil,
            replies: replies,
            question: question,
            pickMany: pickMany,
            createdAt: ServerDate.format(start.addingTimeInterval(seconds))
        )
    }

    private var bubbles: (ChatTimeline) -> [ChatTimeline.Bubble] = { timeline in
        timeline.items.compactMap { if case .bubble(let bubble) = $0 { bubble } else { nil } }
    }

    @Test("A question card shows on the latest employee message, past events, until the owner speaks")
    func questionCards() {
        let asked = [
            message(1, "employee:ops", after: 0, replies: ["Old"]),
            message(2, "employee:growth", after: 10, replies: ["Bold", "Calm"]),
            message(3, "system", after: 20, kind: .event)
        ]
        let offered = { (timeline: ChatTimeline) in self.bubbles(timeline).filter { $0.question != nil }.map(\.id) }
        #expect(offered(ChatTimeline(messages: asked, pending: [], now: start)) == ["m2"])
        #expect(offered(ChatTimeline(messages: asked + [message(4, "person:p1", after: 30)], pending: [], now: start)).isEmpty)
        #expect(offered(ChatTimeline(messages: asked, pending: [PendingMessage(id: "x", text: "Calm")], now: start)).isEmpty)
        #expect(offered(ChatTimeline(messages: asked + [message(5, "employee:ops", after: 40)], pending: [], now: start)).isEmpty)
    }

    @Test("Devys's notice that a turn stopped offers Ask again while it is the latest word")
    func noticeReplies() {
        let stopped = message(6, "system", after: 50, kind: .event, replies: ["Ask again"])
        let events = { (timeline: ChatTimeline) in
            timeline.items.compactMap { if case .event(let event) = $0, event.question != nil { event.id } else { nil } }
        }
        let base = [message(2, "employee:growth", after: 10, replies: ["Bold"])]
        #expect(events(ChatTimeline(messages: base + [stopped], pending: [], now: start)) == ["m6"])
        #expect(events(ChatTimeline(messages: base + [stopped, message(7, "person:p1", after: 60)], pending: [], now: start)).isEmpty)
    }

    @Test("A work item's card is one event, drawn live, and never offers replies or groups bubbles")
    func workCard() {
        let card = ConversationMessage(
            id: "m9", conversation: "work:c1", author: "system", kind: .card, text: "Set up the domain",
            ref: .workItem("c1"), createdAt: ServerDate.format(start.addingTimeInterval(30))
        )
        let timeline = ChatTimeline(messages: [message(2, "employee:growth", after: 10, replies: ["Bold"]), card], pending: [], now: start)
        let events = timeline.items.compactMap { if case .event(let event) = $0 { event } else { nil } }
        #expect(events.map(\.id) == ["m9"] && events.first?.isCard == true && events.first?.ref == .workItem("c1"))
        #expect(bubbles(timeline).first?.question?.answers == ["Bold"])
    }

    @Test("A question card carries its title, at most six answers lettered A to F, and whether several may be picked")
    func questionLetters() {
        let asked = message(2, "employee:growth", after: 10, replies: ["One", "Two", "Three", "Four", "Five", "Six", "Seven"], question: "Which ones?", pickMany: true)
        let question = bubbles(ChatTimeline(messages: [asked], pending: [], now: start)).first?.question
        #expect(question?.title == "Which ones?" && question?.pickMany == true)
        #expect(question?.answers.count == 6)
        #expect(question?.answer(forLetter: "b") == "Two" && question?.answer(forLetter: "F") == "Six")
        #expect(question?.answer(forLetter: "G") == nil && question?.answer(forLetter: "ab") == nil)
        #expect(ChatTimeline.Question.letter(0) == "A" && ChatTimeline.Question.letter(2) == "C")
        let untitled = bubbles(ChatTimeline(messages: [message(3, "employee:ops", after: 10, replies: ["Yes"], question: "  ")], pending: [], now: start)).first?.question
        #expect(untitled?.title == nil && untitled?.pickMany == false)
    }

    @Test("Results and steps read the same words as the web")
    func resultWords() {
        #expect(WorkResult(label: "Registered acme-widgets.com", value: "expires 2027-10-22", check: .held).text == "Registered acme-widgets.com · expires 2027-10-22 ✓")
        #expect(WorkResult(label: "Live at", url: "https://acme-widgets.com").text == "Live at https://acme-widgets.com")
        #expect(WorkResult(label: "Payment", value: "uncertain", check: .uncertain).text == "Payment · uncertain ?")
        #expect(WorkResult(label: "MX", check: .failed).text == "MX ✗")
        #expect(WorkStep.progress([]) == nil)
        #expect(WorkStep.progress([WorkStep(title: "Register", state: .done), WorkStep(title: "Set up email", state: .doing), WorkStep(title: "Test", state: .todo)]) == "1 of 3 · Set up email")
    }

    @Test("A bubble keeps a list one item per line, bullets as bullets, numbers as written")
    func listsInBubbles() {
        let text = String(MessageBubble.rendered("Two ways:\n- **Ramp**\n* A card\n2. Later").characters)
        #expect(text == "Two ways:\n• Ramp\n• A card\n2. Later")
    }

    @Test("Consecutive messages from one author group; a new author, an event or a long gap starts a group")
    func grouping() {
        let timeline = ChatTimeline(
            messages: [
                message(1, "person:p1", after: 0),
                message(2, "person:p1", after: 30),
                message(3, "employee:ops", after: 60),
                message(4, "employee:ops", after: 90),
                message(5, "employee:growth", after: 100),
                message(6, "employee:growth", after: 110),
                message(7, "system", after: 115, kind: .event),
                message(8, "employee:growth", after: 120),
                message(9, "employee:growth", after: 120 + 600)
            ],
            pending: [],
            now: start,
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(bubbles(timeline).map(\.position) == [.first, .last, .first, .last, .first, .last, .single, .single])
        #expect(bubbles(timeline).map(\.isOwner) == [true, true, false, false, false, false, false, false])
        #expect(bubbles(timeline)[2].employeeID == "ops")
        #expect(timeline.items.filter { if case .heading = $0 { true } else { false } }.count == 1)
        let events = timeline.items.compactMap { if case .event(let event) = $0 { event } else { nil } }
        #expect(events == [ChatTimeline.Event(id: "m7", text: "m7", ref: .workItem("c1"))])
    }

    @Test("An hour's silence adds a time heading; replies quote an earlier message; unposted sends come last")
    func headingsQuotesAndPending() {
        let timeline = ChatTimeline(
            messages: [
                message(1, "person:p1", after: 0),
                message(3, "employee:growth", after: 60),
                message(2, "employee:ops", after: 2 * 3600, replyTo: "m1"),
                message(4, "employee:growth", after: 2 * 3600 + 5, replyTo: "m2")
            ],
            pending: [PendingMessage(id: "local", text: "Next", replyTo: "m2", delivery: .failed)],
            now: start.addingTimeInterval(2 * 3600 + 10),
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(timeline.items.filter { if case .heading = $0 { true } else { false } }.count == 2)
        #expect(bubbles(timeline)[2].quote == ChatTimeline.Quote(messageID: "m1", text: "m1", employeeID: nil))
        // A reply to the message right above it shows no quote.
        #expect(bubbles(timeline)[3].quote == nil)
        #expect(bubbles(timeline).last?.delivery == .failed)
        #expect(bubbles(timeline).last?.isOwner == true)
        #expect(bubbles(timeline).last?.quote?.employeeID == "ops")
    }

    @Test("A message about a record says so under it, named as the web names it: \"Viewing Pricing\"")
    func viewedRecord() {
        let about = ConversationMessage(
            id: "m1", conversation: "direct:ops", author: "employee:ops", kind: .message, text: "Here",
            replyTo: nil, ref: .workItem("c1"), createdAt: ServerDate.format(start)
        )
        let timeline = ChatTimeline(messages: [about], pending: [], now: start)
        #expect(bubbles(timeline).map(\.ref) == [.workItem("c1")])

        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.work = .loaded([WorkItem(id: "c1", ownerEmployeeID: "growth", title: "Book the venue")])
        state.artifacts = [Artifact(id: "a1", filename: "Pricing.html", contentType: "text/html", byteLength: 1, createdAt: "2026-10-21T00:00:00Z")]
        #expect(state.recordTitle(.workItem("c1")) == "Book the venue")
        #expect(state.recordTitle(.artifact("a1")) == "Pricing")
        #expect(state.recordTitle(.file("/Users/o/Devys/b/plan.md")) == "plan.md")
        #expect(state.recordTitle(.codeSession("s1")) == "Coding session")
        #expect(state.recordDetail(.codeSession("s1")) == "Coding session")
        #expect(state.recordDetail(.file("/Users/o/Devys/b/plan.md")) == "File")
    }

    @Test("A kept page means the page: it shows its latest version, once, and Keep sees any version")
    func keptPages() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.artifacts = [
            Artifact(id: "v1", filename: "Pricing.html", contentType: "text/html", byteLength: 1, createdAt: "2026-10-21T00:00:00Z", latestID: "v2"),
            Artifact(id: "v2", filename: "Pricing.html", contentType: "text/html", byteLength: 1, createdAt: "2026-10-21T00:01:00Z")
        ]
        let project = Project(id: "p1", name: "Launch", leadEmployeeID: "ops", items: [ProjectItem(id: "i1", ref: .artifact("v1"))])
        #expect(state.currentRef(.artifact("v1")) == .artifact("v2"))
        #expect(state.currentRef(.file("/b/plan.md")) == .file("/b/plan.md"))
        #expect(state.keptEntry(of: .artifact("v2"), in: project)?.id == "i1")
        #expect(state.keptEntry(of: .artifact("other"), in: project) == nil)
    }

    @Test("Working and faces derive from each teammate's runtime status, like the web's workingOf")
    func working() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.snapshot = .acmeLaunch
        let idle = EmployeeStatus(state: RuntimeState(run: nil, inbox: [], outbox: []))
        let running = EmployeeStatus(state: RuntimeState(run: .init(id: "r", stopped: false, deadline: nil), inbox: [], outbox: []))
        let unfinished = EmployeeStatus(state: RuntimeState(run: nil, inbox: [InboxEntry(id: "m", text: "Go", receivedAt: 1, status: .queued)], outbox: []))
        let failed = EmployeeStatus(state: RuntimeState(run: nil, inbox: [InboxEntry(id: "m", text: "Go", receivedAt: 1, status: .failed)], outbox: []))
        state.statuses = ["engineering": running, "growth": unfinished, "business-ops": failed]
        #expect(state.isWorking("engineering") && state.isWorking("growth"))
        #expect(!state.isWorking("business-ops"))
        #expect(state.mood(for: state.snapshot.employees[1]) == .working)
        #expect(state.mood(for: state.snapshot.employees[3]) == .idle)
        state.statuses["engineering"] = idle
        #expect(state.mood(for: state.snapshot.employees[1]) == .idle)
    }

    @Test("Take-over is mine only when the signed-in person has it; a work item shows its own request")
    func takeoverAndWorkDecisions() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.account = .fixture
        let free = WorkItem(id: "c1", ownerEmployeeID: "growth", title: "PR")
        let mine = WorkItem(id: "c2", ownerEmployeeID: "growth", title: "PR", takenOverBy: "person-preview")
        let theirs = WorkItem(id: "c3", ownerEmployeeID: "growth", title: "PR", takenOverBy: "person-other")
        #expect(!state.isMine(free) && state.takeoverTitle(free) == nil)
        #expect(state.isMine(mine) && state.takeoverTitle(mine) == "You have it")
        #expect(!state.isMine(theirs) && state.takeoverTitle(theirs) == "Taken over by another person")
        state.home = .loaded(Home(needsYou: [
            NeedsYouItem(Decision(id: "d1", employeeID: "growth", capability: "email.send", input: .object([:]), workItemID: "c1"), title: "PR"),
            NeedsYouItem(Decision(id: "d2", employeeID: "growth", capability: "email.send", input: .object([:])), title: "email.send"),
            NeedsYouItem(kind: .work, id: "c2", title: "PR", workID: "c2")
        ]))
        #expect(state.request(for: free)?.id == "d1")
        #expect(state.request(for: mine) == nil)
    }
}
