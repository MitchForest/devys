import ChatCore
import Foundation

public struct ConversationEventType:
    RawRepresentable,
    Codable,
    Sendable,
    Equatable,
    Hashable,
    ExpressibleByStringLiteral
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let messageUpsert: Self = "message.upsert"
    public static let messageDeleted: Self = "message.deleted"
    public static let messageBlockUpdated: Self = "message.block.updated"
    public static let sessionUpdated: Self = "session.updated"
    public static let sessionStatus: Self = "session.status"
    public static let streamHeartbeat: Self = "stream.heartbeat"
}

public struct ConversationEventEnvelope: Codable, Sendable, Equatable, Identifiable {
    public let schemaVersion: Int
    public let eventID: String
    public let sessionID: String
    public let sequence: UInt64
    public let timestamp: Date
    public let type: ConversationEventType
    public let payload: JSONValue?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case eventID = "eventId"
        case sessionID = "sessionId"
        case sequence
        case timestamp
        case type
        case payload
    }

    public var id: String { eventID }

    public init(
        schemaVersion: Int = 1,
        eventID: String = UUID().uuidString,
        sessionID: String,
        sequence: UInt64,
        timestamp: Date = .now,
        type: ConversationEventType,
        payload: JSONValue? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.sessionID = sessionID
        self.sequence = sequence
        self.timestamp = timestamp
        self.type = type
        self.payload = payload
    }

    public func decodePayload<T: Decodable>(_ type: T.Type) -> T? {
        guard let payload else { return nil }
        return try? ServerJSONCoding.decodeValue(type, from: payload)
    }
}

public struct ConversationStreamSubscribeRequest: Codable, Sendable, Equatable {
    public let sessionID: String
    public let cursor: StreamCursor?
    public let includeRecentHistory: Bool
    public let historyLimit: Int?

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case cursor
        case includeRecentHistory
        case historyLimit
    }

    public init(
        sessionID: String,
        cursor: StreamCursor? = nil,
        includeRecentHistory: Bool = true,
        historyLimit: Int? = nil
    ) {
        self.sessionID = sessionID
        self.cursor = cursor
        self.includeRecentHistory = includeRecentHistory
        self.historyLimit = historyLimit
    }
}

public struct ConversationStreamSubscribeResponse: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let sessionID: String
    public let nextCursor: StreamCursor?

    enum CodingKeys: String, CodingKey {
        case accepted
        case sessionID = "sessionId"
        case nextCursor
    }

    public init(accepted: Bool, sessionID: String, nextCursor: StreamCursor? = nil) {
        self.accepted = accepted
        self.sessionID = sessionID
        self.nextCursor = nextCursor
    }
}

public struct ConversationEventBatchResponse: Codable, Sendable, Equatable {
    public let sessionID: String
    public let events: [ConversationEventEnvelope]
    public let nextCursor: StreamCursor
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case events
        case nextCursor
        case hasMore
    }

    public init(
        sessionID: String,
        events: [ConversationEventEnvelope],
        nextCursor: StreamCursor,
        hasMore: Bool
    ) {
        self.sessionID = sessionID
        self.events = events
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}
