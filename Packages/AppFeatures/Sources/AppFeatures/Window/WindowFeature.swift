import ComposableArchitecture
import Foundation
import Split
import Workspace

// swiftlint:disable file_length type_body_length
@Reducer
public struct WindowFeature {
    @Dependency(\.workspaceCatalogPersistenceClient) var workspaceCatalogPersistenceClient
    @Dependency(\.workspaceCatalogRefreshClient) var workspaceCatalogRefreshClient
    @Dependency(\.workspaceOperationalClient) var workspaceOperationalClient
    @Dependency(\.workspaceAttentionIngressClient) var workspaceAttentionIngressClient
    @Dependency(\.repositorySettingsClient) var repositorySettingsClient
    @Dependency(\.globalSettingsClient) var globalSettingsClient
    @Dependency(\.windowRelaunchPersistenceClient) var windowRelaunchPersistenceClient
    @Dependency(\.recentRepositoriesClient) var recentRepositoriesClient
    @Dependency(\.repositoryDiscoveryClient) var repositoryDiscoveryClient
    @Dependency(\.workflowPersistenceClient) var workflowPersistenceClient
    @Dependency(\.workflowExecutionClient) var workflowExecutionClient
    @Dependency(\.uuid) var uuid
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .openRepository(let url):
                state.lastErrorMessage = nil
                let repositoryDiscoveryClient = self.repositoryDiscoveryClient
                return .run { send in
                    await send(
                        .openRepositoryResponse(
                            TaskResult {
                                try await repositoryDiscoveryClient.resolveRepository(url)
                            }
                        )
                    )
                }

            case .openRepositoryResponse(.success(let repository)):
                let recentRepositoryURLs = state.openResolvedRepositories([repository])
                let recentRepositoriesClient = self.recentRepositoriesClient
                let operationalContext = state.workspaceOperationalCatalogContext
                return .merge(
                    .run { _ in
                        for repositoryURL in recentRepositoryURLs {
                            await recentRepositoriesClient.add(repositoryURL)
                        }
                    },
                    syncWorkspaceOperationalEffect(operationalContext, mode: .all)
                )

            case .openRepositoryResponse(.failure(let error)):
                state.lastErrorMessage = error.localizedDescription
                return .none

            case .openResolvedRepositories(let repositories):
                let recentRepositoryURLs = state.openResolvedRepositories(repositories)
                let recentRepositoriesClient = self.recentRepositoriesClient
                let repositories = state.repositories
                let operationalContext = state.workspaceOperationalCatalogContext
                return .merge(
                    .run { _ in
                        for repositoryURL in recentRepositoryURLs {
                            await recentRepositoriesClient.add(repositoryURL)
                        }
                    },
                    persistRepositoriesEffect(repositories),
                    syncWorkspaceOperationalEffect(operationalContext, mode: .all)
                )

            case .refreshRepositories(let repositoryIDs):
                let refreshClient = self.workspaceCatalogRefreshClient
                let snapshot = state.repositoryCatalogSnapshot
                return .run { send in
                    let refreshedSnapshot = await refreshClient.refreshRepositories(
                        snapshot,
                        repositoryIDs
                    )
                    await send(.setRepositoryCatalogSnapshot(refreshedSnapshot))
                }

