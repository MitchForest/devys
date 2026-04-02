import ChatCore
import Foundation
import ServerProtocol

public actor ConversationActor {
    public struct ApplyResult: Sendable, Equatable {
        public let didApply: Bool
        public let sessionID: String
        public let messages: [Message]
        public let cursor: StreamCursor
    }

    private var messagesBySessionID: [String: [Message]] = [:]
    private var lastSequenceBySessionID: [String: UInt64] = [:]

    public init() {}

    public func replaceMessages(
        _ messages: [Message],
        sessionID: String,
        cursor: UInt64 = 0
    ) -> [Message] {
        let normalized = normalizedMessages(messages)
        messagesBySessionID[sessionID] = normalized
        lastSequenceBySessionID[sessionID] = cursor
        return normalized
    }

    public func messages(for sessionID: String) -> [Message] {
        messagesBySessionID[sessionID, default: []]
    }

    public func upsertLocalMessage(_ message: Message) -> [Message] {
        var messages = messagesBySessionID[message.sessionID, default: []]
        upsert(message: message, into: &messages)
        let normalized = normalizedMessages(messages)
        messagesBySessionID[message.sessionID] = normalized
        return normalized
    }

    public func cursor(for sessionID: String) -> StreamCursor? {
        guard let sequence = lastSequenceBySessionID[sessionID] else { return nil }
        return StreamCursor(sessionID: sessionID, sequence: sequence)
    }

    public func apply(event: ConversationEventEnvelope) throws -> ApplyResult {
        let sessionID = event.sessionID
        let previousSequence = lastSequenceBySessionID[sessionID, default: 0]
        guard event.sequence > previousSequence else {
            return ApplyResult(
                didApply: false,
                sessionID: sessionID,
                messages: messagesBySessionID[sessionID, default: []],
                cursor: StreamCursor(sessionID: sessionID, sequence: previousSequence)
            )
        }

        var messages = messagesBySessionID[sessionID, default: []]
        switch event.type {
        case .messageUpsert, .messageBlockUpdated:
            guard let message = try decodeMessage(from: event.payload) else {
                throw ConversationEventApplyError.invalidPayload(
                    "Missing message payload for \(event.type.rawValue)"
                )
            }
            upsert(message: message, into: &messages)
        case .messageDeleted:
            guard let messageID = decodeMessageID(from: event.payload) else {
                throw ConversationEventApplyError.invalidPayload(
                    "Missing messageId payload for \(event.type.rawValue)"
                )
            }
            messages.removeAll { $0.id == messageID }
        default:
            break
        }

        let normalized = normalizedMessages(messages)
        messagesBySessionID[sessionID] = normalized
        lastSequenceBySessionID[sessionID] = event.sequence

        return ApplyResult(
            didApply: true,
            sessionID: sessionID,
            messages: normalized,
            cursor: StreamCursor(sessionID: sessionID, sequence: event.sequence)
        )
    }

    private func upsert(message: Message, into messages: inout [Message]) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func normalizedMessages(_ messages: [Message]) -> [Message] {
        messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id < rhs.id
        }
    }

    private func decodeMessage(from payload: JSONValue?) throws -> Message? {
        guard let payload else { return nil }
        if let nested = payload["message"] {
            return try ServerJSONCoding.decodeValue(Message.self, from: nested)
        }
        if case .object = payload {
            return try ServerJSONCoding.decodeValue(Message.self, from: payload)
        }
        return nil
    }

    private func decodeMessageID(from payload: JSONValue?) -> String? {
        guard let payload else { return nil }
        if let nested = payload["messageId"]?.stringValue {
            return nested
        }
        return payload["id"]?.stringValue
    }
}

public enum ConversationEventApplyError: Error, Equatable, Sendable {
    case invalidPayload(String)
}
