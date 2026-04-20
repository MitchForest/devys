import Dependencies
import Foundation
import RemoteCore

public struct RemoteTerminalWorkspaceClient: Sendable {
    public var refreshWorktrees: @MainActor @Sendable (RemoteRepositoryAuthority) async throws -> [RemoteWorktree]
    public var createWorktree: @MainActor @Sendable (
        RemoteRepositoryAuthority,
        RemoteWorktreeDraft
    ) async throws -> RemoteWorktree
    public var fetch: @MainActor @Sendable (RemoteRepositoryAuthority) async throws -> [RemoteWorktree]
    public var pull: @MainActor @Sendable (RemoteRepositoryAuthority, RemoteWorktree) async throws -> [RemoteWorktree]
    public var push: @MainActor @Sendable (RemoteRepositoryAuthority, RemoteWorktree) async throws -> [RemoteWorktree]
    public var prepareShellLaunch: @MainActor @Sendable (
        RemoteRepositoryAuthority,
        RemoteWorktree
    ) async throws -> String

    public init(
        refreshWorktrees: @escaping @MainActor @Sendable (RemoteRepositoryAuthority) async throws -> [RemoteWorktree],
        createWorktree: @escaping @MainActor @Sendable (
            RemoteRepositoryAuthority,
            RemoteWorktreeDraft
        ) async throws -> RemoteWorktree,
        fetch: @escaping @MainActor @Sendable (RemoteRepositoryAuthority) async throws -> [RemoteWorktree],
        pull: @escaping @MainActor @Sendable (
            RemoteRepositoryAuthority,
            RemoteWorktree
        ) async throws -> [RemoteWorktree],
        push: @escaping @MainActor @Sendable (
            RemoteRepositoryAuthority,
            RemoteWorktree
        ) async throws -> [RemoteWorktree],
        prepareShellLaunch: @escaping @MainActor @Sendable (
            RemoteRepositoryAuthority,
            RemoteWorktree
        ) async throws -> String
    ) {
        self.refreshWorktrees = refreshWorktrees
        self.createWorktree = createWorktree
        self.fetch = fetch
        self.pull = pull
        self.push = push
        self.prepareShellLaunch = prepareShellLaunch
    }
}

extension RemoteTerminalWorkspaceClient: DependencyKey {
    public static let liveValue = Self(
        refreshWorktrees: { _ in [] },
        createWorktree: { repository, draft in
            RemoteWorktree(
                repositoryID: repository.id,
                branchName: draft.branchName,
                remotePath: "",
                isPrimary: false
            )
        },
        fetch: { _ in [] },
        pull: { _, _ in [] },
        push: { _, _ in [] },
        prepareShellLaunch: { _, _ in "" }
    )
}

extension RemoteTerminalWorkspaceClient: TestDependencyKey {
    public static let testValue = liveValue
}

public extension DependencyValues {
    var remoteTerminalWorkspaceClient: RemoteTerminalWorkspaceClient {
        get { self[RemoteTerminalWorkspaceClient.self] }
        set { self[RemoteTerminalWorkspaceClient.self] = newValue }
    }
}