            case .setRepositoryCatalogSnapshot(let snapshot):
                let previousRepositoryID = state.selectedRepositoryID
                let previousWorkspaceID = state.selectedWorkspaceID
                state.applyRepositoryCatalogSnapshot(snapshot)
                if previousRepositoryID != state.selectedRepositoryID
                    || previousWorkspaceID != state.selectedWorkspaceID {
                    state.restoreWorkspaceShell(for: state.selectedWorkspaceID)
                }
                let workflowLoadEffect = state.selectedWorkspaceID.map { workspaceID in
                    Effect<Action>.send(.workflowWorkspaceLoadRequested(workspaceID))
                } ?? .none
                return .merge(
                    syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .all
                    ),
                    workflowLoadEffect
                )

            case let .moveRepository(repositoryID, offset):
                state.moveRepository(repositoryID, by: offset)
                return persistRepositoriesEffect(state.repositories)

            case let .reorderRepository(repositoryID, toIndex):
                state.reorderRepository(repositoryID, toIndex: toIndex)
                return persistRepositoriesEffect(state.repositories)

            case .removeRepository(let repositoryID):
                let removedWorkspaceIDs = state.worktreesByRepository[repositoryID]?.map(\.id) ?? []
                state.persistActiveWorkspaceShellIfNeeded()
                state.removeRepository(repositoryID)
                state.restoreWorkspaceShell(for: state.selectedWorkspaceID)
                return .merge(
                    persistCatalogEffect(
                        repositories: state.repositories,
                        workspaceStatesByID: state.workspaceStatesByID
                    ),
                    .merge(
                        clearWorkspaceOperationalEffects(removedWorkspaceIDs),
                        syncWorkspaceOperationalEffect(
                            state.workspaceOperationalCatalogContext,
                            mode: .all
                        )
                    )
                )

            case let .setRepositorySourceControl(sourceControl, repositoryID):
                state.setRepositorySourceControl(sourceControl, for: repositoryID)
                return persistRepositoriesEffect(state.repositories)

            case let .setRepositoryDisplayInitials(repositoryID, initials):
                state.setRepositoryDisplayInitials(repositoryID, initials: initials)
                return persistRepositoriesEffect(state.repositories)

            case let .setRepositoryDisplaySymbol(repositoryID, symbol):
                state.setRepositoryDisplaySymbol(repositoryID, symbol: symbol)
                return persistRepositoriesEffect(state.repositories)

            case let .setWorkspacePinned(workspaceID, repositoryID, isPinned):
                state.setWorkspacePinned(workspaceID, in: repositoryID, isPinned: isPinned)
                return persistWorkspaceStatesEffect(state.workspaceStatesByID)

            case let .setWorkspaceArchived(workspaceID, repositoryID, isArchived):
                let previousWorkspaceID = state.selectedWorkspaceID
                state.setWorkspaceArchived(workspaceID, in: repositoryID, isArchived: isArchived)
                if previousWorkspaceID != state.selectedWorkspaceID {
                    state.restoreWorkspaceShell(for: state.selectedWorkspaceID)
                }
                return .merge(
                    persistWorkspaceStatesEffect(state.workspaceStatesByID),
                    syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .structure
                    )
                )

            case let .setWorkspaceDisplayName(workspaceID, repositoryID, displayName):
                state.setWorkspaceDisplayName(displayName, for: workspaceID, in: repositoryID)
                return persistWorkspaceStatesEffect(state.workspaceStatesByID)

            case let .removeWorkspaceState(workspaceID, repositoryID):
                let previousWorkspaceID = state.selectedWorkspaceID
                state.removeWorkspaceState(workspaceID, in: repositoryID)
                state.hostedWorkspaceContentByID.removeValue(forKey: workspaceID)
                state.workflowWorkspacesByID.removeValue(forKey: workspaceID)
                if previousWorkspaceID != state.selectedWorkspaceID {
                    state.restoreWorkspaceShell(for: state.selectedWorkspaceID)
                }
                return .merge(
                    persistWorkspaceStatesEffect(state.workspaceStatesByID),
                    clearWorkspaceOperationalEffects([workspaceID]),
                    syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .structure
                    )
                )

            case let .setHostedWorkspaceContent(workspaceID, content):
                state.hostedWorkspaceContentByID[workspaceID] = content
                return .none

            case .removeHostedWorkspaceContent(let workspaceID):
                state.hostedWorkspaceContentByID.removeValue(forKey: workspaceID)
                return .none

            case .selectRepository(let repositoryID):
                state.persistActiveWorkspaceShellIfNeeded()
                state.selectedRepositoryID = repositoryID
                state.restoreWorkspaceShell(for: nil)
                state.normalizeSelection()
                return syncWorkspaceOperationalEffect(
                    state.workspaceOperationalCatalogContext,
                    mode: .metadata
                )

            case .selectWorkspace(let workspaceID):
                state.persistActiveWorkspaceShellIfNeeded()
                state.restoreWorkspaceShell(for: workspaceID)
                guard let workspaceID,
                      let repositoryID = state.repositoryID(containing: workspaceID) else {
                    return syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .metadata
                    )
                }
                state.updateWorkspaceState(workspaceID, in: repositoryID) { state in
                    state.lastFocused = now
                }
                state.reorderWorktrees(in: repositoryID)
                return .merge(
                    persistWorkspaceStatesEffect(state.workspaceStatesByID),
                    .send(.workflowWorkspaceLoadRequested(workspaceID)),
                    syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .metadata
                    )
                )

            case .setWorkspaceShell(let workspaceID, let shell):
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.restoreWorkspaceShell(for: workspaceID)
                }
                return .none

            case .removeWorkspaceShell(let workspaceID):
                state.workspaceShells.removeValue(forKey: workspaceID)
                if state.selectedWorkspaceID == workspaceID {
                    state.restoreWorkspaceShell(for: nil)
                }
                return .none

            case let .setWorkspaceTabContent(workspaceID, tabID, content):
                var shell = state.workspaceShells[workspaceID]
                    ?? WindowFeature.WorkspaceShell()
                shell.tabContents[tabID] = content
                state.workspaceShells[workspaceID] = shell
                return .none

            case let .removeWorkspaceTabContent(workspaceID, tabID):
                guard var shell = state.workspaceShells[workspaceID] else { return .none }
                shell.tabContents.removeValue(forKey: tabID)
                state.workspaceShells[workspaceID] = shell
                return .none

            case .clearWorkspaceTabContents(let workspaceID):
                guard var shell = state.workspaceShells[workspaceID] else { return .none }
                shell.tabContents.removeAll()
                state.workspaceShells[workspaceID] = shell
                return .none

            case let .openWorkspaceContent(workspaceID, paneID, content, mode):
                _ = state.openWorkspaceContent(
                    workspaceID: workspaceID,
                    paneID: paneID,
                    content: content,
                    mode: mode
                )
                return .none

            case let .setWorkspaceLayout(workspaceID, layout):
                var shell = state.workspaceShells[workspaceID]
                    ?? WindowFeature.WorkspaceShell()
                shell.layout = layout
                let focusedPaneStillExists = shell.focusedPaneID.flatMap { layout.paneLayout(for: $0) } != nil
                if !focusedPaneStillExists {
                    shell.focusedPaneID = layout.focusedFallbackPaneID
                }
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: shell.focusedPaneID)
                }
                return .none

            case let .insertWorkspaceTab(workspaceID, paneID, tabID, index, isPreview):
                var shell = state.workspaceShells[workspaceID]
                    ?? WindowFeature.WorkspaceShell()
                var layout = shell.layout ?? WindowFeature.WorkspaceLayout()
                layout.insertTab(tabID, into: paneID, at: index, isPreview: isPreview)
                shell.layout = layout
                shell.focusedPaneID = paneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = tabID
                }
                return .none

            case let .selectWorkspaceTab(workspaceID, paneID, tabID):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                guard layout.paneLayout(for: paneID)?.tabIDs.contains(tabID) == true else {
                    return .none
                }
                layout.selectTab(tabID, in: paneID)
                shell.layout = layout
                shell.focusedPaneID = paneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = tabID
                }
                return .none

            case let .closeWorkspaceTab(workspaceID, paneID, tabID):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                let focusedPaneID = layout.closeTab(tabID, in: paneID)
                if let focusedPaneID {
                    shell.focusedPaneID = focusedPaneID
                } else if layout.paneLayout(for: shell.focusedPaneID ?? paneID) == nil {
                    shell.focusedPaneID = layout.focusedFallbackPaneID
                }
                shell.layout = layout
                state.workspaceShells[workspaceID] = shell
                state.clearWorkspacePreviewTabID(workspaceID: workspaceID, matching: tabID)
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: shell.focusedPaneID)
                }
                return .none

            case let .reorderWorkspaceTab(workspaceID, paneID, tabID, sourceIndex, destinationIndex):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                layout.reorderTab(
                    tabID,
                    in: paneID,
                    from: sourceIndex,
                    to: destinationIndex
                )
                shell.layout = layout
                shell.focusedPaneID = paneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: paneID)
                }
                return .none

            case let .moveWorkspaceTab(workspaceID, tabID, sourcePaneID, destinationPaneID, index):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                let focusedPaneID = layout.moveTab(
                    tabID,
                    from: sourcePaneID,
                    to: destinationPaneID,
                    at: index
                )
                shell.layout = layout
                shell.focusedPaneID = focusedPaneID ?? destinationPaneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: shell.focusedPaneID)
                }
                return .none

            case let .splitWorkspacePane(workspaceID, paneID, newPaneID, orientation, insertion):
                var shell = state.workspaceShells[workspaceID]
                    ?? WindowFeature.WorkspaceShell()
                var layout = shell.layout ?? WindowFeature.WorkspaceLayout()
                layout.splitPane(
                    paneID,
                    newPaneID: newPaneID,
                    orientation: orientation,
                    insertion: insertion
                )
                shell.layout = layout
                shell.focusedPaneID = newPaneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: newPaneID)
                }
                return .none

            case let .splitWorkspacePaneWithTab(
                workspaceID,
                targetPaneID,
                newPaneID,
                tabID,
                sourcePaneID,
                sourceIndex,
                orientation,
                insertion
            ):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                guard layout.paneLayout(for: sourcePaneID)?.tabIDs[safe: sourceIndex] == tabID else {
                    return .none
                }
                let focusedPaneID = layout.splitPaneWithTab(
                    targetPaneID: targetPaneID,
                    newPaneID: newPaneID,
                    tabID: tabID,
                    sourcePaneID: sourcePaneID,
                    orientation: orientation,
                    insertion: insertion
                )
                shell.layout = layout
                shell.focusedPaneID = focusedPaneID ?? newPaneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: shell.focusedPaneID)
                }
                return .none

            case let .closeWorkspacePane(workspaceID, paneID):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                let focusedPaneID = layout.closePane(paneID) ?? layout.focusedFallbackPaneID
                shell.layout = layout
                shell.focusedPaneID = focusedPaneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = layout.selectedTabID(in: focusedPaneID)
                }
                return .none

            case let .setWorkspaceSplitDividerPosition(workspaceID, splitID, position):
                guard var shell = state.workspaceShells[workspaceID],
                      var layout = shell.layout else {
                    return .none
                }
                layout.setDividerPosition(position, splitID: splitID)
                shell.layout = layout
                state.workspaceShells[workspaceID] = shell
                return .none

            case let .setWorkspaceFocusedPaneID(workspaceID, paneID):
                var shell = state.workspaceShells[workspaceID]
                    ?? WindowFeature.WorkspaceShell()
                shell.focusedPaneID = paneID
                state.workspaceShells[workspaceID] = shell
                if state.selectedWorkspaceID == workspaceID {
                    state.selectedTabID = shell.layout?.selectedTabID(in: paneID)
                }
                return .none

            case let .setWorkspacePanePreviewTabID(workspaceID, paneID, tabID):
                guard var shell = state.workspaceShells[workspaceID],
                      let layout = shell.layout else {
                    return .none
                }
                shell.layout = WindowFeature.WorkspaceLayout(
                    root: settingPreviewTabID(tabID, in: paneID, within: layout.root)
                )
                state.workspaceShells[workspaceID] = shell
                return .none

            case .setSelectedTabID(let tabID):
                state.selectedTabID = tabID
                return .none

            case let .clearWorkspacePreviewTabID(workspaceID, tabID):
                state.clearWorkspacePreviewTabID(workspaceID: workspaceID, matching: tabID)
                return .none

            case .restoreSelection(let repositoryID, let workspaceID):
                state.persistActiveWorkspaceShellIfNeeded()
                state.selectedRepositoryID = repositoryID
                state.restoreWorkspaceShell(for: nil)
                state.normalizeSelection()
                if state.selectedRepositoryID != nil {
                    state.restoreWorkspaceShell(for: workspaceID)
                }
                return .merge(
                    syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .metadata
                    ),
                    workspaceID.map { Effect<Action>.send(.workflowWorkspaceLoadRequested($0)) } ?? .none
                )

            case .startWorkspaceOperationalObservation:
                return .merge(
                    observeWorkspaceOperationalSnapshotsEffect(),
                    observeWorkspaceAttentionIngressEffect(),
                    syncWorkspaceOperationalEffect(
                        state.workspaceOperationalCatalogContext,
                        mode: .all
                    )
                )

            case .startWorkflowObservation,
                 .workflowWorkspaceLoadRequested,
                 .workflowWorkspaceLoaded,
                 .workflowWorkspaceLoadFailed,
                 .createDefaultWorkflowDefinition,
                 .updateWorkflowDefinition,
                 .createWorkflowWorker,
                 .updateWorkflowWorker,
                 .deleteWorkflowWorker,
                 .replaceWorkflowGraph,
                 .deleteWorkflowDefinition,
                 .startWorkflowRun,
                 .continueWorkflowRun,
                 .restartWorkflowRun,
                 .stopWorkflowRun,
                 .chooseWorkflowRunEdge,
                 .deleteWorkflowRun,
                 .appendWorkflowFollowUpTicket,
                 .workflowPlanSnapshotLoaded,
                 .workflowPlanSnapshotLoadFailed,
                 .workflowNodeLaunchSucceeded,
                 .workflowNodeLaunchFailed,
                 .workflowFollowUpTicketAppended,
                 .workflowFollowUpTicketAppendFailed,
                 .workflowExecutionUpdated:
                return reduceWorkflowAction(state: &state, action: action)

            case .workspaceOperationalSnapshotUpdated(let snapshot):
                state.operational.applySnapshot(
                    snapshot,
                    terminalNotificationsEnabled: state.isTerminalActivityNotificationsEnabled,
                    now: now
                )
                return .none

            case .workspaceAttentionIngressReceived(let payload):
                state.operational.ingest(
                    payload,
                    agentNotificationsEnabled: state.isAgentActivityNotificationsEnabled,
                    terminalNotificationsEnabled: state.isTerminalActivityNotificationsEnabled,
                    now: now
                )
                return .none

            case .syncWorkspaceOperationalState(let mode):
                return syncWorkspaceOperationalEffect(
                    state.workspaceOperationalCatalogContext,
                    mode: mode
                )

            case let .markTerminalAttentionRead(workspaceID, terminalID):
                state.operational.markTerminalRead(terminalID, in: workspaceID)
                let workspaceOperationalClient = self.workspaceOperationalClient
                return .run { _ in
                    await workspaceOperationalClient.markTerminalRead(workspaceID, terminalID)
                }

            case .clearAttentionNotification(let notificationID):
                state.operational.clearNotification(notificationID)
                return .none

            case let .setWorkspaceNotificationPreferences(terminalActivity, agentActivity):
                state.isTerminalActivityNotificationsEnabled = terminalActivity
                state.isAgentActivityNotificationsEnabled = agentActivity
                state.operational.syncAttentionPreferences(
                    terminalNotificationsEnabled: terminalActivity,
                    agentNotificationsEnabled: agentActivity,
                    now: now
                )
                return .none

            case let .requestWorkspaceOperationalMetadataRefresh(worktreeIDs, repositoryID):
                let workspaceOperationalClient = self.workspaceOperationalClient
                return .run { _ in
                    await workspaceOperationalClient.requestMetadataRefresh(worktreeIDs, repositoryID)
                }

            case let .setWorkspaceRunState(workspaceID, runState):
                state.operational.setRunState(runState, for: workspaceID)
                return .none

            case .runProfileLaunchCompleted(let result):
                state.operational.setRunState(
                    WorkspaceRunState(
                        profileID: result.profileID,
                        terminalIDs: Set(result.terminalIDs),
                        backgroundProcessIDs: Set(result.backgroundProcessIDs)
                    ),
                    for: result.workspaceID
                )
                return .none

            case .runProfileStopCompleted(let workspaceID):
                state.operational.setRunState(nil, for: workspaceID)
                return .none

            case .removeWorkspaceRunTerminal(let terminalID):
                state.operational.removeRunTerminal(terminalID)
                return .none

            case .removeWorkspaceRunBackgroundProcess(let processID):
                state.operational.removeRunBackgroundProcess(processID)
                return .none

            case .showSidebar(let sidebar):
                state.activeSidebar = sidebar
                state.isSidebarVisible = true
                state.updateActiveWorkspaceShell { $0.activeSidebar = sidebar }
                return .none

            case .setActiveSidebar(let sidebar):
                state.activeSidebar = sidebar
                state.updateActiveWorkspaceShell { $0.activeSidebar = sidebar }
                return .none

            case .setSidebarVisibility(let isVisible):
                state.isSidebarVisible = isVisible
                return .none

            case .toggleSidebarVisibility:
                state.isSidebarVisible.toggle()
                return .none

            case .setNavigatorCollapsed(let isCollapsed):
                state.isNavigatorCollapsed = isCollapsed
                return .none

            case .toggleNavigatorCollapsed:
                state.isNavigatorCollapsed.toggle()
                return .none

            case .requestNavigatorReveal(let workspaceID):
                state.navigatorRevealRequest = NavigatorRevealRequest(
                    workspaceID: workspaceID,
                    token: uuid()
                )
                return .none

            case .setNavigatorRevealRequest(let request):
                state.navigatorRevealRequest = request
                return .none

            case .openSearch(let mode, let initialQuery):
                state.searchPresentation = SearchPresentation(
                    mode: mode,
                    initialQuery: initialQuery,
                    id: uuid()
                )
                return .none

            case let .presentWorkspaceCreation(repositoryID, mode):
                state.workspaceCreationPresentation = state.repositories
                    .first { $0.id == repositoryID }
                    .map { WorkspaceCreationPresentation(repository: $0, mode: mode) }
                return .none

            case .requestAgentSessionLaunch,
                 .agentSessionLaunchResolved,
                 .setAgentSessionLaunchRequest:
                return reduceAgentSessionLaunchAction(state: &state, action: action)

            case .setWorkspaceCreationPresentation(let presentation):
                state.workspaceCreationPresentation = presentation
                return .none

            case .setAgentLaunchPresentation(let presentation):
                state.agentLaunchPresentation = presentation
                return .none

            case .setGitCommitSheetPresented(let isPresented):
                state.isGitCommitSheetPresented = isPresented
                return .none

            case .setCreatePullRequestSheetPresented(let isPresented):
                state.isCreatePullRequestSheetPresented = isPresented
                return .none

            case .requestOpenRepository,
                 .setOpenRepositoryRequestID,
                 .requestEditorCommand,
                 .setEditorCommandRequest,
                 .requestWorkspaceTabClose,
                 .setWorkspaceTabCloseRequest,
                 .requestSaveDefaultLayout,
                 .setSaveDefaultLayoutRequestID,
                 .requestWorkspaceCommand,
                 .setWorkspaceCommandRequest,
                 .requestFocusAgentSession,
                 .setFocusAgentSessionRequest,
                 .runProfileLaunchRequestResolved,
                 .setRunProfileLaunchRequest,
                 .requestStopWorkspaceRun,
                 .setRunProfileStopRequest,
                 .requestWindowRelaunchRestore,
                 .windowRelaunchRestoreLoaded,
                 .setWindowRelaunchRestoreRequest,
                 .applyWindowRelaunchRestore,
                 .persistWindowRelaunchSnapshot,
                 .revealCurrentWorkspaceInNavigator:
                return reduceShellCommandRequestAction(state: &state, action: action)

            case .requestRepositorySelection,
                 .requestWorkspaceSelection,
                 .requestWorkspaceSelectionAtIndex,
                 .requestAdjacentWorkspaceSelection,
                 .setWorkspaceTransitionRequest,
                 .requestWorkspaceDiscard,
                 .setWorkspaceDiscardRequest,
                 .requestInitializeRepository,
                 .setInitializeRepositoryRequest:
                return reduceShellSelectionRequestAction(state: &state, action: action)

            case .setActiveSheet,
                 .setSearchPresentation,
                 .setNotificationsPanelPresented,
                 .clearErrorMessage:
                return reduceShellPresentationAction(state: &state, action: action)
            }
        }
    }
}

