import Foundation

public enum GitChangeStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case unmerged = "U"

}

public struct GitFileChange: Identifiable, Equatable, Hashable, Sendable {
    public let path: String
    public let previousPath: String?
    public let status: GitChangeStatus
    public let isStaged: Bool

    public init(
        path: String,
        previousPath: String? = nil,
        status: GitChangeStatus,
        isStaged: Bool
    ) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.isStaged = isStaged
    }

    public var id: String {
        "\(isStaged ? "staged" : "unstaged"):\(path)"
    }

    public var filename: String {
        (path as NSString).lastPathComponent
    }

    public var directory: String {
        let directory = (path as NSString).deletingLastPathComponent
        return directory.isEmpty ? "." : directory
    }
}

public enum GitError: LocalizedError, Equatable, Sendable {
    case notRepository
    case commandFailed(message: String)
    case unsupportedOperation(String)
    case invalidPatch(String)

    public var errorDescription: String? {
        switch self {
        case .notRepository:
            "No git repository was found."
        case .commandFailed(let message):
            message
        case .unsupportedOperation(let message):
            message
        case .invalidPatch(let message):
            message
        }
    }
}

public struct GitFileDiscarder: Sendable {
    public var discard: @Sendable (URL) async throws -> Void

    public init(discard: @escaping @Sendable (URL) async throws -> Void) {
        self.discard = discard
    }

    public static let removeImmediately = GitFileDiscarder { url in
        try FileManager.default.removeItem(at: url)
    }
}
