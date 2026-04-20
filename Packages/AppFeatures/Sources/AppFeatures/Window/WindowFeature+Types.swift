import ComposableArchitecture
import Foundation
import RemoteCore
import Split
import Workspace

public extension WindowFeature {
    @ObservableState
    struct State: Equatable, Sendable {
        public var repositories: [Repository] = []
        public var worktreesByRepository: [Repository.ID: [Worktree]] = [:]
        public var remoteRepositories: [RemoteRepositoryAuthority] = []
        public var remoteWorktreesByRepository: [RemoteRepositoryAuthority.ID: [RemoteWorktree]] = [:]
        public var workspaceStatesByID: [Worktree.ID: WorktreeState] = [:]
        public var hostedWorkspaceContentByID: [Workspace.ID: HostedWorkspaceContentState] = [:]
        public var workflowWorkspacesByID: [Workspace.ID: WorkflowWorkspaceState] = [:]
        public var selectedRepositoryID: Repository.ID?
        public var selectedRemoteRepositoryID: RemoteRepositoryAuthority.ID?
        public var selectedRemoteWorktreeID: RemoteWorktree.ID?
        public var selectedWorkspaceID: Workspace.ID?
        public var workspaceShells: [Workspace.ID: WorkspaceShell] = [:]
        public var selectedTabID: TabID?
        public var activeSidebar: Sidebar? = .files
        public var isSidebarVisible = true
        public var isNavigatorCollapsed = false
        public var navigatorRevealRequest: NavigatorRevealRequest?
        public var activeSheet: Sheet?
        public var searchPresentation: SearchPresentation?
        public var addRepositoryPresentation: AddRepositoryPresentation?
        public var workspaceCreationPresentation: WorkspaceCreationPresentation?
        public var chatLaunchPresentation: ChatLaunchPresentation?
        public var remoteRepositoryPresentation: RemoteRepositoryPresentation?
        public var remoteWorktreeCreationPresentation: RemoteWorktreeCreationPresentation?
        public var chatSessionLaunchRequest: ChatSessionLaunchRequest?
        public var isGitCommitSheetPresented = false
        public var isCreatePullRequestSheetPresented = false
        public var openRepositoryRequestID: UUID?
        public var editorCommandRequest: EditorCommandRequest?
        public var workspaceTabCloseRequest: WorkspaceTabCloseRequest?
        public var workspaceTransitionRequest: WorkspaceTransitionRequest?
        public var remoteWorkspaceTransitionRequest: RemoteWorkspaceTransitionRequest?
        public var workspaceDiscardRequest: WorkspaceDiscardRequest?
        public var initializeRepositoryRequest: InitializeRepositoryRequest?
        public var saveDefaultLayoutRequestID: UUID?
        public var workspaceCommandRequest: WorkspaceCommandRequest?
        public var focusChatSessionRequest: FocusChatSessionRequest?
        public var remoteTerminalLaunchRequest: RemoteTerminalLaunchRequest?
        public var runProfileLaunchRequest: RunProfileLaunchRequest?
        public var runProfileStopRequest: RunProfileStopRequest?
        public var windowRelaunchRestoreRequest: WindowRelaunchRestoreRequest?
        public var isNotificationsPanelPresented = false
        public var isTerminalActivityNotificationsEnabled = true
        public var isChatActivityNotificationsEnabled = true
        public var operational = WorkspaceOperationalState()
        public var lastErrorMessage: String?