private extension WindowFeature {
    enum WorkspaceOperationalObservationID: Hashable {
        case snapshots
        case attentionIngress
    }

    func persistRepositoriesEffect(
        _ repositories: [Repository]
    ) -> Effect<Action> {
        let workspaceCatalogPersistenceClient = self.workspaceCatalogPersistenceClient
        return .run { _ in
            await workspaceCatalogPersistenceClient.saveRepositories(repositories)
        }
    }

    func persistWorkspaceStatesEffect(
        _ workspaceStatesByID: [Worktree.ID: WorktreeState]
    ) -> Effect<Action> {
        let workspaceCatalogPersistenceClient = self.workspaceCatalogPersistenceClient
        let workspaceStates = workspaceStatesByID.values.sorted { $0.worktreeId < $1.worktreeId }
        return .run { _ in
            await workspaceCatalogPersistenceClient.saveWorkspaceStates(workspaceStates)
        }
    }

    func persistCatalogEffect(
        repositories: [Repository],
        workspaceStatesByID: [Worktree.ID: WorktreeState]
    ) -> Effect<Action> {
        .merge(
            persistRepositoriesEffect(repositories),
            persistWorkspaceStatesEffect(workspaceStatesByID)
        )
    }

    func syncWorkspaceOperationalEffect(
        _ context: WorkspaceOperationalCatalogContext,
        mode: WorkspaceOperationalSyncMode
    ) -> Effect<Action> {
        let workspaceOperationalClient = self.workspaceOperationalClient
        return .run { _ in
            await workspaceOperationalClient.sync(context, mode)
        }
    }

