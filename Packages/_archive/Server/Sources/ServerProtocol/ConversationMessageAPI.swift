import ChatCore
import Foundation

public struct ConversationUserMessageRequest: Codable, Sendable, Equatable {
    public let text: String
    public let clientMessageID: String?

    enum CodingKeys: String, CodingKey {
        case text
        case clientMessageID = "clientMessageId"
    }

    public init(text: String, clientMessageID: String? = nil) {
        self.text = text
        self.clientMessageID = clientMessageID
    }
}

public struct ConversationUserMessageResponse: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let message: Message?

    public init(accepted: Bool, message: Message? = nil) {
        self.accepted = accepted
        self.message = message
    }
}

public enum ConversationDecision: String, Codable, Sendable, CaseIterable {
    case approve
    case deny
}

public struct ConversationApprovalResponseRequest: Codable, Sendable, Equatable {
    public let requestID: String
    public let decision: ConversationDecision
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case decision
        case note
    }

    public init(requestID: String, decision: ConversationDecision, note: String? = nil) {
        self.requestID = requestID
        self.decision = decision
        self.note = note
    }
}

public struct ConversationUserInputResponseRequest: Codable, Sendable, Equatable {
    public let requestID: String
    public let value: String

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case value
    }

    public init(requestID: String, value: String) {
        self.requestID = requestID
        self.value = value
    }
}

public struct ConversationActionResponse: Codable, Sendable, Equatable {
    public let accepted: Bool

    public init(accepted: Bool) {
        self.accepted = accepted
    }
}
