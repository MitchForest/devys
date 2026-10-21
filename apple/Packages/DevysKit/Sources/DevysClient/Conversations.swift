public import Foundation

/// One shared conversation: `direct:<employee>`, `project:<project>` or `work:<commitment>`.
public struct ConversationKey: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case direct, project, work }

    public let kind: Kind
    public let ref: String

    public init(_ kind: Kind, _ ref: String) {
        self.kind = kind
        self.ref = ref
    }

    /// Parses `kind:ref`; nil for anything else.
    public init?(_ raw: String) {
        guard let colon = raw.firstIndex(of: ":"), let kind = Kind(rawValue: String(raw[..<colon])) else { return nil }
        let ref = String(raw[raw.index(after: colon)...])
        guard !ref.isEmpty else { return nil }
        self.init(kind, ref)
    }

    public static func direct(_ employeeID: String) -> Self { Self(.direct, employeeID) }
    public static func project(_ projectID: String) -> Self { Self(.project, projectID) }
    public static func work(_ commitmentID: String) -> Self { Self(.work, commitmentID) }

    public var rawValue: String { "\(kind.rawValue):\(ref)" }
    public var description: String { rawValue }

    /// The key as one URL path segment, with ":" percent-encoded.
    var pathSegment: String {
        rawValue.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-"))) ?? rawValue
    }
}

/// One message in a shared conversation. Events are hand-off cards written by the system.
public struct ConversationMessage: Equatable, Sendable, Decodable, Identifiable {
    public enum Kind: String, Equatable, Sendable { case message, event }

    public let id: String
    public let conversation: String
    /// `person:<id>`, `employee:<id>` or `system`.
    public let author: String
    public let kind: Kind
    public let text: String
    public let replyTo: String?
    /// Employee ids the message addresses.
    public let mentions: [String]
    public let viaVoice: Bool
    /// The record an event is about: a work item's hand-off card, a page, a coding session.
    public let ref: Ref?
    public let createdAt: String
    public var reactions: [String]

    public init(
        id: String,
        conversation: String,
        author: String,
        kind: Kind = .message,
        text: String,
        replyTo: String? = nil,
        mentions: [String] = [],
        viaVoice: Bool = false,
        ref: Ref? = nil,
        createdAt: String,
        reactions: [String] = []
    ) {
        self.id = id
        self.conversation = conversation
        self.author = author
        self.kind = kind
        self.text = text
        self.replyTo = replyTo
        self.mentions = mentions
        self.viaVoice = viaVoice
        self.ref = ref
        self.createdAt = createdAt
        self.reactions = reactions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            conversation: try container.decodeIfPresent(String.self, forKey: .conversation) ?? "",
            author: try container.decode(String.self, forKey: .author),
            kind: Kind(rawValue: try container.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .message,
            text: try container.decode(String.self, forKey: .text),
            replyTo: try container.decodeIfPresent(String.self, forKey: .replyTo),
            mentions: try container.decodeIfPresent([String].self, forKey: .mentions) ?? [],
            viaVoice: try container.decodeIfPresent(Bool.self, forKey: .viaVoice) ?? false,
            ref: try container.decodeIfPresent(Ref.self, forKey: .ref),
            createdAt: try container.decode(String.self, forKey: .createdAt),
            reactions: try container.decodeIfPresent([String].self, forKey: .reactions) ?? []
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, conversation, author, kind, text, mentions, ref, reactions
        case replyTo = "reply_to"
        case viaVoice = "via_voice"
        case createdAt = "created_at"
    }

    /// The employee who wrote it, when an employee did.
    public var employeeID: String? {
        author.hasPrefix("employee:") ? String(author.dropFirst("employee:".count)) : nil
    }

    public var isFromPerson: Bool { author.hasPrefix("person:") }
    public var isEvent: Bool { kind == .event }
    public var date: Date? { ServerDate.parse(createdAt) }
}

/// `GET …/conversations`: a started conversation, its newest message and how many are unread.
public struct ConversationSummary: Equatable, Sendable, Decodable {
    public let key: String
    public let last: ConversationMessage?
    public let unread: Int
    /// The signed-in person follows it: a work thread they hear each milestone of.
    public let following: Bool

