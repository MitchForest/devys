import Foundation

public struct CreateSessionRequest: Codable, Sendable, Equatable {
    public let workspacePath: String?

    public init(workspacePath: String? = nil) {
        self.workspacePath = workspacePath
    }
}

public struct CreateSessionResponse: Codable, Sendable, Equatable {
    public let session: SessionSummary

    public init(session: SessionSummary) {
        self.session = session
    }
}

public struct RunSessionRequest: Codable, Sendable, Equatable {
    public let command: String
    public let arguments: [String]
    public let workingDirectory: String?
    public let environment: [String: String]?

    public init(
        command: String,
        arguments: [String] = [],
        workingDirectory: String? = nil,
        environment: [String: String]? = nil
    ) {
        self.command = command
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
    }
}

public struct RunSessionResponse: Codable, Sendable, Equatable {
    public let accepted: Bool
    public let session: SessionSummary

    public init(accepted: Bool, session: SessionSummary) {
        self.accepted = accepted
        self.session = session
    }
}

public struct StopSessionResponse: Codable, Sendable, Equatable {
    public let session: SessionSummary

    public init(session: SessionSummary) {
        self.session = session
    }
}

public struct ListSessionsResponse: Codable, Sendable, Equatable {
    public let sessions: [SessionSummary]

    public init(sessions: [SessionSummary]) {
        self.sessions = sessions
    }
}
