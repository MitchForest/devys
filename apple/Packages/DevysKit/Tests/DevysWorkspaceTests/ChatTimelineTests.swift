import DevysCharacter
import DevysClient
import Foundation
import Testing
@testable import DevysWorkspace

@Suite("Chat timeline and presence")
struct ChatTimelineTests {
    private let start = Date(timeIntervalSince1970: 1_792_400_000)

    private func message(_ id: Int, _ author: String, after seconds: TimeInterval, kind: ConversationMessage.Kind = .message, replyTo: String? = nil) -> ConversationMessage {
        ConversationMessage(
            id: "m\(id)",
            conversation: "space:s1",
            author: author,
            kind: kind,
            text: "m\(id)",
            replyTo: replyTo,
            ref: kind == .event ? "c1" : nil,
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
        #expect(events == [ChatTimeline.Event(id: "m7", text: "m7", ref: "c1")])
    }

    @Test("An hour's silence adds a time heading; replies quote their message; unposted sends come last")
    func headingsQuotesAndPending() {
        let timeline = ChatTimeline(
            messages: [message(1, "person:p1", after: 0), message(2, "employee:ops", after: 2 * 3600, replyTo: "m1")],
            pending: [PendingMessage(id: "local", text: "Next", replyTo: "m2", delivery: .failed)],
            now: start.addingTimeInterval(2 * 3600 + 10),
            calendar: Calendar(identifier: .gregorian)
        )
        #expect(timeline.items.filter { if case .heading = $0 { true } else { false } }.count == 2)
        #expect(bubbles(timeline)[1].quote == ChatTimeline.Quote(messageID: "m1", text: "m1", employeeID: nil))
        #expect(bubbles(timeline).last?.delivery == .failed)
        #expect(bubbles(timeline).last?.isOwner == true)
        #expect(bubbles(timeline).last?.quote?.employeeID == "ops")
    }

    @Test("Presence hides idle teammates and reflects Operations' live state")
    func presence() {
        var state = Workspace.State(server: URL(string: "http://127.0.0.1:5173")!)
        state.preview = .acmeLaunch
        let idle = EmployeeStatus(state: RuntimeState(run: nil, inbox: [], outbox: []))
        state.status = .loaded(idle)
        let shown = state.presence
        #expect(shown.allSatisfy { $0.employee.activity != .idle || $0.employee.id == state.operations?.id })
        #expect(!shown.contains { $0.employee.id == state.operations?.id && $0.signal == .working })

        let running = EmployeeStatus(state: RuntimeState(run: .init(id: "r", stopped: false, deadline: nil), inbox: [], outbox: []))
        state.status = .loaded(running)
        #expect(state.presence.first { $0.employee.id == state.operations?.id }?.signal == .working)

        let stopped = EmployeeStatus(state: RuntimeState(run: .init(id: "r", stopped: true, deadline: nil), inbox: [], outbox: []))
        state.status = .loaded(stopped)
        #expect(state.presence.first { $0.employee.id == state.operations?.id }?.signal == .paused)
    }
}