    public init(key: String, last: ConversationMessage?, unread: Int, following: Bool = false) {
        self.key = key
        self.last = last
        self.unread = unread
        self.following = following
    }
}

/// `GET …/conversations/:key`: up to 50 messages, oldest first, and who answers next.
public struct ConversationPage: Equatable, Sendable, Decodable {
    public static let size = 50

    public let messages: [ConversationMessage]
    /// Who answers the owner's next message when it neither replies to nor mentions anyone.
    public let respondent: String?

    public init(messages: [ConversationMessage], respondent: String?) {
        self.messages = messages
        self.respondent = respondent
    }
}

/// A message the owner posts. The id makes retries safe.
public struct NewMessage: Equatable, Sendable, Encodable {
    public let id: String
    public let text: String
    public let replyTo: String?
    public let mentions: [String]
    public let viaVoice: Bool

    public init(id: String, text: String, replyTo: String? = nil, mentions: [String] = [], viaVoice: Bool = false) {
        self.id = id
        self.text = text
        self.replyTo = replyTo
        self.mentions = mentions
        self.viaVoice = viaVoice
    }

    enum CodingKeys: String, CodingKey { case id, text, replyTo, mentions, viaVoice }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(replyTo, forKey: .replyTo)
        if !mentions.isEmpty { try container.encode(mentions, forKey: .mentions) }
        try container.encode(viaVoice, forKey: .viaVoice)
    }
}

/// The posted message and the employees who will answer it.
public struct PostedMessage: Equatable, Sendable, Decodable {
    public let message: ConversationMessage
    public let recipients: [String]

    public init(message: ConversationMessage, recipients: [String]) {
        self.message = message
        self.recipients = recipients
    }

    enum CodingKeys: String, CodingKey {
        case message
        case recipients = "to"
    }
}

extension DevysHTTPClient {
    /// Every started conversation of the business, with its newest message and unread count.
    public func conversations(_ session: DeviceSession, businessID: String) async throws -> [ConversationSummary] {
        struct Page: Decodable { let conversations: [ConversationSummary] }
        let page: Page = try await send(conversationRequest(session, businessID: businessID, key: nil))
        return page.conversations
    }

    /// The newest page of a conversation; `before` (a message id) pages back.
    public func conversation(_ session: DeviceSession, businessID: String, key: ConversationKey, before: String? = nil) async throws -> ConversationPage {
        var request = conversationRequest(session, businessID: businessID, key: key)
        if let before { request.url?.append(queryItems: [URLQueryItem(name: "before", value: before)]) }
        return try await send(request)
    }

    /// Posts the owner's message; 409 means everyone who would answer is paused.
    public func postMessage(_ session: DeviceSession, businessID: String, key: ConversationKey, _ message: NewMessage) async throws -> PostedMessage {
        var request = conversationRequest(session, businessID: businessID, key: key, action: "messages", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(message)
        return try await send(request)
    }

    /// Marks the conversation read up to `seen`, the created_at of the newest message seen.
    public func markRead(_ session: DeviceSession, businessID: String, key: ConversationKey, at seen: String) async throws {
        var request = conversationRequest(session, businessID: businessID, key: key, action: "read", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(ReadPosition(seen: seen))
        _ = try await raw(request)
    }

    /// Starts or stops following a conversation.
    public func follow(_ session: DeviceSession, businessID: String, key: ConversationKey, following: Bool) async throws {
        var request = conversationRequest(session, businessID: businessID, key: key, action: "follow", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(FollowBody(following: following))
        _ = try await raw(request)
    }

    /// The key goes in the path percent-encoded, so ":" survives every proxy.
    private func conversationRequest(
        _ session: DeviceSession,
        businessID: String,
        key: ConversationKey?,
        action: String? = nil,
        method: String = "GET"
    ) -> URLRequest {
        var request = authorized(session, path: "api/businesses/\(businessID)/conversations", method: method)
        guard let key, let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return request }
        components.percentEncodedPath += "/" + key.pathSegment + (action.map { "/\($0)" } ?? "")
        request.url = components.url
        return request
    }
}

/// `POST …/read`: the created_at of the newest message seen.
private struct FollowBody: Encodable {
    let following: Bool

    enum CodingKeys: String, CodingKey { case following = "on" }
}

private struct ReadPosition: Encodable {
    let seen: String

    enum CodingKeys: String, CodingKey { case seen = "at" }
}
