import Foundation

public struct StreamCursor: Codable, Sendable, Equatable {
    public let sessionID: String
    public let sequence: UInt64

    enum CodingKeys: String, CodingKey {
        case sessionID = "sessionId"
        case sequence
    }

    public init(sessionID: String, sequence: UInt64) {
        self.sessionID = sessionID
        self.sequence = sequence
    }
}
