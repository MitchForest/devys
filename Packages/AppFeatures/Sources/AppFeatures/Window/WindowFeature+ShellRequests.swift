import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func reduceShellCommandRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestAddRepository,
             .setAddRepositoryPresentation,
             .requestOpenRepository,
             .setOpenRepositoryRequestID:
            return reduceRepositoryImportRequestAction(state: &state, action: action)

        case .requestEditorCommand,
             .setEditorCommandRequest:
            return reduceEditorCommandRequestAction(state: &state, action: action)

        case .requestWorkspaceTabClose,
             .setWorkspaceTabCloseRequest:
            return reduceWorkspaceTabCloseRequestAction(state: &state, action: action)

        case .requestSaveDefaultLayout,
             .setSaveDefaultLayoutRequestID:
            return reduceSaveLayoutRequestAction(state: &state, action: action)

        case .requestWorkspaceCommand,
             .setWorkspaceCommandRequest:
            return reduceWorkspaceCommandRequestAction(state: &state, action: action)

        case .requestFocusChatSession,
             .setFocusChatSessionRequest,
             .revealCurrentWorkspaceInNavigator:
            return reduceWorkspaceScopedRequestAction(state: &state, action: action)

        case .runProfileLaunchRequestResolved,
             .setRunProfileLaunchRequest,
             .requestStopWorkspaceRun,
             .setRunProfileStopRequest:
            return reduceRunProfileRequestAction(state: &state, action: action)

        case .requestWindowRelaunchRestore,
             .windowRelaunchRestoreLoaded,
             .setWindowRelaunchRestoreRequest,
             .applyWindowRelaunchRestore,
             .persistWindowRelaunchSnapshot:
            return reduceWindowRelaunchRequestAction(state: &state, action: action)

        default:
            return .none
        }
    }

    private func reduceEditorCommandRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestEditorCommand(let command):
            state.editorCommandRequest = EditorCommandRequest(command: command, id: uuid())
            return .none

        case .setEditorCommandRequest(let request):
            state.editorCommandRequest = request
            return .none

        default:
            return .none
        }
    }

    private func reduceWorkspaceTabCloseRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestWorkspaceTabClose(let context):
            let strategy: WorkspaceTabCloseRequest.Strategy
            if context.isDirtyEditor {
                strategy = .confirmDirtyEditor(fileName: context.content.fallbackTitle)
            } else {
                strategy = .closeImmediately
            }
            state.workspaceTabCloseRequest = WorkspaceTabCloseRequest(
                context: context,
                strategy: strategy,
                id: uuid()
            )
            return .none

        case .setWorkspaceTabCloseRequest(let request):
            state.workspaceTabCloseRequest = request
            return .none

        default:
            return .none
        }
    }

    private func reduceSaveLayoutRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestSaveDefaultLayout:
            state.saveDefaultLayoutRequestID = uuid()
            return .none

        case .setSaveDefaultLayoutRequestID(let requestID):
            state.saveDefaultLayoutRequestID = requestID
            return .none

        default:
            return .none
        }
    }

    private func reduceWorkspaceCommandRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestWorkspaceCommand(let command):
            return reduceWorkspaceCommandRequest(state: &state, command: command)

        case .setWorkspaceCommandRequest(let request):
            state.workspaceCommandRequest = request
            return .none

        default:
            return .none
        }
    }

    private func reduceWorkspaceScopedRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestFocusChatSession(let sessionID):
            guard let workspaceID = state.selectedWorkspaceID else { return .none }
            state.focusChatSessionRequest = FocusChatSessionRequest(
                workspaceID: workspaceID,
                sessionID: sessionID,
                id: uuid()
            )
            return .none

        case .setFocusChatSessionRequest(let request):
            state.focusChatSessionRequest = request
            return .none

        case .revealCurrentWorkspaceInNavigator:
            guard let workspaceID = state.selectedWorkspaceID else { return .none }
            state.navigatorRevealRequest = NavigatorRevealRequest(
                workspaceID: workspaceID,
                token: uuid()
            )
            return .none

        default:
            return .none
        }
    }

    private func reduceRunProfileRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .runProfileLaunchRequestResolved(let resolution):
            state.lastErrorMessage = nil
            switch resolution {
            case .ready(let request):
                state.runProfileLaunchRequest = request
            case .failed(let message):
                state.lastErrorMessage = message
            }
            return .none

        case .setRunProfileLaunchRequest(let request):
            state.runProfileLaunchRequest = request
            return .none

        case .requestStopWorkspaceRun(let workspaceID):
            state.runProfileStopRequest = makeRunProfileStopRequest(
                state: state,
                workspaceID: workspaceID
            )
            return .none

        case .setRunProfileStopRequest(let request):
            state.runProfileStopRequest = request
            return .none

        default:
            return .none
        }
    }

    private func reduceWindowRelaunchRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestWindowRelaunchRestore(let force):
            return makeWindowRelaunchRestoreEffect(
                state: state,
                force: force
            )

        case .windowRelaunchRestoreLoaded(.success(let snapshot), let settings, let force):
            guard let snapshot, snapshot.hasRepositories else { return .none }
            guard force || settings.restoreRepositoriesOnLaunch else { return .none }
            state.windowRelaunchRestoreRequest = WindowRelaunchRestoreRequest(
                snapshot: snapshot,
                settings: settings,
                id: uuid()
            )
            return .none

        case .windowRelaunchRestoreLoaded(.failure, _, _):
            return .none

        case .setWindowRelaunchRestoreRequest(let request):
            state.windowRelaunchRestoreRequest = request
            return .none

        case .applyWindowRelaunchRestore(let request):
            state.applyWindowRelaunchRestore(request)
            return request.snapshot.selectedWorkspaceID.map { workspaceID in
                .send(.workflowWorkspaceLoadRequested(workspaceID))
            } ?? .none

        case .persistWindowRelaunchSnapshot(let hostedTerminalSessions):
            return makePersistWindowRelaunchSnapshotEffect(
                state: state,
                hostedTerminalSessions: hostedTerminalSessions
            )

        default:
            return .none
        }
    }

    private func makeWindowRelaunchRestoreEffect(
        state: State,
        force: Bool
    ) -> Effect<Action> {
        guard state.repositories.isEmpty else { return .none }
        let globalSettingsClient = self.globalSettingsClient
        let windowRelaunchPersistenceClient = self.windowRelaunchPersistenceClient
        return .run { send in
            let settings = makeRelaunchSettingsSnapshot(from: await globalSettingsClient.load())
            await send(
                .windowRelaunchRestoreLoaded(
                    TaskResult {
                        await windowRelaunchPersistenceClient.load()
                    },
                    settings: settings,
                    force: force
                )
            )
        }
    }

    private func makePersistWindowRelaunchSnapshotEffect(
        state: State,
        hostedTerminalSessions: [HostedTerminalSessionRecord]
    ) -> Effect<Action> {
        let globalSettingsClient = self.globalSettingsClient
        let windowRelaunchPersistenceClient = self.windowRelaunchPersistenceClient
        return .run { _ in
            let settings = makeRelaunchSettingsSnapshot(from: await globalSettingsClient.load())

            if let relaunchSnapshot = state.makeWindowRelaunchSnapshot(
                settings: settings,
                hostedTerminalSessions: hostedTerminalSessions
            ) {
                try? await windowRelaunchPersistenceClient.save(relaunchSnapshot)
            } else {
                try? await windowRelaunchPersistenceClient.clear()
            }
        }
    }

    private func reduceWorkspaceCommandRequest(
        state: inout State,
        command: WorkspaceCommand
    ) -> Effect<Action> {
        state.lastErrorMessage = nil

        switch command {
        case .runWorkspaceProfile:
            guard let worktree = state.selectedWorktree else { return .none }
            return prepareRunProfileLaunchEffect(for: worktree)
        case .openChat,
             .launchShell,
             .launchClaude,
             .launchCodex,
             .jumpToLatestUnreadWorkspace:
            state.workspaceCommandRequest = WorkspaceCommandRequest(command: command, id: uuid())
            return .none
        }
    }

    private func prepareRunProfileLaunchEffect(
        for worktree: Worktree
    ) -> Effect<Action> {
        let requestID = uuid()
        let repositorySettingsClient = self.repositorySettingsClient

        return .run { send in
            let settings = await repositorySettingsClient.load(worktree.repositoryRootURL)

            do {
                let resolvedProfile = try RepositoryLaunchPlanner.resolveDefaultStartupProfile(
                    in: settings,
                    workspaceRoot: worktree.workingDirectory
                )
                await send(
                    .runProfileLaunchRequestResolved(
                        .ready(
                            RunProfileLaunchRequest(
                                workspaceID: worktree.id,
                                resolvedProfile: resolvedProfile,
                                id: requestID
                            )
                        )
                    )
                )
            } catch {
                await send(.runProfileLaunchRequestResolved(.failed(error.localizedDescription)))
            }
        }
    }

    private func makeRunProfileStopRequest(
        state: State,
        workspaceID: Workspace.ID?
    ) -> RunProfileStopRequest? {
        let targetWorkspaceID = workspaceID ?? state.selectedWorkspaceID
        guard let targetWorkspaceID,
              let runState = state.operational.runStatesByWorkspaceID[targetWorkspaceID] else {
            return nil
        }

        return RunProfileStopRequest(
            workspaceID: targetWorkspaceID,
            terminalIDs: sortedUUIDs(runState.terminalIDs),
            backgroundProcessIDs: sortedUUIDs(runState.backgroundProcessIDs),
            id: uuid()
        )
    }

    func reduceShellSelectionRequestAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestRepositorySelection(let repositoryID):
            return setWorkspaceTransitionRequest(
                state: &state,
                targetRepositoryID: repositoryID,
                targetWorkspaceID: nil
            )

        case let .requestWorkspaceSelection(repositoryID, workspaceID):
            return setWorkspaceTransitionRequest(
                state: &state,
                targetRepositoryID: repositoryID,
                targetWorkspaceID: workspaceID
            )

        case .requestWorkspaceSelectionAtIndex(let index):
            guard let target = state.visibleNavigatorWorkspaces[safe: index] else { return .none }
            return setWorkspaceTransitionRequest(
                state: &state,
                targetRepositoryID: target.repositoryID,
                targetWorkspaceID: target.workspace.id
            )

        case .requestAdjacentWorkspaceSelection(let offset):
            guard let target = state.adjacentVisibleWorkspace(offset: offset) else { return .none }
            return setWorkspaceTransitionRequest(
                state: &state,
                targetRepositoryID: target.repositoryID,
                targetWorkspaceID: target.workspace.id
            )

        case .setWorkspaceTransitionRequest(let request):
            state.workspaceTransitionRequest = request
            return .none

        case let .requestWorkspaceDiscard(workspaceID, repositoryID):
            return setWorkspaceDiscardRequest(
                state: &state,
                workspaceID: workspaceID,
                repositoryID: repositoryID
            )

        case .setWorkspaceDiscardRequest(let request):
            state.workspaceDiscardRequest = request
            return .none

        case .requestInitializeRepository(let repositoryID):
            return setInitializeRepositoryRequest(state: &state, repositoryID: repositoryID)

        case .setInitializeRepositoryRequest(let request):
            state.initializeRepositoryRequest = request
            return .none

        default:
            return .none
        }
    }

    func reduceShellPresentationAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .setActiveSheet(let sheet):
            state.activeSheet = sheet
            return .none

        case .setSearchPresentation(let presentation):
            state.searchPresentation = presentation
            return .none

        case .setNotificationsPanelPresented(let isPresented):
            state.isNotificationsPanelPresented = isPresented
            if isPresented {
                state.activeSheet = .notifications
            } else if state.activeSheet == .notifications {
                state.activeSheet = nil
            }
            return .none

        case .clearErrorMessage:
            state.lastErrorMessage = nil
            return .none

        default:
            return .none
        }
    }
}

