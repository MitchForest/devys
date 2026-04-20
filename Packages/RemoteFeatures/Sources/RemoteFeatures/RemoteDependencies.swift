import Dependencies
import Foundation
import RemoteCore
import SSH

public enum RemoteWorkspaceClientError: Error, Sendable, Equatable, LocalizedError {
    case hostTrustRequired(SSHHostKeyValidationContext)
    case message(String)

    public var errorDescription: String? {
        switch self {
        case .hostTrustRequired:
            "Host trust is required."
        case .message(let message):
            message
        }
    }
}

public struct RemoteRepositoryStoreClient: Sendable {
    public var load: @Sendable () async throws -> [RemoteRepositoryRecord]
    public var save: @Sendable ([RemoteRepositoryRecord]) async throws -> Void

    public init(
        load: @escaping @Sendable () async throws -> [RemoteRepositoryRecord],
        save: @escaping @Sendable ([RemoteRepositoryRecord]) async throws -> Void
    ) {
        self.load = load
        self.save = save
    }
}

public struct RemoteWorkspaceClient: Sendable {
    public var refreshWorktrees: @Sendable (
        RemoteRepositoryRecord
    ) async throws -> [RemoteWorktree]
    public var createWorktree: @Sendable (
        RemoteRepositoryRecord,
        RemoteWorktreeDraft
    ) async throws -> RemoteWorktree
    public var fetch: @Sendable (RemoteRepositoryRecord) async throws -> Void
    public var pull: @Sendable (
        RemoteRepositoryRecord,
        RemoteWorktree
    ) async throws -> Void
    public var push: @Sendable (
        RemoteRepositoryRecord,
        RemoteWorktree
    ) async throws -> Void
    public var discoverShellSessions: @Sendable (
        RemoteRepositoryRecord,
        [RemoteWorktree]
    ) async throws -> [SSHRemoteShellSession]
    public var prepareShellSession: @Sendable (
        RemoteRepositoryRecord,
        RemoteWorktree
    ) async throws -> SSHRemotePreparedShellSession
    public var validateShellConnection: @Sendable (
        RemoteRepositoryRecord
    ) async throws -> Void
    public var trustedHostValidator: @Sendable () -> SSHHostKeyValidator?
    public var trustHost: @Sendable (SSHHostKeyValidationContext) async throws -> Void
    public var trustedHostsCount: @Sendable () async throws -> Int
    public var clearTrustedHosts: @Sendable () async throws -> Void

    public init(
        refreshWorktrees: @escaping @Sendable (RemoteRepositoryRecord) async throws -> [RemoteWorktree],
        createWorktree: @escaping @Sendable (
            RemoteRepositoryRecord,
            RemoteWorktreeDraft
        ) async throws -> RemoteWorktree,
        fetch: @escaping @Sendable (RemoteRepositoryRecord) async throws -> Void,
        pull: @escaping @Sendable (RemoteRepositoryRecord, RemoteWorktree) async throws -> Void,
        push: @escaping @Sendable (RemoteRepositoryRecord, RemoteWorktree) async throws -> Void,
        discoverShellSessions: @escaping @Sendable (
            RemoteRepositoryRecord,
            [RemoteWorktree]
        ) async throws -> [SSHRemoteShellSession],
        prepareShellSession: @escaping @Sendable (
            RemoteRepositoryRecord,
            RemoteWorktree
        ) async throws -> SSHRemotePreparedShellSession,
        validateShellConnection: @escaping @Sendable (
            RemoteRepositoryRecord
        ) async throws -> Void,
        trustedHostValidator: @escaping @Sendable () -> SSHHostKeyValidator?,
        trustHost: @escaping @Sendable (SSHHostKeyValidationContext) async throws -> Void,
        trustedHostsCount: @escaping @Sendable () async throws -> Int,
        clearTrustedHosts: @escaping @Sendable () async throws -> Void
    ) {
        self.refreshWorktrees = refreshWorktrees
        self.createWorktree = createWorktree
        self.fetch = fetch
        self.pull = pull
        self.push = push
        self.discoverShellSessions = discoverShellSessions
        self.prepareShellSession = prepareShellSession
        self.validateShellConnection = validateShellConnection
        self.trustedHostValidator = trustedHostValidator
        self.trustHost = trustHost
        self.trustedHostsCount = trustedHostsCount
        self.clearTrustedHosts = clearTrustedHosts
    }
}

extension RemoteRepositoryStoreClient: DependencyKey {
    public static let liveValue = Self(
        load: { [] },
        save: { _ in }
    )
}

extension RemoteRepositoryStoreClient: TestDependencyKey {
    public static let testValue = Self(
        load: { [] },
        save: { _ in }
    )
}

extension RemoteWorkspaceClient: DependencyKey {
    public static let liveValue = Self(
        refreshWorktrees: { _ in [] },
        createWorktree: { _, draft in
            RemoteWorktree(
                repositoryID: draft.repositoryID,
                branchName: draft.branchName,
                remotePath: "",
                isPrimary: false
            )
        },
        fetch: { _ in },
        pull: { _, _ in },
        push: { _, _ in },
        discoverShellSessions: { _, _ in [] },
        prepareShellSession: { repository, worktree in
            let session = SSHRemoteShellSession(
                repositoryID: repository.id,
                worktreeID: worktree.id,
                branchName: worktree.branchName,
                remotePath: worktree.remotePath,
                sessionName: RemoteSessionNaming.shellSessionName(
                    target: repository.authority.sshTarget,
                    remotePath: worktree.remotePath
                )
            )
            return SSHRemotePreparedShellSession(session: session, remoteAttachCommand: "")
        },
        validateShellConnection: { _ in },
        trustedHostValidator: { nil },
        trustHost: { _ in },
        trustedHostsCount: { 0 },
        clearTrustedHosts: {}
    )
}

extension RemoteWorkspaceClient: TestDependencyKey {
    public static let testValue = liveValue
}

public extension DependencyValues {
    var remoteRepositoryStoreClient: RemoteRepositoryStoreClient {
        get { self[RemoteRepositoryStoreClient.self] }
        set { self[RemoteRepositoryStoreClient.self] = newValue }
    }

    var remoteWorkspaceClient: RemoteWorkspaceClient {
        get { self[RemoteWorkspaceClient.self] }
        set { self[RemoteWorkspaceClient.self] = newValue }
    }
}
