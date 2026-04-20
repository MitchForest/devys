import ComposableArchitecture
import Foundation
import RemoteCore
import Split
import Workspace

extension WindowFeature {
    func reduceRemoteOperationAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestRemoteWorktreeSelection,
             .setRemoteWorkspaceTransitionRequest:
            return reduceRemoteSelectionAction(state: &state, action: action)

        case .refreshRemoteRepository,
             .refreshRemoteRepositoryResponse,
             .createRemoteWorktree,
             .createRemoteWorktreeResponse,
             .fetchRemoteRepository,
             .fetchRemoteRepositoryResponse,
             .pullRemoteWorktree,
             .pullRemoteWorktreeResponse,
             .pushRemoteWorktree,
             .pushRemoteWorktreeResponse:
            return reduceRemoteRepositoryAction(state: &state, action: action)

        case .requestOpenRemoteTerminal,
             .remoteTerminalLaunchPrepared,
             .setRemoteTerminalLaunchRequest:
            return reduceRemoteTerminalLaunchAction(state: &state, action: action)

        default:
            return .none
        }
    }
}

private extension WindowFeature {
    func reduceRemoteSelectionAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case let .requestRemoteWorktreeSelection(repositoryID, workspaceID):
            return setRemoteWorkspaceTransitionRequest(
                state: &state,
                targetRepositoryID: repositoryID,
                targetWorkspaceID: workspaceID
            )

        case .setRemoteWorkspaceTransitionRequest(let request):
            state.remoteWorkspaceTransitionRequest = request
            return .none

