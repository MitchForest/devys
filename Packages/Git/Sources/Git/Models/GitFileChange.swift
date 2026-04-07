// GitFileChange.swift
// Model for a file change in git status.

import Foundation

/// Status of a file in the git working tree or staging area.
public enum GitFileStatus: String, Sendable, Equatable, Hashable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case unmerged = "U"
    
    /// SF Symbol name for the status.
    public var iconName: String {
        switch self {
        case .modified: return "pencil.circle.fill"
        case .added: return "plus.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .copied: return "doc.on.doc.fill"
        case .untracked: return "questionmark.circle.fill"
        case .ignored: return "eye.slash.circle.fill"
        case .unmerged: return "exclamationmark.triangle.fill"
        }
    }
}

/// A file change in the git repository.
public struct GitFileChange: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let status: GitFileStatus
    public let isStaged: Bool
    
    public init(
        path: String,
        status: GitFileStatus,
        isStaged: Bool
    ) {
        self.id = "\(isStaged ? "staged" : "unstaged"):\(path)"
        self.path = path
        self.status = status
        self.isStaged = isStaged
    }
    
    /// The filename without directory path.
    public var filename: String {
        (path as NSString).lastPathComponent
    }
    
    /// The directory containing the file.
    public var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "." : dir
    }
    
}
