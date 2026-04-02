import ServerProtocol
import Testing
@testable import ChatUI

@Test func transportActorIgnoresHeartbeatCursorRegression() async {
    let actor = TransportActor()
    let sessionID = "session-heartbeat"

    _ = await actor.beginStreaming(sessionID: sessionID)

    let advanced = await actor.apply(
        event: makeEvent(sessionID: sessionID, sequence: 7, type: .messageUpsert)
    )
    #expect(advanced.sequence == 7)

    let heartbeat = await actor.apply(
        event: makeEvent(sessionID: sessionID, sequence: 0, type: .streamHeartbeat)
    )
    #expect(heartbeat.sequence == 7)

    let stored = await actor.cursor(for: sessionID)
    #expect(stored?.sequence == 7)
}

@Test func transportActorRejectsOutOfOrderSequenceUpdates() async {
    let actor = TransportActor()
    let sessionID = "session-ooo"

    _ = await actor.beginStreaming(sessionID: sessionID)

    _ = await actor.apply(
        event: makeEvent(sessionID: sessionID, sequence: 12, type: .messageUpsert)
    )

    let duplicate = await actor.apply(
        event: makeEvent(sessionID: sessionID, sequence: 12, type: .messageUpsert)
    )
    #expect(duplicate.sequence == 12)

    let older = await actor.apply(
        event: makeEvent(sessionID: sessionID, sequence: 9, type: .messageUpsert)
    )
    #expect(older.sequence == 12)

    let stored = await actor.cursor(for: sessionID)
    #expect(stored?.sequence == 12)
}

@Test func transportActorMaintainsIndependentSessionCursors() async {
    let actor = TransportActor()

    _ = await actor.apply(event: makeEvent(sessionID: "session-a", sequence: 3, type: .messageUpsert))
    _ = await actor.apply(event: makeEvent(sessionID: "session-b", sequence: 11, type: .messageUpsert))

    let cursorA = await actor.cursor(for: "session-a")
    let cursorB = await actor.cursor(for: "session-b")

    #expect(cursorA?.sequence == 3)
    #expect(cursorB?.sequence == 11)
}

private func makeEvent(
    sessionID: String,
    sequence: UInt64,
    type: ConversationEventType
) -> ConversationEventEnvelope {
    ConversationEventEnvelope(
        sessionID: sessionID,
        sequence: sequence,
        type: type,
        payload: nil
    )
}