        default:
            return .none
        }
    }

    func reduceRemoteRepositoryAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .refreshRemoteRepository(let repositoryID):
            return refreshRemoteRepositoryEffect(state: state, repositoryID: repositoryID)

        case let .refreshRemoteRepositoryResponse(repositoryID, result):
            return reduceRemoteWorktreeResult(
                state: &state,
                repositoryID: repositoryID,
                result: result
            )

        case .createRemoteWorktree(let draft):
            return createRemoteWorktreeEffect(state: state, draft: draft)

        case let .createRemoteWorktreeResponse(result):
            return reduceCreateRemoteWorktreeResponse(state: &state, result: result)

        case .fetchRemoteRepository(let repositoryID):
            return fetchRemoteRepositoryEffect(state: state, repositoryID: repositoryID)

        case let .fetchRemoteRepositoryResponse(repositoryID, result):
            return reduceRemoteWorktreeResult(
                state: &state,
                repositoryID: repositoryID,
                result: result
            )

        case let .pullRemoteWorktree(repositoryID, workspaceID):
            return pullRemoteWorktreeEffect(
                state: state,
                repositoryID: repositoryID,
                workspaceID: workspaceID
            )

        case let .pullRemoteWorktreeResponse(repositoryID, result):
            return reduceRemoteWorktreeResult(
                state: &state,
                repositoryID: repositoryID,
                result: result
            )

        case let .pushRemoteWorktree(repositoryID, workspaceID):
            return pushRemoteWorktreeEffect(
                state: state,
                repositoryID: repositoryID,
                workspaceID: workspaceID
            )

        case let .pushRemoteWorktreeResponse(repositoryID, result):
            return reduceRemoteWorktreeResult(
                state: &state,
                repositoryID: repositoryID,
                result: result
            )

        default:
            return .none
        }
    }

    func reduceRemoteTerminalLaunchAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .requestOpenRemoteTerminal(let preferredPaneID):
            return requestOpenRemoteTerminalEffect(
                state: state,
                preferredPaneID: preferredPaneID
            )

        case let .remoteTerminalLaunchPrepared(result):
            return reduceRemoteTerminalLaunchPrepared(state: &state, result: result)

        case .setRemoteTerminalLaunchRequest(let request):
            state.remoteTerminalLaunchRequest = request
            return .none

        default:
            return .none
        }
    }

    func setRemoteWorkspaceTransitionRequest(
        state: inout State,
        targetRepositoryID: RemoteRepositoryAuthority.ID,
        targetWorkspaceID: Workspace.ID
    ) -> Effect<Action> {
        state.remoteWorkspaceTransitionRequest = makeRemoteWorkspaceTransitionRequest(
            state: state,
            targetRepositoryID: targetRepositoryID,
            targetWorkspaceID: targetWorkspaceID
        )
        return .none
    }

    func refreshRemoteRepositoryEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID
    ) -> Effect<Action> {
        guard let repository = state.remoteRepositories.first(where: { $0.id == repositoryID }) else {
            return .none
        }
        let client = remoteTerminalWorkspaceClient
        return .run { send in
            await send(
                .refreshRemoteRepositoryResponse(
                    repositoryID: repositoryID,
                    result: TaskResult {
                        try await client.refreshWorktrees(repository)
                    }
                )
            )
        }
    }

    func createRemoteWorktreeEffect(
        state: State,
        draft: RemoteWorktreeDraft
    ) -> Effect<Action> {
        guard let repository = state.remoteRepositories.first(where: { $0.id == draft.repositoryID }) else {
            return .none
        }
        let client = remoteTerminalWorkspaceClient
        return .run { send in
            await send(
                .createRemoteWorktreeResponse(
                    TaskResult {
                        let createdWorktree = try await client.createWorktree(repository, draft)
                        let worktrees = try await client.refreshWorktrees(repository)
                        return RemoteWorktreeCreationResult(
                            createdWorktree: createdWorktree,
                            worktrees: worktrees
                        )
                    }
                )
            )
        }
    }

    func fetchRemoteRepositoryEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID
    ) -> Effect<Action> {
        guard let repository = state.remoteRepositories.first(where: { $0.id == repositoryID }) else {
            return .none
        }
        let client = remoteTerminalWorkspaceClient
        return .run { send in
            await send(
                .fetchRemoteRepositoryResponse(
                    repositoryID: repositoryID,
                    result: TaskResult {
                        try await client.fetch(repository)
                    }
                )
            )
        }
    }

    func pullRemoteWorktreeEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID,
        workspaceID: RemoteWorktree.ID
    ) -> Effect<Action> {
        guard let repository = state.remoteRepositories.first(where: { $0.id == repositoryID }),
              let worktree = state.remoteWorktreesByRepository[repositoryID]?.first(where: { $0.id == workspaceID })
        else {
            return .none
        }
        let client = remoteTerminalWorkspaceClient
        return .run { send in
            await send(
                .pullRemoteWorktreeResponse(
                    repositoryID: repositoryID,
                    result: TaskResult {
                        try await client.pull(repository, worktree)
                    }
                )
            )
        }
    }

    func pushRemoteWorktreeEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID,
        workspaceID: RemoteWorktree.ID
    ) -> Effect<Action> {
        guard let repository = state.remoteRepositories.first(where: { $0.id == repositoryID }),
              let worktree = state.remoteWorktreesByRepository[repositoryID]?.first(where: { $0.id == workspaceID })
        else {
            return .none
        }
        let client = remoteTerminalWorkspaceClient
        return .run { send in
            await send(
                .pushRemoteWorktreeResponse(
                    repositoryID: repositoryID,
                    result: TaskResult {
                        try await client.push(repository, worktree)
                    }
                )
            )
        }
    }

    func requestOpenRemoteTerminalEffect(
        state: State,
        preferredPaneID: PaneID?
    ) -> Effect<Action> {
        guard let repository = state.selectedRemoteRepository,
              let worktree = state.selectedRemoteWorktree else {
            return .none
        }
        let client = remoteTerminalWorkspaceClient
        let requestID = uuid()
        return .run { send in
            await send(
                .remoteTerminalLaunchPrepared(
                    TaskResult {
                        let launch = try await client.prepareShellLaunch(repository, worktree)
                        return RemoteTerminalLaunchRequest(
                            workspaceID: worktree.id,
                            attachCommand: launch,
                            preferredPaneID: preferredPaneID,
                            id: requestID
                        )
                    }
                )
            )
        }
    }

    func reduceRemoteWorktreeResult(
        state: inout State,
        repositoryID: RemoteRepositoryAuthority.ID,
        result: TaskResult<[RemoteWorktree]>
    ) -> Effect<Action> {
        switch result {
        case .success(let worktrees):
            state.remoteWorktreesByRepository[repositoryID] = worktrees
            state.normalizeSelection()
        case .failure(let error):
            state.lastErrorMessage = error.localizedDescription
        }
        return .none
    }

    func reduceCreateRemoteWorktreeResponse(
        state: inout State,
        result: TaskResult<RemoteWorktreeCreationResult>
    ) -> Effect<Action> {
        switch result {
        case .success(let created):
            let repositoryID = created.createdWorktree.repositoryID
            state.remoteWorktreesByRepository[repositoryID] = created.worktrees
            state.remoteWorktreeCreationPresentation = nil
            state.remoteWorkspaceTransitionRequest = makeRemoteWorkspaceTransitionRequest(
                state: state,
                targetRepositoryID: repositoryID,
                targetWorkspaceID: created.createdWorktree.id
            )
        case .failure(let error):
            state.lastErrorMessage = error.localizedDescription
        }
        return .none
    }

    func reduceRemoteTerminalLaunchPrepared(
        state: inout State,
        result: TaskResult<RemoteTerminalLaunchRequest>
    ) -> Effect<Action> {
        switch result {
        case .success(let request):
            state.remoteTerminalLaunchRequest = request
        case .failure(let error):
            state.lastErrorMessage = error.localizedDescription
        }
        return .none
    }

    func makeRemoteWorkspaceTransitionRequest(
        state: State,
        targetRepositoryID: RemoteRepositoryAuthority.ID,
        targetWorkspaceID: Workspace.ID
    ) -> RemoteWorkspaceTransitionRequest? {
        let isSameSelection = state.selectedRemoteRepositoryID == targetRepositoryID
            && state.selectedRemoteWorktreeID == targetWorkspaceID
        guard !isSameSelection else {
            return nil
        }

        let sourceWorkspaceID = state.selectedWorkspaceID
        let shouldTransitionWorkspaceState = sourceWorkspaceID != nil && sourceWorkspaceID != targetWorkspaceID
        return RemoteWorkspaceTransitionRequest(
            sourceWorkspaceID: sourceWorkspaceID,
            targetRepositoryID: targetRepositoryID,
            targetWorkspaceID: targetWorkspaceID,
            shouldPersistVisibleWorkspaceState: shouldTransitionWorkspaceState,
            shouldResetHostWorkspaceState: shouldTransitionWorkspaceState,
            id: uuid()
        )
    }
}
