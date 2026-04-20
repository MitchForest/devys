import ACPClientKit
import Foundation
import RemoteCore
import Split
import Workspace

public typealias ChatSessionID = ACPSessionID

public enum ChatAttachment: Equatable, Sendable, Identifiable {
    case file(url: URL)
    case gitDiff(path: String, isStaged: Bool)
    case image(url: URL)
    case url(URL)
    case snippet(language: String?, content: String)

    public var id: String {
        switch self {
        case .file(let url):
            "file:\(url.absoluteString)"
        case .gitDiff(let path, let isStaged):
            "gitDiff:\(path):\(isStaged)"
        case .image(let url):
            "image:\(url.absoluteString)"
        case .url(let url):
            "url:\(url.absoluteString)"
        case .snippet(let language, let content):
            "snippet:\(language ?? "plain"):\(content)"
        }
    }
}

public enum WorkspaceCreationMode: String, CaseIterable, Equatable, Sendable, Identifiable {
    case newBranch = "New Branch"
    case existingBranch = "Existing Branch"
    case pullRequest = "Pull Request"
    case importedWorktree = "Imported Worktree"

    public var id: String { rawValue }
}

public struct WorkspaceCreationPresentation: Equatable, Sendable, Identifiable {
    public var repository: Repository
    public var mode: WorkspaceCreationMode

    public init(
        repository: Repository,
        mode: WorkspaceCreationMode
    ) {
        self.repository = repository
        self.mode = mode
    }

    public var id: String {
        "\(repository.id)|\(mode.rawValue)"
    }
}

public struct AddRepositoryPresentation: Equatable, Sendable, Identifiable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

public struct ChatLaunchPresentation: Equatable, Sendable, Identifiable {
    public var workspaceID: Workspace.ID
    public var initialAttachments: [ChatAttachment]
    public var preferredPaneID: PaneID?
    public var pendingSessionID: ChatSessionID?
    public var pendingTabID: TabID?

    public init(
        workspaceID: Workspace.ID,
        initialAttachments: [ChatAttachment] = [],
        preferredPaneID: PaneID? = nil,
        pendingSessionID: ChatSessionID? = nil,
        pendingTabID: TabID? = nil
    ) {
        self.workspaceID = workspaceID
        self.initialAttachments = initialAttachments
        self.preferredPaneID = preferredPaneID
        self.pendingSessionID = pendingSessionID
        self.pendingTabID = pendingTabID
    }

    public var id: String {
        if let pendingSessionID {
            return "\(workspaceID)|\(pendingSessionID.rawValue)"
        }
        return workspaceID
    }
}

public struct RemoteRepositoryPresentation: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var authority: RemoteRepositoryAuthority?

    public init(
        authority: RemoteRepositoryAuthority? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.authority = authority
    }
}

public struct RemoteWorktreeCreationPresentation: Equatable, Sendable, Identifiable {
    public var draft: RemoteWorktreeDraft

    public init(draft: RemoteWorktreeDraft) {
        self.draft = draft
    }

    public var id: UUID {
        draft.id
    }
}