    func observeWorkspaceOperationalSnapshotsEffect() -> Effect<Action> {
        let workspaceOperationalClient = self.workspaceOperationalClient
        return .run { send in
            for await snapshot in await workspaceOperationalClient.updates() {
                await send(.workspaceOperationalSnapshotUpdated(snapshot))
            }
        }
        .cancellable(id: WorkspaceOperationalObservationID.snapshots, cancelInFlight: true)
    }

    func observeWorkspaceAttentionIngressEffect() -> Effect<Action> {
        let workspaceAttentionIngressClient = self.workspaceAttentionIngressClient
        return .run { send in
            for await payload in await workspaceAttentionIngressClient.updates() {
                await send(.workspaceAttentionIngressReceived(payload))
            }
        }
        .cancellable(id: WorkspaceOperationalObservationID.attentionIngress, cancelInFlight: true)
    }

    func clearWorkspaceOperationalEffects(
        _ workspaceIDs: [Workspace.ID]
    ) -> Effect<Action> {
        let workspaceOperationalClient = self.workspaceOperationalClient
        return .run { _ in
            for workspaceID in workspaceIDs {
                await workspaceOperationalClient.clearWorkspace(workspaceID)
            }
        }
    }
}
// swiftlint:enable type_body_length

private func settingPreviewTabID(
    _ tabID: TabID?,
    in paneID: PaneID,
    within node: WindowFeature.WorkspaceLayoutNode
) -> WindowFeature.WorkspaceLayoutNode {
    switch node {
    case .pane(var pane):
        guard pane.id == paneID else { return .pane(pane) }
        pane.previewTabID = tabID
        return .pane(pane)
    case .split(var split):
        split.first = settingPreviewTabID(tabID, in: paneID, within: split.first)
        split.second = settingPreviewTabID(tabID, in: paneID, within: split.second)
        return .split(split)
    }
}
