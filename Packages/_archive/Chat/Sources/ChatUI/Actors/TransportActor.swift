import ChatCore
import Foundation
import ServerProtocol

public actor TransportActor {
    public enum State: Sendable, Equatable {
        case idle
        case connecting(sessionID: String)
        case streaming(sessionID: String)
        case failed(sessionID: String, message: String)
    }

    public private(set) var state: State = .idle
    private var lastCursorBySessionID: [String: StreamCursor] = [:]

    public init() {}

    public func beginStreaming(
        sessionID: String,
        resumeFrom cursor: StreamCursor? = nil
    ) -> StreamCursor? {
        state = .connecting(sessionID: sessionID)
        if let cursor {
            lastCursorBySessionID[sessionID] = cursor
            return cursor
        }
        return lastCursorBySessionID[sessionID]
    }

    public func markStreaming(sessionID: String) {
        state = .streaming(sessionID: sessionID)
    }

    public func apply(event: ConversationEventEnvelope) -> StreamCursor {
        let previousSequence = lastCursorBySessionID[event.sessionID]?.sequence ?? 0
        guard event.sequence > previousSequence else {
            return StreamCursor(sessionID: event.sessionID, sequence: previousSequence)
        }

        let cursor = StreamCursor(sessionID: event.sessionID, sequence: event.sequence)
        lastCursorBySessionID[event.sessionID] = cursor
        if case .idle = state {
            state = .streaming(sessionID: event.sessionID)
        }
        return cursor
    }

    public func fail(sessionID: String, message: String) {
        state = .failed(sessionID: sessionID, message: message)
    }

    public func endStreaming(sessionID: String) {
        if case .streaming(let activeSessionID) = state, activeSessionID == sessionID {
            state = .idle
            return
        }
        if case .connecting(let activeSessionID) = state, activeSessionID == sessionID {
            state = .idle
            return
        }
        if case .failed(let activeSessionID, _) = state, activeSessionID == sessionID {
            state = .idle
        }
    }

    public func cursor(for sessionID: String) -> StreamCursor? {
        lastCursorBySessionID[sessionID]
    }

    public func reset(sessionID: String) {
        lastCursorBySessionID.removeValue(forKey: sessionID)
        endStreaming(sessionID: sessionID)
    }
}
