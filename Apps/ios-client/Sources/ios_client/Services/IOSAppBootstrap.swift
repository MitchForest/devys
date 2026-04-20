import ComposableArchitecture
import RemoteFeatures
import SwiftUI

@MainActor
enum IOSAppBootstrap {
    static func makeStore() -> StoreOf<RemoteTerminalFeature> {
        let repositoryStore = IOSRemoteRepositoryPersistenceStore()
        let knownHostsStore = IOSKnownHostsStore()
        let workspaceBridge = IOSRemoteWorkspaceBridge(knownHostsStore: knownHostsStore)

        return withDependencies {
            $0.remoteRepositoryStoreClient = .live(store: repositoryStore)
            $0.remoteWorkspaceClient = .live(
                bridge: workspaceBridge,
                knownHostsStore: knownHostsStore
            )
        } operation: {
            Store(initialState: RemoteTerminalFeature.State()) {
                RemoteTerminalFeature()
            }
        }
    }
}

private extension RemoteRepositoryStoreClient {
    static func live(
        store: IOSRemoteRepositoryPersistenceStore
    ) -> Self {
        Self(
            load: { try await store.load() },
            save: { try await store.save($0) }
        )
    }
}

private extension RemoteWorkspaceClient {
    static func live(
        bridge: IOSRemoteWorkspaceBridge,
        knownHostsStore: IOSKnownHostsStore
    ) -> Self {
        Self(
            refreshWorktrees: { repository in
                try await bridge.refreshWorktrees(repository)
            },
            createWorktree: { repository, draft in
                try await bridge.createWorktree(repository, draft: draft)
            },
            fetch: { repository in
                try await bridge.fetch(repository)
            },
            pull: { repository, worktree in
                try await bridge.pull(repository, worktree: worktree)
            },
            push: { repository, worktree in
                try await bridge.push(repository, worktree: worktree)
            },
            discoverShellSessions: { repository, worktrees in
                try await bridge.discoverShellSessions(repository, worktrees: worktrees)
            },
            prepareShellSession: { repository, worktree in
                try await bridge.prepareShellSession(repository, worktree: worktree)
            },
            validateShellConnection: { repository in
                try await bridge.validateShellConnection(repository)
            },
            trustedHostValidator: {
                IOSRemoteWorkspaceBridge.makeTrustedHostValidator(
                    knownHostsStore: knownHostsStore
                )
            },
            trustHost: { context in
                try await bridge.trustHost(context)
            },
            trustedHostsCount: {
                try await bridge.trustedHostsCount()
            },
            clearTrustedHosts: {
                try await bridge.clearTrustedHosts()
            }
        )
    }
}
