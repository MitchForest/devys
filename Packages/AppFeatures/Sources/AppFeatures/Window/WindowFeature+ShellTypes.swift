import Foundation
import Split
import Workspace

public extension WindowFeature {
    enum Sidebar: String, CaseIterable, Equatable, Sendable {
        case files
        case agents
    }

    enum Sheet: String, CaseIterable, Equatable, Sendable {
        case commandPalette
        case settings
        case workspaceCreation
        case gitCommit
        case pullRequest
        case notifications
    }

    enum SearchMode: String, Equatable, Sendable {
        case commands
        case files
        case textSearch
    }

    enum EditorCommand: Equatable, Sendable {
        case find
        case save
        case saveAs
        case saveAll
    }

    enum TabOpenMode: Equatable, Sendable {
        case preview
        case permanent
    }

    enum WorkspaceCommand: Equatable, Sendable {
        case openAgents
        case launchShell
        case launchClaude
        case launchCodex
        case runWorkspaceProfile
        case jumpToLatestUnreadWorkspace
    }

    struct EditorCommandRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var command: EditorCommand

        public init(
            command: EditorCommand,
            id: UUID = UUID()
        ) {
            self.id = id
            self.command = command
        }
    }

    struct InitializeRepositoryRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var repositoryID: Repository.ID

        public init(
            repositoryID: Repository.ID,
            id: UUID = UUID()
        ) {
            self.id = id
            self.repositoryID = repositoryID
        }
    }

    struct WorkspaceDiscardRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var workspaceID: Workspace.ID
        public var repositoryID: Repository.ID

        public init(
            workspaceID: Workspace.ID,
            repositoryID: Repository.ID,
            id: UUID = UUID()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.repositoryID = repositoryID
        }
    }

    struct WorkspaceCommandRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var command: WorkspaceCommand

        public init(
            command: WorkspaceCommand,
            id: UUID = UUID()
        ) {
            self.id = id
            self.command = command
        }
    }

    struct SearchPresentation: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var mode: SearchMode
        public var initialQuery: String

        public init(
            mode: SearchMode,
            initialQuery: String = "",
            id: UUID = UUID()
        ) {
            self.id = id
            self.mode = mode
            self.initialQuery = initialQuery
        }
    }

    struct NavigatorRevealRequest: Equatable, Identifiable, Sendable {
        public let workspaceID: Workspace.ID
        public let token: UUID

        public init(
            workspaceID: Workspace.ID,
            token: UUID = UUID()
        ) {
            self.workspaceID = workspaceID
            self.token = token
        }

        public var id: UUID {
            token
        }
    }

    struct WorkspaceShell: Equatable, Sendable {
        public var activeSidebar: Sidebar?
        public var tabContents: [TabID: WorkspaceTabContent]
        public var focusedPaneID: PaneID?
        public var layout: WorkspaceLayout?

        public init(
            activeSidebar: Sidebar? = .files,
            tabContents: [TabID: WorkspaceTabContent] = [:],
            focusedPaneID: PaneID? = nil,
            layout: WorkspaceLayout? = nil
        ) {
            self.activeSidebar = activeSidebar
            self.tabContents = tabContents
            self.focusedPaneID = focusedPaneID
            self.layout = layout
        }
    }

    struct WorkspaceLayout: Equatable, Sendable, Codable {
        public var root: WorkspaceLayoutNode

        public init(root: WorkspaceLayoutNode = .pane(WorkspacePaneLayout())) {
            self.root = root
        }

        public var allPaneIDs: [PaneID] {
            root.allPaneIDs
        }

        public func paneLayout(for paneID: PaneID) -> WorkspacePaneLayout? {
            root.paneLayout(for: paneID)
        }

        public var focusedFallbackPaneID: PaneID? {
            root.allPaneIDs.first
        }

        public func selectedTabID(in paneID: PaneID?) -> TabID? {
            guard let paneID else { return nil }
            return paneLayout(for: paneID)?.selectedTabID
        }

        public func paneID(containing tabID: TabID) -> PaneID? {
            root.paneID(containing: tabID)
        }
    }

    indirect enum WorkspaceLayoutNode: Equatable, Sendable, Codable {
        case pane(WorkspacePaneLayout)
        case split(WorkspaceSplitLayout)

        public var allPaneIDs: [PaneID] {
            switch self {
            case .pane(let pane):
                [pane.id]
            case .split(let split):
                split.first.allPaneIDs + split.second.allPaneIDs
            }
        }

        public func paneLayout(for paneID: PaneID) -> WorkspacePaneLayout? {
            switch self {
            case .pane(let pane):
                pane.id == paneID ? pane : nil
            case .split(let split):
                split.first.paneLayout(for: paneID) ?? split.second.paneLayout(for: paneID)
            }
        }

        public func paneID(containing tabID: TabID) -> PaneID? {
            switch self {
            case .pane(let pane):
                pane.tabIDs.contains(tabID) ? pane.id : nil
            case .split(let split):
                split.first.paneID(containing: tabID) ?? split.second.paneID(containing: tabID)
            }
        }
    }

    struct WorkspacePaneLayout: Equatable, Sendable, Codable {
        public var id: PaneID
        public var tabIDs: [TabID]
        public var selectedTabID: TabID?
        public var previewTabID: TabID?

        public init(
            id: PaneID = PaneID(),
            tabIDs: [TabID] = [],
            selectedTabID: TabID? = nil,
            previewTabID: TabID? = nil
        ) {
            self.id = id
            self.tabIDs = tabIDs
            self.selectedTabID = selectedTabID
            self.previewTabID = previewTabID
        }
    }

    struct WorkspaceSplitLayout: Equatable, Sendable, Codable {
        public var id: UUID
        public var orientation: Split.SplitOrientation
        public var dividerPosition: Double
        public var first: WorkspaceLayoutNode
        public var second: WorkspaceLayoutNode

        public init(
            id: UUID = UUID(),
            orientation: Split.SplitOrientation,
            dividerPosition: Double = 0.5,
            first: WorkspaceLayoutNode,
            second: WorkspaceLayoutNode
        ) {
            self.id = id
            self.orientation = orientation
            self.dividerPosition = dividerPosition
            self.first = first
            self.second = second
        }
    }

    enum SplitInsertionPosition: String, Equatable, Sendable, Codable {
        case before
        case after
    }

    struct RepositoryCatalogSnapshot: Equatable, Sendable {
        public var repositories: [Repository]
        public var worktreesByRepository: [Repository.ID: [Worktree]]
        public var workspaceStatesByID: [Worktree.ID: WorktreeState]

        public init(
            repositories: [Repository] = [],
            worktreesByRepository: [Repository.ID: [Worktree]] = [:],
            workspaceStatesByID: [Worktree.ID: WorktreeState] = [:]
        ) {
            self.repositories = repositories
            self.worktreesByRepository = worktreesByRepository
            self.workspaceStatesByID = workspaceStatesByID
        }
    }
}