        public init(
            repositories: [Repository] = [],
            worktreesByRepository: [Repository.ID: [Worktree]] = [:],
            remoteRepositories: [RemoteRepositoryAuthority] = [],
            remoteWorktreesByRepository: [RemoteRepositoryAuthority.ID: [RemoteWorktree]] = [:],
            workspaceStatesByID: [Worktree.ID: WorktreeState] = [:],
            hostedWorkspaceContentByID: [Workspace.ID: HostedWorkspaceContentState] = [:],
            workflowWorkspacesByID: [Workspace.ID: WorkflowWorkspaceState] = [:],
            selectedRepositoryID: Repository.ID? = nil,
            selectedRemoteRepositoryID: RemoteRepositoryAuthority.ID? = nil,
            selectedRemoteWorktreeID: RemoteWorktree.ID? = nil,
            selectedWorkspaceID: Workspace.ID? = nil,
            workspaceShells: [Workspace.ID: WorkspaceShell] = [:],
            selectedTabID: TabID? = nil,
            activeSidebar: Sidebar? = .files,
            isSidebarVisible: Bool = true,
            isNavigatorCollapsed: Bool = false,
            navigatorRevealRequest: NavigatorRevealRequest? = nil,
            activeSheet: Sheet? = nil,
            searchPresentation: SearchPresentation? = nil,
            addRepositoryPresentation: AddRepositoryPresentation? = nil,
            workspaceCreationPresentation: WorkspaceCreationPresentation? = nil,
            chatLaunchPresentation: ChatLaunchPresentation? = nil,
            remoteRepositoryPresentation: RemoteRepositoryPresentation? = nil,
            remoteWorktreeCreationPresentation: RemoteWorktreeCreationPresentation? = nil,
            chatSessionLaunchRequest: ChatSessionLaunchRequest? = nil,
            isGitCommitSheetPresented: Bool = false,
            isCreatePullRequestSheetPresented: Bool = false,
            openRepositoryRequestID: UUID? = nil,
            editorCommandRequest: EditorCommandRequest? = nil,
            workspaceTabCloseRequest: WorkspaceTabCloseRequest? = nil,
            workspaceTransitionRequest: WorkspaceTransitionRequest? = nil,
            remoteWorkspaceTransitionRequest: RemoteWorkspaceTransitionRequest? = nil,
            workspaceDiscardRequest: WorkspaceDiscardRequest? = nil,
            initializeRepositoryRequest: InitializeRepositoryRequest? = nil,
            saveDefaultLayoutRequestID: UUID? = nil,
            workspaceCommandRequest: WorkspaceCommandRequest? = nil,
            focusChatSessionRequest: FocusChatSessionRequest? = nil,
            remoteTerminalLaunchRequest: RemoteTerminalLaunchRequest? = nil,
            runProfileLaunchRequest: RunProfileLaunchRequest? = nil,
            runProfileStopRequest: RunProfileStopRequest? = nil,
            windowRelaunchRestoreRequest: WindowRelaunchRestoreRequest? = nil,
            isNotificationsPanelPresented: Bool = false,
            isTerminalActivityNotificationsEnabled: Bool = true,
            isChatActivityNotificationsEnabled: Bool = true,
            operational: WorkspaceOperationalState = WorkspaceOperationalState(),
            lastErrorMessage: String? = nil
        ) {
            self.repositories = repositories
            self.worktreesByRepository = worktreesByRepository
            self.remoteRepositories = remoteRepositories
            self.remoteWorktreesByRepository = remoteWorktreesByRepository
            self.workspaceStatesByID = workspaceStatesByID
            self.hostedWorkspaceContentByID = hostedWorkspaceContentByID
            self.workflowWorkspacesByID = workflowWorkspacesByID
            self.selectedRepositoryID = selectedRepositoryID
            self.selectedRemoteRepositoryID = selectedRemoteRepositoryID
            self.selectedRemoteWorktreeID = selectedRemoteWorktreeID
            self.selectedWorkspaceID = selectedWorkspaceID
            self.workspaceShells = workspaceShells
            self.selectedTabID = selectedTabID
            self.activeSidebar = activeSidebar
            self.isSidebarVisible = isSidebarVisible
            self.isNavigatorCollapsed = isNavigatorCollapsed
            self.navigatorRevealRequest = navigatorRevealRequest
            self.activeSheet = activeSheet
            self.searchPresentation = searchPresentation
            self.addRepositoryPresentation = addRepositoryPresentation
            self.workspaceCreationPresentation = workspaceCreationPresentation
            self.chatLaunchPresentation = chatLaunchPresentation
            self.remoteRepositoryPresentation = remoteRepositoryPresentation
            self.remoteWorktreeCreationPresentation = remoteWorktreeCreationPresentation
            self.chatSessionLaunchRequest = chatSessionLaunchRequest
            self.isGitCommitSheetPresented = isGitCommitSheetPresented
            self.isCreatePullRequestSheetPresented = isCreatePullRequestSheetPresented
            self.openRepositoryRequestID = openRepositoryRequestID
            self.editorCommandRequest = editorCommandRequest
            self.workspaceTabCloseRequest = workspaceTabCloseRequest
            self.workspaceTransitionRequest = workspaceTransitionRequest
            self.remoteWorkspaceTransitionRequest = remoteWorkspaceTransitionRequest
            self.workspaceDiscardRequest = workspaceDiscardRequest
            self.initializeRepositoryRequest = initializeRepositoryRequest
            self.saveDefaultLayoutRequestID = saveDefaultLayoutRequestID
            self.workspaceCommandRequest = workspaceCommandRequest
            self.focusChatSessionRequest = focusChatSessionRequest
            self.remoteTerminalLaunchRequest = remoteTerminalLaunchRequest
            self.runProfileLaunchRequest = runProfileLaunchRequest
            self.runProfileStopRequest = runProfileStopRequest
            self.windowRelaunchRestoreRequest = windowRelaunchRestoreRequest
            self.isNotificationsPanelPresented = isNotificationsPanelPresented
            self.isTerminalActivityNotificationsEnabled = isTerminalActivityNotificationsEnabled
            self.isChatActivityNotificationsEnabled = isChatActivityNotificationsEnabled
            self.operational = operational
            self.lastErrorMessage = lastErrorMessage
            normalizeSelection()
        }
    }

