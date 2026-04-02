import Foundation

public struct HealthResponse: Codable, Sendable, Equatable {
    public let status: String
    public let serverName: String
    public let version: String
    public let timestamp: Date

    public init(
        status: String = "ok",
        serverName: String,
        version: String,
        timestamp: Date = .now
    ) {
        self.status = status
        self.serverName = serverName
        self.version = version
        self.timestamp = timestamp
    }
}
