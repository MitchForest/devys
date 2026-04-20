import ACPClientKit
import Foundation
import Workspace

public struct HostedTerminalViewportSizeRecord: Codable, Equatable, Sendable {
    public let cols: Int
    public let rows: Int

    public init(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
    }
}

public struct HostedTerminalSessionRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let workspaceID: Workspace.ID
    public let workingDirectory: URL?
    public let launchCommand: String?
    public let viewportSize: HostedTerminalViewportSizeRecord?
    public let processID: Int32?
    public let createdAt: Date

    public init(
        id: UUID,
        workspaceID: Workspace.ID,
        workingDirectory: URL?,
        launchCommand: String?,
        viewportSize: HostedTerminalViewportSizeRecord? = nil,
        processID: Int32? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.workingDirectory = workingDirectory
        self.launchCommand = launchCommand
        self.viewportSize = viewportSize
        self.processID = processID
        self.createdAt = createdAt
    }
}

public struct PersistedChatSessionRecord: Codable, Equatable, Sendable {
    public let sessionID: String
    public let kind: ACPAgentKind
    public let title: String?
    public let subtitle: String?

    public init(
        sessionID: String,
        kind: ACPAgentKind,
        title: String? = nil,
        subtitle: String? = nil
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
    }
}

public enum PersistedWorkspaceSidebarMode: String, Codable, Equatable, Sendable {
    case files
    case agents

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.files.rawValue, "changes", "ports":
            self = .files
        case Self.agents.rawValue:
            self = .agents
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid workspace sidebar mode: \(rawValue)"
            )
        }
    }
}

public enum PersistedWorkspaceTabRecord: Codable, Equatable, Sendable {
    case terminal(hostedSessionID: UUID)
    case browser(id: UUID, url: URL)
    case chat(PersistedChatSessionRecord)
    case editor(fileURL: URL)
    case gitDiff(path: String, isStaged: Bool)
    case workflowDefinition(definitionID: String)
    case workflowRun(runID: UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case hostedSessionID
        case browserID
        case browserURL
        case chatSession
        case fileURL
        case path
        case isStaged
        case definitionID
        case runID
    }

    private enum Kind: String, Codable {
        case terminal
        case browser
        case chat
        case agent
        case editor
        case gitDiff
        case workflowDefinition
        case workflowRun
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .terminal:
            self = .terminal(
                hostedSessionID: try container.decode(UUID.self, forKey: .hostedSessionID)
            )
        case .browser:
            self = .browser(
                id: try container.decode(UUID.self, forKey: .browserID),
                url: try container.decode(URL.self, forKey: .browserURL)
            )
        case .chat, .agent:
            self = .chat(
                try container.decode(PersistedChatSessionRecord.self, forKey: .chatSession)
            )
        case .editor:
            self = .editor(
                fileURL: try container.decode(URL.self, forKey: .fileURL)
            )
        case .gitDiff:
            self = .gitDiff(
                path: try container.decode(String.self, forKey: .path),
                isStaged: try container.decode(Bool.self, forKey: .isStaged)
            )
        case .workflowDefinition:
            self = .workflowDefinition(
                definitionID: try container.decode(String.self, forKey: .definitionID)
            )
        case .workflowRun:
            self = .workflowRun(
                runID: try container.decode(UUID.self, forKey: .runID)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .terminal(let hostedSessionID):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(hostedSessionID, forKey: .hostedSessionID)
        case .browser(let id, let url):
            try container.encode(Kind.browser, forKey: .kind)
            try container.encode(id, forKey: .browserID)
            try container.encode(url, forKey: .browserURL)
        case .chat(let record):
            try container.encode(Kind.chat, forKey: .kind)
            try container.encode(record, forKey: .chatSession)
        case .editor(let fileURL):
            try container.encode(Kind.editor, forKey: .kind)
            try container.encode(fileURL, forKey: .fileURL)
        case .gitDiff(let path, let isStaged):
            try container.encode(Kind.gitDiff, forKey: .kind)
            try container.encode(path, forKey: .path)
            try container.encode(isStaged, forKey: .isStaged)
        case .workflowDefinition(let definitionID):
            try container.encode(Kind.workflowDefinition, forKey: .kind)
            try container.encode(definitionID, forKey: .definitionID)
        case .workflowRun(let runID):
            try container.encode(Kind.workflowRun, forKey: .kind)
            try container.encode(runID, forKey: .runID)
        }
    }
}

