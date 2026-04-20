import ComposableArchitecture
import Dependencies
import Foundation
import RemoteCore
import SSH

@Reducer
public struct RemoteTerminalFeature: Sendable {
    public init() {}

    @ObservableState
    public struct State: Equatable, Sendable {
        public var repositories: [RemoteRepositoryRecord] = []
        public var worktreesByRepository: [RemoteRepositoryAuthority.ID: [RemoteWorktree]] = [:]
        public var shellSessionsByRepository: [RemoteRepositoryAuthority.ID: [SSHRemoteShellSession]] = [:]
        public var selectedRepositoryID: RemoteRepositoryAuthority.ID?
        public var selectedWorktreeID: RemoteWorktree.ID?
        public var isSettingsPresented = false
        public var activeSession: ActiveRemoteSession?
        public var repositoryEditor: RemoteRepositoryEditorDraft?
        public var worktreeCreationRepositoryID: RemoteRepositoryAuthority.ID?
        public var hostTrustPrompt: RemoteHostTrustPrompt?
        public var pendingOperation: RemotePendingOperation?
        public var trustedHostsCount = 0
        public var isBootstrapping = false
        public var lastErrorMessage: String?

        public init() {}

        public var selectedRepository: RemoteRepositoryRecord? {
            guard let selectedRepositoryID else { return nil }
            return repositories.first { $0.id == selectedRepositoryID }
        }

        public var selectedWorktrees: [RemoteWorktree] {
            guard let selectedRepositoryID else { return [] }
            return worktreesByRepository[selectedRepositoryID] ?? []
        }

        public var selectedWorktree: RemoteWorktree? {
            guard let selectedWorktreeID else { return nil }
            return selectedWorktrees.first { $0.id == selectedWorktreeID }
        }

        public var selectedWorktreeShellSessions: [SSHRemoteShellSession] {
            guard let selectedRepositoryID, let selectedWorktreeID else { return [] }
            return (shellSessionsByRepository[selectedRepositoryID] ?? [])
                .filter { $0.worktreeID == selectedWorktreeID }
        }

        public var discoveredSessions: [SSHRemoteShellSession] {
            repositories.flatMap { shellSessionsByRepository[$0.id] ?? [] }
        }
    }

    public enum Action: Equatable, BindableAction, Sendable {
        case binding(BindingAction<State>)
        case task
        case bootstrapLoaded(
            repositories: [RemoteRepositoryRecord],
            trustedHostsCount: Int
        )
        case bootstrapFailed(String)
        case selectRepository(RemoteRepositoryAuthority.ID?)
        case selectWorktree(RemoteWorktree.ID?)
        case presentSettings
        case dismissSettings
        case presentNewRepository
        case presentEditRepository(RemoteRepositoryAuthority.ID)
        case dismissRepositoryEditor
        case saveRepository(RemoteRepositoryRecord)
        case removeRepository(RemoteRepositoryAuthority.ID)
        case presentWorktreeCreation(RemoteRepositoryAuthority.ID)
        case dismissWorktreeCreation
        case createWorktree(RemoteWorktreeDraft)
        case setRemoteWorktrees(RemoteRepositoryAuthority.ID, [RemoteWorktree])
        case setShellSessions(RemoteRepositoryAuthority.ID, [SSHRemoteShellSession])
        case refreshRepository(RemoteRepositoryAuthority.ID)
        case fetchRepository(RemoteRepositoryAuthority.ID)
        case pullWorktree(repositoryID: RemoteRepositoryAuthority.ID, worktreeID: RemoteWorktree.ID)
        case pushWorktree(repositoryID: RemoteRepositoryAuthority.ID, worktreeID: RemoteWorktree.ID)
        case discoverShellSessions(RemoteRepositoryAuthority.ID)
        case openSession(repositoryID: RemoteRepositoryAuthority.ID, worktreeID: RemoteWorktree.ID)
        case shellSessionPrepared(SSHRemotePreparedShellSession)
        case reconnectActiveSession
        case activeSessionReconnectReady(UUID)
        case dismissActiveSession
        case hostTrustRequired(RemoteHostTrustPrompt, RemotePendingOperation)
        case resolveHostTrust(Bool)
        case trustedHostsCountLoaded(Int)
        case clearTrustedHosts
        case setErrorMessage(String?)
    }

