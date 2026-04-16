import ComposableArchitecture
import Foundation
import Split
import Workspace

public extension WindowFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        public var repositories: [Repository] = []
        public var worktreesByRepository: [Repository.ID: [Worktree]] = [:]
        public var workspaceStatesByID: [Worktree.ID: WorktreeState] = [:]
        public var hostedWorkspaceContentByID: [Workspace.ID: HostedWorkspaceContentState] = [:]
        public var selectedRepositoryID: Repository.ID?
        public var selectedWorkspaceID: Workspace.ID?
        public var workspaceShells: [Workspace.ID: WorkspaceShell] = [:]
        public var selectedTabID: TabID?
        public var activeSidebar: Sidebar? = .files
        public var isSidebarVisible = true
        public var isNavigatorCollapsed = false
        public var navigatorRevealRequest: NavigatorRevealRequest?
        public var activeSheet: Sheet?
        public var searchPresentation: SearchPresentation?
        public var workspaceCreationPresentation: WorkspaceCreationPresentation?
        public var agentLaunchPresentation: AgentLaunchPresentation?
        public var agentSessionLaunchRequest: AgentSessionLaunchRequest?
        public var isGitCommitSheetPresented = false
        public var isCreatePullRequestSheetPresented = false
        public var openRepositoryRequestID: UUID?
        public var editorCommandRequest: EditorCommandRequest?
        public var workspaceTabCloseRequest: WorkspaceTabCloseRequest?
        public var workspaceTransitionRequest: WorkspaceTransitionRequest?
        public var workspaceDiscardRequest: WorkspaceDiscardRequest?
        public var initializeRepositoryRequest: InitializeRepositoryRequest?
        public var saveDefaultLayoutRequestID: UUID?
        public var workspaceCommandRequest: WorkspaceCommandRequest?
        public var focusAgentSessionRequest: FocusAgentSessionRequest?
        public var runProfileLaunchRequest: RunProfileLaunchRequest?
        public var runProfileStopRequest: RunProfileStopRequest?
        public var windowRelaunchRestoreRequest: WindowRelaunchRestoreRequest?
        public var isNotificationsPanelPresented = false
        public var isTerminalActivityNotificationsEnabled = true
        public var isAgentActivityNotificationsEnabled = true
        public var operational = WorkspaceOperationalState()
        public var lastErrorMessage: String?

        public init(
            repositories: [Repository] = [],
            worktreesByRepository: [Repository.ID: [Worktree]] = [:],
            workspaceStatesByID: [Worktree.ID: WorktreeState] = [:],
            hostedWorkspaceContentByID: [Workspace.ID: HostedWorkspaceContentState] = [:],
            selectedRepositoryID: Repository.ID? = nil,
            selectedWorkspaceID: Workspace.ID? = nil,
            workspaceShells: [Workspace.ID: WorkspaceShell] = [:],
            selectedTabID: TabID? = nil,
            activeSidebar: Sidebar? = .files,
            isSidebarVisible: Bool = true,
            isNavigatorCollapsed: Bool = false,
            navigatorRevealRequest: NavigatorRevealRequest? = nil,
            activeSheet: Sheet? = nil,
            searchPresentation: SearchPresentation? = nil,
            workspaceCreationPresentation: WorkspaceCreationPresentation? = nil,
            agentLaunchPresentation: AgentLaunchPresentation? = nil,
            agentSessionLaunchRequest: AgentSessionLaunchRequest? = nil,
            isGitCommitSheetPresented: Bool = false,
            isCreatePullRequestSheetPresented: Bool = false,
            openRepositoryRequestID: UUID? = nil,
            editorCommandRequest: EditorCommandRequest? = nil,
            workspaceTabCloseRequest: WorkspaceTabCloseRequest? = nil,
            workspaceTransitionRequest: WorkspaceTransitionRequest? = nil,
            workspaceDiscardRequest: WorkspaceDiscardRequest? = nil,
            initializeRepositoryRequest: InitializeRepositoryRequest? = nil,
            saveDefaultLayoutRequestID: UUID? = nil,
            workspaceCommandRequest: WorkspaceCommandRequest? = nil,
            focusAgentSessionRequest: FocusAgentSessionRequest? = nil,
            runProfileLaunchRequest: RunProfileLaunchRequest? = nil,
            runProfileStopRequest: RunProfileStopRequest? = nil,
            windowRelaunchRestoreRequest: WindowRelaunchRestoreRequest? = nil,
            isNotificationsPanelPresented: Bool = false,
            isTerminalActivityNotificationsEnabled: Bool = true,
            isAgentActivityNotificationsEnabled: Bool = true,
            operational: WorkspaceOperationalState = WorkspaceOperationalState(),
            lastErrorMessage: String? = nil
        ) {
            self.repositories = repositories
            self.worktreesByRepository = worktreesByRepository
            self.workspaceStatesByID = workspaceStatesByID
            self.hostedWorkspaceContentByID = hostedWorkspaceContentByID
            self.selectedRepositoryID = selectedRepositoryID
            self.selectedWorkspaceID = selectedWorkspaceID
            self.workspaceShells = workspaceShells
            self.selectedTabID = selectedTabID
            self.activeSidebar = activeSidebar
            self.isSidebarVisible = isSidebarVisible
            self.isNavigatorCollapsed = isNavigatorCollapsed
            self.navigatorRevealRequest = navigatorRevealRequest
            self.activeSheet = activeSheet
            self.searchPresentation = searchPresentation
            self.workspaceCreationPresentation = workspaceCreationPresentation
            self.agentLaunchPresentation = agentLaunchPresentation
            self.agentSessionLaunchRequest = agentSessionLaunchRequest
            self.isGitCommitSheetPresented = isGitCommitSheetPresented
            self.isCreatePullRequestSheetPresented = isCreatePullRequestSheetPresented
            self.openRepositoryRequestID = openRepositoryRequestID
            self.editorCommandRequest = editorCommandRequest
            self.workspaceTabCloseRequest = workspaceTabCloseRequest
            self.workspaceTransitionRequest = workspaceTransitionRequest
            self.workspaceDiscardRequest = workspaceDiscardRequest
            self.initializeRepositoryRequest = initializeRepositoryRequest
            self.saveDefaultLayoutRequestID = saveDefaultLayoutRequestID
            self.workspaceCommandRequest = workspaceCommandRequest
            self.focusAgentSessionRequest = focusAgentSessionRequest
            self.runProfileLaunchRequest = runProfileLaunchRequest
            self.runProfileStopRequest = runProfileStopRequest
            self.windowRelaunchRestoreRequest = windowRelaunchRestoreRequest
            self.isNotificationsPanelPresented = isNotificationsPanelPresented
            self.isTerminalActivityNotificationsEnabled = isTerminalActivityNotificationsEnabled
            self.isAgentActivityNotificationsEnabled = isAgentActivityNotificationsEnabled
            self.operational = operational
            self.lastErrorMessage = lastErrorMessage
            normalizeSelection()
        }
    }

    enum Action: Equatable {
        case openRepository(URL)
        case openRepositoryResponse(TaskResult<Repository>)
        case openResolvedRepositories([Repository])
        case refreshRepositories([Repository.ID])
        case setRepositoryCatalogSnapshot(RepositoryCatalogSnapshot)
        case moveRepository(Repository.ID, by: Int)
        case reorderRepository(Repository.ID, toIndex: Int)
        case removeRepository(Repository.ID)
        case setRepositorySourceControl(RepositorySourceControl, for: Repository.ID)
        case setRepositoryDisplayInitials(Repository.ID, String?)
        case setRepositoryDisplaySymbol(Repository.ID, String?)
        case setWorkspacePinned(Workspace.ID, repositoryID: Repository.ID, isPinned: Bool)
        case setWorkspaceArchived(Workspace.ID, repositoryID: Repository.ID, isArchived: Bool)
        case setWorkspaceDisplayName(Workspace.ID, repositoryID: Repository.ID, displayName: String?)
        case removeWorkspaceState(Workspace.ID, repositoryID: Repository.ID)
        case setHostedWorkspaceContent(Workspace.ID, HostedWorkspaceContentState)
        case removeHostedWorkspaceContent(Workspace.ID)
        case selectRepository(Repository.ID?)
        case selectWorkspace(Workspace.ID?)
        case setWorkspaceShell(Workspace.ID, WorkspaceShell)
        case removeWorkspaceShell(Workspace.ID)
        case setWorkspaceTabContent(workspaceID: Workspace.ID, tabID: TabID, content: WorkspaceTabContent)
        case removeWorkspaceTabContent(workspaceID: Workspace.ID, tabID: TabID)
        case clearWorkspaceTabContents(Workspace.ID)
        case openWorkspaceContent(
            workspaceID: Workspace.ID,
            paneID: PaneID,
            content: WorkspaceTabContent,
            mode: TabOpenMode
        )
        case setWorkspaceLayout(workspaceID: Workspace.ID, layout: WorkspaceLayout)
        case insertWorkspaceTab(
            workspaceID: Workspace.ID,
            paneID: PaneID,
            tabID: TabID,
            index: Int?,
            isPreview: Bool
        )
        case selectWorkspaceTab(workspaceID: Workspace.ID, paneID: PaneID, tabID: TabID)
        case closeWorkspaceTab(workspaceID: Workspace.ID, paneID: PaneID, tabID: TabID)
        case reorderWorkspaceTab(
            workspaceID: Workspace.ID,
            paneID: PaneID,
            tabID: TabID,
            sourceIndex: Int,
            destinationIndex: Int
        )
        case moveWorkspaceTab(
            workspaceID: Workspace.ID,
            tabID: TabID,
            sourcePaneID: PaneID,
            destinationPaneID: PaneID,
            index: Int?
        )
        case splitWorkspacePane(
            workspaceID: Workspace.ID,
            paneID: PaneID,
            newPaneID: PaneID,
            orientation: Split.SplitOrientation,
            insertion: SplitInsertionPosition
        )
        case splitWorkspacePaneWithTab(
            workspaceID: Workspace.ID,
            targetPaneID: PaneID,
            newPaneID: PaneID,
            tabID: TabID,
            sourcePaneID: PaneID,
            sourceIndex: Int,
            orientation: Split.SplitOrientation,
            insertion: SplitInsertionPosition
        )
        case closeWorkspacePane(workspaceID: Workspace.ID, paneID: PaneID)
        case setWorkspaceSplitDividerPosition(workspaceID: Workspace.ID, splitID: UUID, position: Double)
        case setWorkspaceFocusedPaneID(workspaceID: Workspace.ID, paneID: PaneID?)
        case setSelectedTabID(TabID?)
        case setWorkspacePanePreviewTabID(workspaceID: Workspace.ID, paneID: PaneID, tabID: TabID?)
        case clearWorkspacePreviewTabID(workspaceID: Workspace.ID, tabID: TabID)
        case restoreSelection(repositoryID: Repository.ID?, workspaceID: Workspace.ID?)
        case showSidebar(Sidebar)
        case setActiveSidebar(Sidebar?)
        case setSidebarVisibility(Bool)
        case toggleSidebarVisibility
        case setNavigatorCollapsed(Bool)
        case toggleNavigatorCollapsed
        case requestNavigatorReveal(Workspace.ID)
        case setNavigatorRevealRequest(NavigatorRevealRequest?)
        case openSearch(SearchMode, initialQuery: String)
        case presentWorkspaceCreation(repositoryID: Repository.ID, mode: WorkspaceCreationMode)
        case setWorkspaceCreationPresentation(WorkspaceCreationPresentation?)
        case setAgentLaunchPresentation(AgentLaunchPresentation?)
        case requestAgentSessionLaunch(AgentSessionLaunchIntent)
        case agentSessionLaunchResolved(AgentSessionLaunchResolution)
        case setAgentSessionLaunchRequest(AgentSessionLaunchRequest?)
        case setGitCommitSheetPresented(Bool)
        case setCreatePullRequestSheetPresented(Bool)
        case requestOpenRepository
        case setOpenRepositoryRequestID(UUID?)
        case requestEditorCommand(EditorCommand)
        case setEditorCommandRequest(EditorCommandRequest?)
        case requestWorkspaceTabClose(WorkspaceTabCloseContext)
        case setWorkspaceTabCloseRequest(WorkspaceTabCloseRequest?)
        case requestRepositorySelection(Repository.ID)
        case requestWorkspaceSelection(repositoryID: Repository.ID, workspaceID: Workspace.ID)
        case requestWorkspaceSelectionAtIndex(Int)
        case requestAdjacentWorkspaceSelection(Int)
        case setWorkspaceTransitionRequest(WorkspaceTransitionRequest?)
        case requestWorkspaceDiscard(workspaceID: Workspace.ID, repositoryID: Repository.ID)
        case setWorkspaceDiscardRequest(WorkspaceDiscardRequest?)
        case requestInitializeRepository(Repository.ID)
        case setInitializeRepositoryRequest(InitializeRepositoryRequest?)
        case requestSaveDefaultLayout
        case setSaveDefaultLayoutRequestID(UUID?)
        case requestWorkspaceCommand(WorkspaceCommand)
        case setWorkspaceCommandRequest(WorkspaceCommandRequest?)
        case requestFocusAgentSession(AgentSessionID)
        case setFocusAgentSessionRequest(FocusAgentSessionRequest?)
        case runProfileLaunchRequestResolved(RunProfileLaunchResolution)
        case setRunProfileLaunchRequest(RunProfileLaunchRequest?)
        case runProfileLaunchCompleted(RunProfileLaunchResult)
        case requestStopWorkspaceRun(Workspace.ID?)
        case setRunProfileStopRequest(RunProfileStopRequest?)
        case runProfileStopCompleted(Workspace.ID)
        case requestWindowRelaunchRestore(force: Bool)
        case windowRelaunchRestoreLoaded(
            TaskResult<WindowRelaunchSnapshot?>,
            settings: RelaunchSettingsSnapshot,
            force: Bool
        )
        case setWindowRelaunchRestoreRequest(WindowRelaunchRestoreRequest?)
        case applyWindowRelaunchRestore(WindowRelaunchRestoreRequest)
        case persistWindowRelaunchSnapshot([HostedTerminalSessionRecord])
        case startWorkspaceOperationalObservation
        case workspaceOperationalSnapshotUpdated(WorkspaceOperationalSnapshot)
        case workspaceAttentionIngressReceived(WorkspaceAttentionIngressPayload)
        case syncWorkspaceOperationalState(WorkspaceOperationalSyncMode)
        case markTerminalAttentionRead(workspaceID: Workspace.ID?, terminalID: UUID)
        case clearAttentionNotification(UUID)
        case setWorkspaceNotificationPreferences(terminalActivity: Bool, agentActivity: Bool)
        case requestWorkspaceOperationalMetadataRefresh(worktreeIDs: [Workspace.ID], repositoryID: Repository.ID?)
        case setWorkspaceRunState(workspaceID: Workspace.ID, WorkspaceRunState?)
        case removeWorkspaceRunTerminal(UUID)
        case removeWorkspaceRunBackgroundProcess(UUID)
        case revealCurrentWorkspaceInNavigator
        case setActiveSheet(Sheet?)
        case setSearchPresentation(SearchPresentation?)
        case setNotificationsPanelPresented(Bool)
        case clearErrorMessage
    }

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
        case preview, permanent
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
                return [pane.id]
            case .split(let split):
                return split.first.allPaneIDs + split.second.allPaneIDs
            }
        }

        public func paneLayout(for paneID: PaneID) -> WorkspacePaneLayout? {
            switch self {
            case .pane(let pane):
                return pane.id == paneID ? pane : nil
            case .split(let split):
                return split.first.paneLayout(for: paneID) ?? split.second.paneLayout(for: paneID)
            }
        }

        public func paneID(containing tabID: TabID) -> PaneID? {
            switch self {
            case .pane(let pane):
                return pane.tabIDs.contains(tabID) ? pane.id : nil
            case .split(let split):
                return split.first.paneID(containing: tabID) ?? split.second.paneID(containing: tabID)
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
        case before, after
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
