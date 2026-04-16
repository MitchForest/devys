import ACPClientKit
import Foundation
import Split
import Workspace

public typealias AgentSessionID = ACPSessionID

public enum AgentAttachment: Equatable, Sendable, Identifiable {
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

public struct AgentLaunchPresentation: Equatable, Sendable, Identifiable {
    public var workspaceID: Workspace.ID
    public var initialAttachments: [AgentAttachment]
    public var preferredPaneID: PaneID?
    public var pendingSessionID: AgentSessionID?
    public var pendingTabID: TabID?

    public init(
        workspaceID: Workspace.ID,
        initialAttachments: [AgentAttachment] = [],
        preferredPaneID: PaneID? = nil,
        pendingSessionID: AgentSessionID? = nil,
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