    enum Action: Equatable {
        case loadRemoteRepositories
        case loadRemoteRepositoriesResponse(TaskResult<[RemoteRepositoryAuthority]>)
        case setRemoteRepositories([RemoteRepositoryAuthority])
        case setRemoteWorktrees(
            repositoryID: RemoteRepositoryAuthority.ID,
            worktrees: [RemoteWorktree]
        )
        case upsertRemoteRepository(RemoteRepositoryAuthority)
        case removeRemoteRepository(RemoteRepositoryAuthority.ID)
        case selectRemoteRepository(RemoteRepositoryAuthority.ID?)
        case selectRemoteWorktree(
            repositoryID: RemoteRepositoryAuthority.ID,
            workspaceID: RemoteWorktree.ID
        )
        case setRemoteRepositoryPresentation(RemoteRepositoryPresentation?)
        case setRemoteWorktreeCreationPresentation(RemoteWorktreeCreationPresentation?)
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
        case requestAddRepository
        case setAddRepositoryPresentation(AddRepositoryPresentation?)
        case presentWorkspaceCreation(repositoryID: Repository.ID, mode: WorkspaceCreationMode)
        case setWorkspaceCreationPresentation(WorkspaceCreationPresentation?)
        case setChatLaunchPresentation(ChatLaunchPresentation?)
        case requestChatSessionLaunch(ChatSessionLaunchIntent)
        case chatSessionLaunchResolved(ChatSessionLaunchResolution)
        case setChatSessionLaunchRequest(ChatSessionLaunchRequest?)
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
        case requestRemoteWorktreeSelection(
            repositoryID: RemoteRepositoryAuthority.ID,
            workspaceID: RemoteWorktree.ID
        )
        case setRemoteWorkspaceTransitionRequest(RemoteWorkspaceTransitionRequest?)
        case requestWorkspaceDiscard(workspaceID: Workspace.ID, repositoryID: Repository.ID)
        case setWorkspaceDiscardRequest(WorkspaceDiscardRequest?)
        case requestInitializeRepository(Repository.ID)
        case setInitializeRepositoryRequest(InitializeRepositoryRequest?)
        case requestSaveDefaultLayout
        case setSaveDefaultLayoutRequestID(UUID?)
        case requestWorkspaceCommand(WorkspaceCommand)
        case setWorkspaceCommandRequest(WorkspaceCommandRequest?)
        case requestFocusChatSession(ChatSessionID)
        case setFocusChatSessionRequest(FocusChatSessionRequest?)
        case refreshRemoteRepository(RemoteRepositoryAuthority.ID)
        case refreshRemoteRepositoryResponse(
            repositoryID: RemoteRepositoryAuthority.ID,
            result: TaskResult<[RemoteWorktree]>
        )
        case createRemoteWorktree(RemoteWorktreeDraft)
        case createRemoteWorktreeResponse(TaskResult<RemoteWorktreeCreationResult>)
        case fetchRemoteRepository(RemoteRepositoryAuthority.ID)
        case fetchRemoteRepositoryResponse(
            repositoryID: RemoteRepositoryAuthority.ID,
            result: TaskResult<[RemoteWorktree]>
        )
        case pullRemoteWorktree(
            repositoryID: RemoteRepositoryAuthority.ID,
            workspaceID: RemoteWorktree.ID
        )
        case pullRemoteWorktreeResponse(
            repositoryID: RemoteRepositoryAuthority.ID,
            result: TaskResult<[RemoteWorktree]>
        )
        case pushRemoteWorktree(
            repositoryID: RemoteRepositoryAuthority.ID,
            workspaceID: RemoteWorktree.ID
        )
        case pushRemoteWorktreeResponse(
            repositoryID: RemoteRepositoryAuthority.ID,
            result: TaskResult<[RemoteWorktree]>
        )
        case requestOpenRemoteTerminal(preferredPaneID: PaneID?)
        case remoteTerminalLaunchPrepared(TaskResult<RemoteTerminalLaunchRequest>)
        case setRemoteTerminalLaunchRequest(RemoteTerminalLaunchRequest?)
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
        case startWorkflowObservation
        case workflowWorkspaceLoadRequested(Workspace.ID)
        case workflowWorkspaceLoaded(Workspace.ID, WorkflowWorkspaceSnapshot)
        case workflowWorkspaceLoadFailed(Workspace.ID, String)
        case createDefaultWorkflowDefinition(workspaceID: Workspace.ID, definitionID: String)
        case updateWorkflowDefinition(
            workspaceID: Workspace.ID,
            definitionID: String,
            update: WorkflowDefinitionUpdate
        )
        case createWorkflowWorker(
            workspaceID: Workspace.ID,
            definitionID: String,
            workerID: String
        )
        case updateWorkflowWorker(
            workspaceID: Workspace.ID,
            definitionID: String,
            workerID: String,
            update: WorkflowWorkerUpdate
        )
        case deleteWorkflowWorker(
            workspaceID: Workspace.ID,
            definitionID: String,
            workerID: String
        )
        case replaceWorkflowGraph(
            workspaceID: Workspace.ID,
            definitionID: String,
            nodes: [WorkflowNode],
            edges: [WorkflowEdge]
        )
        case deleteWorkflowDefinition(workspaceID: Workspace.ID, definitionID: String)
        case startWorkflowRun(workspaceID: Workspace.ID, definitionID: String, runID: UUID)
        case continueWorkflowRun(workspaceID: Workspace.ID, runID: UUID)
        case restartWorkflowRun(workspaceID: Workspace.ID, runID: UUID)
        case stopWorkflowRun(workspaceID: Workspace.ID, runID: UUID)
        case deleteWorkflowRun(workspaceID: Workspace.ID, runID: UUID)
        case chooseWorkflowRunEdge(workspaceID: Workspace.ID, runID: UUID, edgeID: String)
        case appendWorkflowFollowUpTicket(
            workspaceID: Workspace.ID,
            runID: UUID,
            sectionTitle: String,
            text: String
        )
        case workflowPlanSnapshotLoaded(
            workspaceID: Workspace.ID,
            runID: UUID,
            snapshot: WorkflowPlanSnapshot
        )
        case workflowPlanSnapshotLoadFailed(
            workspaceID: Workspace.ID,
            runID: UUID,
            message: String
        )
        case workflowNodeLaunchSucceeded(
            workspaceID: Workspace.ID,
            runID: UUID,
            result: WorkflowNodeLaunchResult
        )
        case workflowNodeLaunchFailed(
            workspaceID: Workspace.ID,
            runID: UUID,
            message: String
        )
        case workflowFollowUpTicketAppended(
            workspaceID: Workspace.ID,
            runID: UUID,
            snapshot: WorkflowPlanSnapshot,
            sectionTitle: String,
            text: String
        )
        case workflowFollowUpTicketAppendFailed(
            workspaceID: Workspace.ID,
            runID: UUID,
            message: String
        )
        case workflowExecutionUpdated(WorkflowExecutionUpdate)
        case workspaceOperationalSnapshotUpdated(WorkspaceOperationalSnapshot)
        case workspaceAttentionIngressReceived(WorkspaceAttentionIngressPayload)
        case syncWorkspaceOperationalState(WorkspaceOperationalSyncMode)
        case markTerminalAttentionRead(workspaceID: Workspace.ID?, terminalID: UUID)
        case clearAttentionNotification(UUID)
        case setWorkspaceNotificationPreferences(terminalActivity: Bool, chatActivity: Bool)
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
}
