import DevysCharacter
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@Suite("Chat timeline and who is working")
struct ChatTimelineTests {
    private let start = Date(timeIntervalSince1970: 1_792_400_000)

    private func message(_ id: Int, _ author: String, after seconds: TimeInterval, kind: ConversationMessage.Kind = .message, replyTo: String? = nil) -> ConversationMessage {
        ConversationMessage(
            id: "m\(id)",
            conversation: "project:p1",
            author: author,
            kind: kind,
            text: "m\(id)",
            replyTo: replyTo,
            ref: kind == .event ? .workItem("c1") : nil,
            createdAt: start.addingTimeInterval(seconds).formatted(.iso8601)
        )
    }

    private var bubbles: (ChatTimeline) -> [ChatTimeline.Bubble] = { timeline in
        timeline.items.compactMap { if case .bubble(let bubble) = $0 { bubble } else { nil } }
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

    @Test("Working and faces derive from each teammate's runtime status, like the web's workingOf")
    func working() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.snapshot = .acmeLaunch
        let idle = EmployeeStatus(state: RuntimeState(run: nil, inbox: [], outbox: []))
        let running = EmployeeStatus(state: RuntimeState(run: .init(id: "r", stopped: false, deadline: nil), inbox: [], outbox: []))
        let unfinished = EmployeeStatus(state: RuntimeState(run: nil, inbox: [InboxEntry(id: "m", text: "Go", receivedAt: 1, status: "queued")], outbox: []))
        let failed = EmployeeStatus(state: RuntimeState(run: nil, inbox: [InboxEntry(id: "m", text: "Go", receivedAt: 1, status: "failed")], outbox: []))
        state.statuses = ["engineering": running, "growth": unfinished, "business-ops": failed]
        #expect(state.isWorking("engineering") && state.isWorking("growth"))
        #expect(!state.isWorking("business-ops"))
        #expect(state.mood(for: state.snapshot.employees[1]) == .working)
        #expect(state.mood(for: state.snapshot.employees[3]) == .idle)
        state.statuses["engineering"] = idle
        #expect(state.mood(for: state.snapshot.employees[1]) == .idle)
    }

    @Test("Take-over is mine only when the signed-in person has it; a work item shows its own decisions")
    func takeoverAndWorkDecisions() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.account = .fixture
        let free = Commitment(id: "c1", ownerEmployeeID: "growth", title: "PR")
        let mine = Commitment(id: "c2", ownerEmployeeID: "growth", title: "PR", takenOverBy: "person-preview")
        let theirs = Commitment(id: "c3", ownerEmployeeID: "growth", title: "PR", takenOverBy: "person-other")
        #expect(!state.isMine(free) && state.takeoverTitle(free) == nil)
        #expect(state.isMine(mine) && state.takeoverTitle(mine) == "You have it")
        #expect(!state.isMine(theirs) && state.takeoverTitle(theirs) == "Taken over by another person")
        state.decisions = .loaded([
            Decision(id: "d1", employeeID: "growth", capability: "email.send", input: .object([:]), commitmentID: "c1"),
            Decision(id: "d2", employeeID: "growth", capability: "email.send", input: .object([:]))
        ])
        #expect(state.decisions(for: free).map(\.id) == ["d1"])
        #expect(state.decisions(for: mine).isEmpty)
    }
}