    @Dependency(\.remoteRepositoryStoreClient) var repositoryStoreClient
    @Dependency(\.remoteWorkspaceClient) var workspaceClient
    @Dependency(\.uuid) var uuid

    public var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .task:
                state.isBootstrapping = true
                state.lastErrorMessage = nil
                return .run { send in
                    do {
                        let repositories = try await repositoryStoreClient.load()
                        let trustedHostsCount = try await workspaceClient.trustedHostsCount()
                        await send(
                            .bootstrapLoaded(
                                repositories: repositories,
                                trustedHostsCount: trustedHostsCount
                            )
                        )
                    } catch {
                        await send(.bootstrapFailed(error.localizedDescription))
                    }
                }

            case let .bootstrapLoaded(repositories, trustedHostsCount):
                state.isBootstrapping = false
                state.repositories = repositories
                state.trustedHostsCount = trustedHostsCount
                if state.selectedRepositoryID == nil {
                    state.selectedRepositoryID = repositories.first?.id
                }
                return .merge(
                    repositories.map { record in
                        .send(.refreshRepository(record.id))
                    }
                )

            case let .bootstrapFailed(message):
                state.isBootstrapping = false
                state.lastErrorMessage = message
                return .none

            case let .selectRepository(repositoryID):
                if state.selectedRepositoryID != repositoryID {
                    state.selectedWorktreeID = nil
                }
                state.selectedRepositoryID = repositoryID
                return .none

            case let .selectWorktree(worktreeID):
                state.selectedWorktreeID = worktreeID
                return .none

            case .presentSettings:
                state.isSettingsPresented = true
                return .none

            case .dismissSettings:
                state.isSettingsPresented = false
                return .none

            case .presentNewRepository:
                state.repositoryEditor = RemoteRepositoryEditorDraft()
                return .none

            case let .presentEditRepository(repositoryID):
                guard let record = repositoryRecord(in: state, repositoryID: repositoryID) else {
                    return .none
                }
                state.repositoryEditor = RemoteRepositoryEditorDraft(record: record)
                return .none

            case .dismissRepositoryEditor:
                state.repositoryEditor = nil
                return .none

            case let .saveRepository(record):
                let originalRepositoryID = state.repositoryEditor?.originalRepositoryID
                if let originalRepositoryID,
                   originalRepositoryID != record.id {
                    state.repositories.removeAll { $0.id == originalRepositoryID }
                    state.worktreesByRepository.removeValue(forKey: originalRepositoryID)
                    state.shellSessionsByRepository.removeValue(forKey: originalRepositoryID)
                    if state.selectedRepositoryID == originalRepositoryID {
                        state.selectedRepositoryID = nil
                    }
                }

                if let index = state.repositories.firstIndex(where: { $0.id == record.id }) {
                    state.repositories[index] = record
                } else {
                    state.repositories.append(record)
                }

                state.selectedRepositoryID = record.id
                state.repositoryEditor = nil
                return .merge(
                    saveRepositoriesEffect(state.repositories),
                    .send(.refreshRepository(record.id))
                )

            case let .removeRepository(repositoryID):
                state.repositories.removeAll { $0.id == repositoryID }
                state.worktreesByRepository.removeValue(forKey: repositoryID)
                state.shellSessionsByRepository.removeValue(forKey: repositoryID)
                if state.selectedRepositoryID == repositoryID {
                    state.selectedRepositoryID = state.repositories.first?.id
                    state.selectedWorktreeID = nil
                }
                if state.activeSession?.repositoryID == repositoryID {
                    state.activeSession = nil
                }
                return saveRepositoriesEffect(state.repositories)

            case let .presentWorktreeCreation(repositoryID):
                state.worktreeCreationRepositoryID = repositoryID
                return .none

            case .dismissWorktreeCreation:
                state.worktreeCreationRepositoryID = nil
                return .none

