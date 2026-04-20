import ComposableArchitecture

extension RemoteTerminalFeature {
    func reconnectActiveSessionEffect(
        state: State
    ) -> Effect<Action> {
        guard let activeSession = state.activeSession,
              let repository = repositoryRecord(
                in: state,
                repositoryID: activeSession.repositoryID
              )
        else {
            return .none
        }

        return .run { [requestID = uuid()] send in
            do {
                try await workspaceClient.validateShellConnection(repository)
                await send(.activeSessionReconnectReady(requestID))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .reconnectActiveSession,
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func sendRemoteWorkspaceError(
        _ error: RemoteWorkspaceClientError,
        pendingOperation: RemotePendingOperation,
        send: Send<Action>
    ) async {
        switch error {
        case .hostTrustRequired(let context):
            await send(
                .hostTrustRequired(
                    RemoteHostTrustPrompt(context: context),
                    pendingOperation
                )
            )
        case .message(let message):
            await send(.setErrorMessage(message))
        }
    }

    func retryActions(
        for operation: RemotePendingOperation
    ) -> [Action] {
        switch operation {
        case .refreshRepository(let repositoryID):
            [.refreshRepository(repositoryID)]
        case .fetchRepository(let repositoryID):
            [.fetchRepository(repositoryID)]
        case let .pullWorktree(repositoryID, worktreeID):
            [.pullWorktree(repositoryID: repositoryID, worktreeID: worktreeID)]
        case let .pushWorktree(repositoryID, worktreeID):
            [.pushWorktree(repositoryID: repositoryID, worktreeID: worktreeID)]
        case .discoverShellSessions(let repositoryID):
            [.discoverShellSessions(repositoryID)]
        case .createWorktree(let draft):
            [.createWorktree(draft)]
        case let .openSession(repositoryID, worktreeID):
            [.openSession(repositoryID: repositoryID, worktreeID: worktreeID)]
        case .reconnectActiveSession:
            [.reconnectActiveSession]
        }
    }
}