public indirect enum PersistedWorkspaceLayoutTree: Codable, Equatable, Sendable {
    case pane(selectedTabIndex: Int?, tabs: [PersistedWorkspaceTabRecord])
    case split(
        orientation: String,
        dividerPosition: Double,
        first: PersistedWorkspaceLayoutTree,
        second: PersistedWorkspaceLayoutTree
    )

    private enum CodingKeys: String, CodingKey {
        case kind
        case selectedTabIndex
        case tabs
        case orientation
        case dividerPosition
        case first
        case second
    }

    private enum Kind: String, Codable {
        case pane
        case split
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .pane:
            self = .pane(
                selectedTabIndex: try container.decodeIfPresent(Int.self, forKey: .selectedTabIndex),
                tabs: try container.decode([PersistedWorkspaceTabRecord].self, forKey: .tabs)
            )
        case .split:
            self = .split(
                orientation: try container.decode(String.self, forKey: .orientation),
                dividerPosition: try container.decode(Double.self, forKey: .dividerPosition),
                first: try container.decode(PersistedWorkspaceLayoutTree.self, forKey: .first),
                second: try container.decode(PersistedWorkspaceLayoutTree.self, forKey: .second)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pane(let selectedTabIndex, let tabs):
            try container.encode(Kind.pane, forKey: .kind)
            try container.encodeIfPresent(selectedTabIndex, forKey: .selectedTabIndex)
            try container.encode(tabs, forKey: .tabs)
        case .split(let orientation, let dividerPosition, let first, let second):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(orientation, forKey: .orientation)
            try container.encode(dividerPosition, forKey: .dividerPosition)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }
}

public struct PersistedWorkspaceLayoutState: Codable, Equatable, Sendable, Identifiable {
    public let workspaceID: Workspace.ID
    public let sidebarMode: PersistedWorkspaceSidebarMode
    public let tree: PersistedWorkspaceLayoutTree

    public init(
        workspaceID: Workspace.ID,
        sidebarMode: PersistedWorkspaceSidebarMode,
        tree: PersistedWorkspaceLayoutTree
    ) {
        self.workspaceID = workspaceID
        self.sidebarMode = sidebarMode
        self.tree = tree
    }

    public var id: Workspace.ID {
        workspaceID
    }

    public var persistedTabs: [PersistedWorkspaceTabRecord] {
        tree.persistedTabs
    }
}

public struct WindowRelaunchSnapshot: Codable, Equatable, Sendable {
    public var repositoryRootURLs: [URL]
    public var selectedRepositoryID: Repository.ID?
    public var selectedWorkspaceID: Workspace.ID?
    public var hostedSessions: [HostedTerminalSessionRecord]
    public var workspaceStates: [PersistedWorkspaceLayoutState]

    public init(
        repositoryRootURLs: [URL],
        selectedRepositoryID: Repository.ID?,
        selectedWorkspaceID: Workspace.ID?,
        hostedSessions: [HostedTerminalSessionRecord],
        workspaceStates: [PersistedWorkspaceLayoutState]
    ) {
        self.repositoryRootURLs = repositoryRootURLs
        self.selectedRepositoryID = selectedRepositoryID
        self.selectedWorkspaceID = selectedWorkspaceID
        self.hostedSessions = hostedSessions
        self.workspaceStates = workspaceStates
    }

    public var hasRepositories: Bool {
        !repositoryRootURLs.isEmpty
    }

    public static let empty = WindowRelaunchSnapshot(
        repositoryRootURLs: [],
        selectedRepositoryID: nil,
        selectedWorkspaceID: nil,
        hostedSessions: [],
        workspaceStates: []
    )
}

public struct RelaunchSettingsSnapshot: Equatable, Sendable {
    public var restoreRepositoriesOnLaunch: Bool
    public var restoreSelectedWorkspace: Bool
    public var restoreWorkspaceLayoutAndTabs: Bool
    public var restoreTerminalSessions: Bool
    public var restoreChatSessions: Bool

    public init(
        restoreRepositoriesOnLaunch: Bool,
        restoreSelectedWorkspace: Bool,
        restoreWorkspaceLayoutAndTabs: Bool,
        restoreTerminalSessions: Bool,
        restoreChatSessions: Bool
    ) {
        self.restoreRepositoriesOnLaunch = restoreRepositoriesOnLaunch
        self.restoreSelectedWorkspace = restoreSelectedWorkspace
        self.restoreWorkspaceLayoutAndTabs = restoreWorkspaceLayoutAndTabs
        self.restoreTerminalSessions = restoreTerminalSessions
        self.restoreChatSessions = restoreChatSessions
    }
}

public extension PersistedWorkspaceLayoutTree {
    var persistedTabs: [PersistedWorkspaceTabRecord] {
        switch self {
        case .pane(_, let tabs):
            tabs
        case .split(_, _, let first, let second):
            first.persistedTabs + second.persistedTabs
        }
    }
}