            case let .createWorktree(draft):
                return createWorktreeEffect(state: state, draft: draft)

            case let .setRemoteWorktrees(repositoryID, worktrees):
                state.worktreesByRepository[repositoryID] = worktrees
                if state.selectedRepositoryID == repositoryID,
                   let selectedWorktreeID = state.selectedWorktreeID,
                   worktrees.contains(where: { $0.id == selectedWorktreeID }) == false {
                    state.selectedWorktreeID = nil
                }
                if let activeSession = state.activeSession,
                   activeSession.repositoryID == repositoryID,
                   worktrees.contains(where: { $0.id == activeSession.worktreeID }) == false {
                    state.activeSession = nil
                }
                return .send(.discoverShellSessions(repositoryID))

            case let .setShellSessions(repositoryID, sessions):
                state.shellSessionsByRepository[repositoryID] = sessions
                if let activeSession = state.activeSession,
                   activeSession.repositoryID == repositoryID,
                   let refreshed = sessions.first(where: { $0.id == activeSession.id }) {
                    state.activeSession?.session = refreshed
                }
                return .none

            case let .refreshRepository(repositoryID):
                return refreshRepositoryEffect(state: state, repositoryID: repositoryID)

            case let .fetchRepository(repositoryID):
                return fetchRepositoryEffect(state: state, repositoryID: repositoryID)

            case let .pullWorktree(repositoryID, worktreeID):
                return pullWorktreeEffect(
                    state: state,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID
                )

            case let .pushWorktree(repositoryID, worktreeID):
                return pushWorktreeEffect(
                    state: state,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID
                )

            case let .discoverShellSessions(repositoryID):
                return discoverShellSessionsEffect(state: state, repositoryID: repositoryID)

            case let .openSession(repositoryID, worktreeID):
                return openSessionEffect(
                    state: state,
                    repositoryID: repositoryID,
                    worktreeID: worktreeID
                )

            case let .shellSessionPrepared(prepared):
                state.activeSession = ActiveRemoteSession(
                    session: prepared.session,
                    remoteAttachCommand: prepared.remoteAttachCommand,
                    connectRequestID: uuid()
                )
                return .send(.discoverShellSessions(prepared.session.repositoryID))

            case .reconnectActiveSession:
                return reconnectActiveSessionEffect(state: state)

            case let .activeSessionReconnectReady(requestID):
                state.activeSession?.connectRequestID = requestID
                state.activeSession?.errorMessage = nil
                return .none

            case .dismissActiveSession:
                state.activeSession = nil
                return .none

            case let .hostTrustRequired(prompt, pendingOperation):
                state.hostTrustPrompt = prompt
                state.pendingOperation = pendingOperation
                return .none

            case let .resolveHostTrust(trust):
                guard let prompt = state.hostTrustPrompt else { return .none }
                let pending = state.pendingOperation
                state.hostTrustPrompt = nil
                state.pendingOperation = nil
                guard trust else {
                    state.lastErrorMessage = "Host trust was rejected."
                    return .none
                }
                return .run { send in
                    do {
                        try await workspaceClient.trustHost(prompt.context)
                        let count = try await workspaceClient.trustedHostsCount()
                        await send(.trustedHostsCountLoaded(count))
                        if let pending {
                            for action in retryActions(for: pending) {
                                await send(action)
                            }
                        }
                    } catch {
                        await send(.setErrorMessage(error.localizedDescription))
                    }
                }

            case let .trustedHostsCountLoaded(count):
                state.trustedHostsCount = count
                return .none

            case .clearTrustedHosts:
                return .run { send in
                    do {
                        try await workspaceClient.clearTrustedHosts()
                        let count = try await workspaceClient.trustedHostsCount()
                        await send(.trustedHostsCountLoaded(count))
                    } catch {
                        await send(.setErrorMessage(error.localizedDescription))
                    }
                }

            case let .setErrorMessage(message):
                state.lastErrorMessage = message
                state.activeSession?.errorMessage = message
                return .none
            }
        }
    }
}

