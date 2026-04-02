import Foundation

public struct HarnessType:
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

    public static let codex: Self = "codex"
    public static let claudeCode: Self = "claude-code"
}

public struct SessionStatus:
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

    public static let idle: Self = "idle"
    public static let streaming: Self = "streaming"
    public static let waitingInput: Self = "waiting-input"
    public static let archived: Self = "archived"
    public static let failed: Self = "failed"
}

public struct Session: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let harnessType: HarnessType
    public let model: String
    public let workspaceRoot: String?
    public let branch: String?
    public let status: SessionStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let archivedAt: Date?
    public let lastMessagePreview: String?
    public let unreadCount: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        harnessType: HarnessType,
        model: String,
        workspaceRoot: String? = nil,
        branch: String? = nil,
        status: SessionStatus = .idle,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil,
        lastMessagePreview: String? = nil,
        unreadCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.harnessType = harnessType
        self.model = model
        self.workspaceRoot = workspaceRoot
        self.branch = branch
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.lastMessagePreview = lastMessagePreview
        self.unreadCount = unreadCount
    }
}
