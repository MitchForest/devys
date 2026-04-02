import Foundation

public struct ServerCapabilitiesResponse: Codable, Sendable, Equatable {
    public let tmuxAvailable: Bool
    public let claudeAvailable: Bool
    public let codexAvailable: Bool

    public init(
        tmuxAvailable: Bool,
        claudeAvailable: Bool,
        codexAvailable: Bool
    ) {
        self.tmuxAvailable = tmuxAvailable
        self.claudeAvailable = claudeAvailable
        self.codexAvailable = codexAvailable
    }
}