private func makeRelaunchSettingsSnapshot(
    from settings: GlobalSettings
) -> RelaunchSettingsSnapshot {
    RelaunchSettingsSnapshot(
        restoreRepositoriesOnLaunch: settings.restore.restoreRepositoriesOnLaunch,
        restoreSelectedWorkspace: settings.restore.restoreSelectedWorkspace,
        restoreWorkspaceLayoutAndTabs: settings.restore.restoreWorkspaceLayoutAndTabs,
        restoreTerminalSessions: settings.restore.restoreTerminalSessions,
        restoreChatSessions: settings.restore.restoreChatSessions
    )
}

private func sortedUUIDs(_ ids: Set<UUID>) -> [UUID] {
    ids.sorted { lhs, rhs in
        lhs.uuidString < rhs.uuidString
    }
}

private extension WindowFeature {
    func makeWorkspaceTransitionRequest(
        state: State,
        targetRepositoryID: Repository.ID,
        targetWorkspaceID: Workspace.ID?
    ) -> WorkspaceTransitionRequest? {
        let sourceRepositoryID = state.selectedRepositoryID
        let sourceWorkspaceID = state.selectedWorkspaceID
        let isSameRepository = sourceRepositoryID == targetRepositoryID
        let isSameWorkspace = sourceWorkspaceID == targetWorkspaceID

        if isSameRepository, isSameWorkspace {
            return nil
        }

        let didSwitchRepository = sourceRepositoryID != targetRepositoryID
        let requiresBlockingTargetRefresh = targetWorkspaceID.flatMap { workspaceID in
            state.worktreesByRepository[targetRepositoryID]?.contains { $0.id == workspaceID } == true
                ? nil
                : workspaceID
        } != nil
        let refreshStrategy: WorkspaceTransitionCatalogRefreshStrategy =
            if requiresBlockingTargetRefresh {
                .blockingTargetWorkspace
            } else if targetWorkspaceID == nil {
                .retryIfSelectionMissing
            } else {
                .none
            }

        return WorkspaceTransitionRequest(
            sourceRepositoryID: sourceRepositoryID,
            sourceWorkspaceID: sourceWorkspaceID,
            targetRepositoryID: targetRepositoryID,
            targetWorkspaceID: targetWorkspaceID,
            requiresRepositoryConfirmation: didSwitchRepository && sourceRepositoryID != nil,
            shouldPersistVisibleWorkspaceState: sourceWorkspaceID != nil && !isSameWorkspace,
            shouldResetHostWorkspaceState: didSwitchRepository,
            catalogRefreshStrategy: refreshStrategy,
            shouldScheduleDeferredRefresh: didSwitchRepository
                && targetWorkspaceID != nil
                && refreshStrategy == .none,
            id: uuid()
        )
    }

    func setWorkspaceTransitionRequest(
        state: inout State,
        targetRepositoryID: Repository.ID,
        targetWorkspaceID: Workspace.ID?
    ) -> Effect<Action> {
        state.workspaceTransitionRequest = makeWorkspaceTransitionRequest(
            state: state,
            targetRepositoryID: targetRepositoryID,
            targetWorkspaceID: targetWorkspaceID
        )
        return .none
    }

    func setWorkspaceDiscardRequest(
        state: inout State,
        workspaceID: Workspace.ID,
        repositoryID: Repository.ID
    ) -> Effect<Action> {
        state.workspaceDiscardRequest = WorkspaceDiscardRequest(
            workspaceID: workspaceID,
            repositoryID: repositoryID,
            id: uuid()
        )
        return .none
    }

    func setInitializeRepositoryRequest(
        state: inout State,
        repositoryID: Repository.ID
    ) -> Effect<Action> {
        state.initializeRepositoryRequest = InitializeRepositoryRequest(
            repositoryID: repositoryID,
            id: uuid()
        )
        return .none
    }
}
