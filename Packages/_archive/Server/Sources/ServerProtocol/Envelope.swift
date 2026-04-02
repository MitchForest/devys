import Foundation

public struct RequestEnvelope: Codable, Sendable, Equatable {
    public let requestID: String
    public let type: String
    public let payload: JSONValue?

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case type
        case payload
    }

    public init(
        requestID: String = UUID().uuidString,
        type: String,
        payload: JSONValue? = nil
    ) {
        self.requestID = requestID
        self.type = type
        self.payload = payload
    }
}

public struct ResponseEnvelope: Codable, Sendable, Equatable {
    public let requestID: String
    public let ok: Bool
    public let payload: JSONValue?
    public let error: ErrorEnvelope?

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case ok
        case payload
        case error
    }

    public init(
        requestID: String,
        ok: Bool,
        payload: JSONValue? = nil,
        error: ErrorEnvelope? = nil
    ) {
        self.requestID = requestID
        self.ok = ok
        self.payload = payload
        self.error = error
    }
}

public struct ErrorEnvelope: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let details: JSONValue?

    public init(code: String, message: String, details: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}
