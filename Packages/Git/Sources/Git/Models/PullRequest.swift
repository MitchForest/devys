// PullRequest.swift
// Model for GitHub pull requests.

import Foundation

/// State of a pull request.
public enum PRState: String, Sendable, Codable {
    case open = "OPEN"
    case closed = "CLOSED"
    case merged = "MERGED"
}

/// Status of CI checks on a PR.
public enum ChecksStatus: String, Sendable {
    case pending
    case passing
    case failing
}

/// Review decision on a PR.
public enum ReviewDecision: String, Sendable, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

/// A GitHub pull request.
public struct PullRequest: Identifiable, Equatable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: PRState
    public let author: String
    public let headBranch: String
    public let baseBranch: String
    public let createdAt: Date
    public let updatedAt: Date
    public let isDraft: Bool
    public let checksStatus: ChecksStatus?
    public let reviewDecision: ReviewDecision?
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int
    
    public init(
        id: Int,
        number: Int,
        title: String,
        body: String?,
        state: PRState,
        author: String,
        headBranch: String,
        baseBranch: String,
        createdAt: Date,
        updatedAt: Date,
        isDraft: Bool,
        checksStatus: ChecksStatus?,
        reviewDecision: ReviewDecision?,
        additions: Int,
        deletions: Int,
        changedFiles: Int
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.body = body
        self.state = state
        self.author = author
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDraft = isDraft
        self.checksStatus = checksStatus
        self.reviewDecision = reviewDecision
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
    }
    
    /// Relative time since creation.
    var relativeCreatedAt: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

/// A file changed in a pull request.
struct PRFile: Identifiable, Equatable, Sendable {
    var id: String { path }
    
    let path: String
    let status: PRFileStatus
    let additions: Int
    let deletions: Int
    let patch: String?
    
    init(
        path: String,
        status: PRFileStatus,
        additions: Int,
        deletions: Int,
        patch: String?
    ) {
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }
    
    /// The filename without directory path.
    var filename: String {
        (path as NSString).lastPathComponent
    }
}

/// Status of a file in a PR.
enum PRFileStatus: String, Sendable {
    case added
    case modified
    case deleted
    case renamed
    case copied
}

/// Merge method for pull requests.
enum MergeMethod: String, Sendable {
    case merge
    case squash
    case rebase
    
    var label: String {
        switch self {
        case .merge: return "Create a merge commit"
        case .squash: return "Squash and merge"
        case .rebase: return "Rebase and merge"
        }
    }
}

/// Filter for PR list.
enum PRStateFilter: String, Sendable {
    case open
    case closed
    case merged
    case all
}
