import Foundation

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case created
    case running
    case stopping
    case stopped
    case completed
    case failed
}

public struct SessionSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let status: SessionStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let workspacePath: String?

    public init(
        id: String = UUID().uuidString,
        status: SessionStatus = .created,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        workspacePath: String? = nil
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspacePath = workspacePath
    }
}