extension RemoteTerminalFeature {
    func refreshRepositoryEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: repositoryID) else {
            return .none
        }
        return .run { send in
            do {
                let worktrees = try await workspaceClient.refreshWorktrees(repository)
                await send(.setRemoteWorktrees(repositoryID, worktrees))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .refreshRepository(repositoryID),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func fetchRepositoryEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: repositoryID) else {
            return .none
        }
        return .run { send in
            do {
                try await workspaceClient.fetch(repository)
                let worktrees = try await workspaceClient.refreshWorktrees(repository)
                await send(.setRemoteWorktrees(repositoryID, worktrees))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .fetchRepository(repositoryID),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func pullWorktreeEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID,
        worktreeID: RemoteWorktree.ID
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: repositoryID),
              let worktree = worktree(in: state, repositoryID: repositoryID, worktreeID: worktreeID)
        else {
            return .none
        }
        return .run { send in
            do {
                try await workspaceClient.pull(repository, worktree)
                let worktrees = try await workspaceClient.refreshWorktrees(repository)
                await send(.setRemoteWorktrees(repositoryID, worktrees))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .pullWorktree(repositoryID: repositoryID, worktreeID: worktreeID),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func pushWorktreeEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID,
        worktreeID: RemoteWorktree.ID
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: repositoryID),
              let worktree = worktree(in: state, repositoryID: repositoryID, worktreeID: worktreeID)
        else {
            return .none
        }
        return .run { send in
            do {
                try await workspaceClient.push(repository, worktree)
                let worktrees = try await workspaceClient.refreshWorktrees(repository)
                await send(.setRemoteWorktrees(repositoryID, worktrees))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .pushWorktree(repositoryID: repositoryID, worktreeID: worktreeID),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func discoverShellSessionsEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: repositoryID) else {
            return .none
        }
        let worktrees = state.worktreesByRepository[repositoryID] ?? []
        return .run { send in
            do {
                let sessions = try await workspaceClient.discoverShellSessions(repository, worktrees)
                await send(.setShellSessions(repositoryID, sessions))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .discoverShellSessions(repositoryID),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func createWorktreeEffect(
        state: State,
        draft: RemoteWorktreeDraft
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: draft.repositoryID) else {
            return .none
        }
        return .run { send in
            do {
                _ = try await workspaceClient.createWorktree(repository, draft)
                let worktrees = try await workspaceClient.refreshWorktrees(repository)
                await send(.setRemoteWorktrees(repository.id, worktrees))
                await send(.dismissWorktreeCreation)
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .createWorktree(draft),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func openSessionEffect(
        state: State,
        repositoryID: RemoteRepositoryAuthority.ID,
        worktreeID: RemoteWorktree.ID
    ) -> Effect<Action> {
        guard let repository = repositoryRecord(in: state, repositoryID: repositoryID),
              let worktree = worktree(in: state, repositoryID: repositoryID, worktreeID: worktreeID)
        else {
            return .none
        }

        return .run { send in
            do {
                let prepared = try await workspaceClient.prepareShellSession(repository, worktree)
                await send(.shellSessionPrepared(prepared))
            } catch let error as RemoteWorkspaceClientError {
                await sendRemoteWorkspaceError(
                    error,
                    pendingOperation: .openSession(repositoryID: repositoryID, worktreeID: worktreeID),
                    send: send
                )
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func saveRepositoriesEffect(
        _ repositories: [RemoteRepositoryRecord]
    ) -> Effect<Action> {
        .run { send in
            do {
                try await repositoryStoreClient.save(repositories)
            } catch {
                await send(.setErrorMessage(error.localizedDescription))
            }
        }
    }

    func repositoryRecord(
        in state: State,
        repositoryID: RemoteRepositoryAuthority.ID
    ) -> RemoteRepositoryRecord? {
        state.repositories.first { $0.id == repositoryID }
    }

    func worktree(
        in state: State,
        repositoryID: RemoteRepositoryAuthority.ID,
        worktreeID: RemoteWorktree.ID
    ) -> RemoteWorktree? {
        state.worktreesByRepository[repositoryID]?.first { $0.id == worktreeID }
    }
}
