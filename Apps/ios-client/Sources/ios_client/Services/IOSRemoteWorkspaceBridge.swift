import Foundation
import RemoteFeatures
import RemoteCore
import SSH

actor IOSRemoteWorkspaceBridge {
    private let service: SSHRemoteWorkspaceService
    private let knownHostsStore: IOSKnownHostsStore

    init(
        service: SSHRemoteWorkspaceService = SSHRemoteWorkspaceService(),
        knownHostsStore: IOSKnownHostsStore
    ) {
        self.service = service
        self.knownHostsStore = knownHostsStore
    }

    func refreshWorktrees(
        _ repository: RemoteRepositoryRecord
    ) async throws -> [RemoteWorktree] {
        try await perform { validator in
            try await self.service.refreshWorktrees(
                repository: repository.authority,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        }
    }

    func createWorktree(
        _ repository: RemoteRepositoryRecord,
        draft: RemoteWorktreeDraft
    ) async throws -> RemoteWorktree {
        try await perform { validator in
            try await self.service.createWorktree(
                repository: repository.authority,
                draft: draft,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        }
    }

    func fetch(
        _ repository: RemoteRepositoryRecord
    ) async throws {
        _ = try await perform { validator in
            try await self.service.fetch(
                repository: repository.authority,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        } as Void
    }

    func pull(
        _ repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) async throws {
        _ = try await perform { validator in
            try await self.service.pull(
                worktree: worktree,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        } as Void
    }

    func push(
        _ repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) async throws {
        _ = try await perform { validator in
            try await self.service.push(
                worktree: worktree,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        } as Void
    }

    func discoverShellSessions(
        _ repository: RemoteRepositoryRecord,
        worktrees: [RemoteWorktree]
    ) async throws -> [SSHRemoteShellSession] {
        try await perform { validator in
            try await self.service.discoverShellSessions(
                repository: repository.authority,
                worktrees: worktrees,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        }
    }

    func prepareShellSession(
        _ repository: RemoteRepositoryRecord,
        worktree: RemoteWorktree
    ) async throws -> SSHRemotePreparedShellSession {
        try await perform { validator in
            try await self.service.prepareShellSession(
                repository: repository.authority,
                worktree: worktree,
                connection: repository.connection,
                hostKeyValidator: validator
            )
        }
    }

    func validateShellConnection(
        _ repository: RemoteRepositoryRecord
    ) async throws {
        _ = try await perform { validator in
            try await self.service.validateShellConnection(
                connection: repository.connection,
                hostKeyValidator: validator
            )
        } as Void
    }

    func trustHost(
        _ context: SSHHostKeyValidationContext
    ) async throws {
        try await knownHostsStore.trust(context)
    }

    func trustedHostsCount() async throws -> Int {
        try await knownHostsStore.count()
    }

    func clearTrustedHosts() async throws {
        try await knownHostsStore.clear()
    }

    nonisolated static func makeTrustedHostValidator(
        knownHostsStore: IOSKnownHostsStore
    ) -> SSHHostKeyValidator {
        { context in
            do {
                if let trusted = try await knownHostsStore.trustedContext(
                    host: context.host,
                    port: context.port
                ),
                   trusted.fingerprintSHA256 == context.fingerprintSHA256,
                   trusted.openSSHPublicKey == context.openSSHPublicKey {
                    return .trust
                }
            } catch {
                return .reject
            }

            return .reject
        }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (_ validator: @escaping SSHHostKeyValidator) async throws -> T
    ) async throws -> T {
        let recorder = PendingHostTrustRecorder()
        let validator: SSHHostKeyValidator = { [knownHostsStore] context in
            do {
                if let trusted = try await knownHostsStore.trustedContext(
                    host: context.host,
                    port: context.port
                ),
                   trusted.fingerprintSHA256 == context.fingerprintSHA256,
                   trusted.openSSHPublicKey == context.openSSHPublicKey {
                    return .trust
                }
            } catch {
                // Treat trust-store read failures as an untrusted host and fall back
                // to the reducer-owned approval flow.
            }
            await recorder.record(context)
            return .reject
        }

        do {
            return try await operation(validator)
        } catch let error as SSHTerminalError {
            switch error {
            case .hostKeyRejected:
                if let context = await recorder.context {
                    throw RemoteWorkspaceClientError.hostTrustRequired(context)
                }
                throw RemoteWorkspaceClientError.message(error.localizedDescription)
            default:
                throw RemoteWorkspaceClientError.message(error.localizedDescription)
            }
        } catch let error as SSHRemoteWorkspaceError {
            throw RemoteWorkspaceClientError.message(error.localizedDescription)
        } catch let error as RemoteWorkspaceClientError {
            throw error
        } catch {
            throw RemoteWorkspaceClientError.message(error.localizedDescription)
        }
    }
}

private actor PendingHostTrustRecorder {
    private(set) var context: SSHHostKeyValidationContext?

    func record(_ context: SSHHostKeyValidationContext) {
        self.context = context
    }
}
