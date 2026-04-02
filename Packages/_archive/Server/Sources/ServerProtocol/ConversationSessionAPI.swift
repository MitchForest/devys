import ChatCore
import Foundation

public struct SessionListRequest: Codable, Sendable, Equatable {
    public let includeArchived: Bool
    public let limit: Int?

    public init(includeArchived: Bool = false, limit: Int? = nil) {
        self.includeArchived = includeArchived
        self.limit = limit
    }
}

public struct SessionListResponse: Codable, Sendable, Equatable {
    public let sessions: [Session]

    public init(sessions: [Session]) {
        self.sessions = sessions
    }
}

public struct SessionCreateRequest: Codable, Sendable, Equatable {
    public let title: String
    public let harnessType: HarnessType
    public let model: String
    public let workspaceRoot: String?
    public let branch: String?

    public init(
        title: String,
        harnessType: HarnessType,
        model: String,
        workspaceRoot: String? = nil,
        branch: String? = nil
    ) {
        self.title = title
        self.harnessType = harnessType
        self.model = model
        self.workspaceRoot = workspaceRoot
        self.branch = branch
    }
}

public struct SessionCreateResponse: Codable, Sendable, Equatable {
    public let session: Session

    public init(session: Session) {
        self.session = session
    }
}

public struct SessionRenameRequest: Codable, Sendable, Equatable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

public struct SessionRenameResponse: Codable, Sendable, Equatable {
    public let session: Session

    public init(session: Session) {
        self.session = session
    }
}

public struct SessionArchiveRequest: Codable, Sendable, Equatable {
    public let archived: Bool

    public init(archived: Bool = true) {
        self.archived = archived
    }
}

public struct SessionArchiveResponse: Codable, Sendable, Equatable {
    public let session: Session

    public init(session: Session) {
        self.session = session
    }
}

public struct SessionDeleteResponse: Codable, Sendable, Equatable {
    public let deleted: Bool
    public let sessionID: String
    public let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case deleted
        case sessionID = "sessionId"
        case deletedAt
    }

    public init(deleted: Bool, sessionID: String, deletedAt: Date = .now) {
        self.deleted = deleted
        self.sessionID = sessionID
        self.deletedAt = deletedAt
    }
}

public struct SessionResumeResponse: Codable, Sendable, Equatable {
    public let session: Session
    public let messages: [Message]
    public let nextCursor: StreamCursor?

    public init(
        session: Session,
        messages: [Message],
        nextCursor: StreamCursor? = nil
    ) {
        self.session = session
        self.messages = messages
        self.nextCursor = nextCursor
    }
}
