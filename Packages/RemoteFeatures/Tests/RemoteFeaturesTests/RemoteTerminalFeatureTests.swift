import ComposableArchitecture
import RemoteCore
import RemoteFeatures
import SSH
import XCTest

@MainActor
final class RemoteTerminalFeatureTests: XCTestCase {
    func testBootstrapSelectsFirstRepositoryAndDiscoversSessions() async {
        let record = makeRepositoryRecord()
        let worktree = makeWorktree(repositoryID: record.id)
        let session = makeShellSession(repositoryID: record.id, worktreeID: worktree.id)

        let store = TestStore(initialState: RemoteTerminalFeature.State()) {
            RemoteTerminalFeature()
        } withDependencies: {
            $0.remoteRepositoryStoreClient.load = { [record] }
            $0.remoteWorkspaceClient.trustedHostsCount = { 0 }
            $0.remoteWorkspaceClient.refreshWorktrees = { _ in [worktree] }
            $0.remoteWorkspaceClient.discoverShellSessions = { repository, worktrees in
                XCTAssertEqual(repository.id, record.id)
                XCTAssertEqual(worktrees, [worktree])
                return [session]
            }
        }

        await store.send(.task) {
            $0.isBootstrapping = true
        }
        await store.receive(
            .bootstrapLoaded(
                repositories: [record],
                trustedHostsCount: 0
            )
        ) {
            $0.isBootstrapping = false
            $0.repositories = [record]
            $0.selectedRepositoryID = record.id
        }
        await store.receive(.refreshRepository(record.id))
        await store.receive(.setRemoteWorktrees(record.id, [worktree])) {
            $0.worktreesByRepository[record.id] = [worktree]
        }
        await store.receive(.discoverShellSessions(record.id))
        await store.receive(.setShellSessions(record.id, [session])) {
            $0.shellSessionsByRepository[record.id] = [session]
        }
    }

    func testOpenSessionPreparesShellAndSetsActiveSession() async {
        let record = makeRepositoryRecord()
        let worktree = makeWorktree(repositoryID: record.id)
        let connectRequestID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let prepared = SSHRemotePreparedShellSession(
            session: makeShellSession(repositoryID: record.id, worktreeID: worktree.id),
            remoteAttachCommand: "sh -lc 'exec tmux attach'"
        )
        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.worktreesByRepository = [record.id: [worktree]]
        initialState.selectedRepositoryID = record.id

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        } withDependencies: {
            $0.remoteWorkspaceClient.prepareShellSession = { repository, resolvedWorktree in
                XCTAssertEqual(repository.id, record.id)
                XCTAssertEqual(resolvedWorktree.id, worktree.id)
                return prepared
            }
            $0.remoteWorkspaceClient.discoverShellSessions = { _, _ in [prepared.session] }
            $0.uuid = .constant(connectRequestID)
        }

        await store.send(.openSession(repositoryID: record.id, worktreeID: worktree.id))
        await store.receive(.shellSessionPrepared(prepared)) {
            $0.activeSession = ActiveRemoteSession(
                session: prepared.session,
                remoteAttachCommand: prepared.remoteAttachCommand,
                connectRequestID: connectRequestID
            )
        }
        await store.receive(.discoverShellSessions(record.id))
        await store.receive(.setShellSessions(record.id, [prepared.session])) {
            $0.shellSessionsByRepository[record.id] = [prepared.session]
        }
    }

    func testReconnectActiveSessionValidatesConnectionAndUpdatesConnectRequest() async {
        let record = makeRepositoryRecord()
        let oldRequestID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let newRequestID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let session = makeShellSession(
            repositoryID: record.id,
            worktreeID: makeWorktree(repositoryID: record.id).id
        )
        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.activeSession = ActiveRemoteSession(
            session: session,
            remoteAttachCommand: "sh -lc 'exec tmux attach'",
            connectRequestID: oldRequestID,
            errorMessage: "previous failure"
        )

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        } withDependencies: {
            $0.remoteWorkspaceClient.validateShellConnection = { repository in
                XCTAssertEqual(repository.id, record.id)
            }
            $0.uuid = .constant(newRequestID)
        }

        await store.send(.reconnectActiveSession)
        await store.receive(.activeSessionReconnectReady(newRequestID)) {
            $0.activeSession?.connectRequestID = newRequestID
            $0.activeSession?.errorMessage = nil
        }
    }

    func testResolveHostTrustRetriesReconnectActiveSession() async {
        let record = makeRepositoryRecord()
        let trustedContext = SSHHostKeyValidationContext(
            host: "100.64.0.10",
            port: 22,
            algorithm: "ssh-ed25519",
            openSSHPublicKey: "ssh-ed25519 AAAA",
            fingerprintSHA256: "abc123"
        )
        let nextRequestID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let session = makeShellSession(
            repositoryID: record.id,
            worktreeID: makeWorktree(repositoryID: record.id).id
        )
        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.activeSession = ActiveRemoteSession(
            session: session,
            remoteAttachCommand: "sh -lc 'exec tmux attach'",
            connectRequestID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        )
        initialState.hostTrustPrompt = RemoteHostTrustPrompt(context: trustedContext)
        initialState.pendingOperation = .reconnectActiveSession

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        } withDependencies: {
            $0.remoteWorkspaceClient.trustHost = { context in
                XCTAssertEqual(context, trustedContext)
            }
            $0.remoteWorkspaceClient.trustedHostsCount = { 1 }
            $0.remoteWorkspaceClient.validateShellConnection = { repository in
                XCTAssertEqual(repository.id, record.id)
            }
            $0.uuid = .constant(nextRequestID)
        }

        await store.send(.resolveHostTrust(true)) {
            $0.hostTrustPrompt = nil
            $0.pendingOperation = nil
        }
        await store.receive(.trustedHostsCountLoaded(1)) {
            $0.trustedHostsCount = 1
        }
        await store.receive(.reconnectActiveSession)
        await store.receive(.activeSessionReconnectReady(nextRequestID)) {
            $0.activeSession?.connectRequestID = nextRequestID
            $0.activeSession?.errorMessage = nil
        }
    }

    func testResolveHostTrustRetriesPendingFetch() async {
        let record = makeRepositoryRecord()
        let trustedContext = SSHHostKeyValidationContext(
            host: "100.64.0.10",
            port: 22,
            algorithm: "ssh-ed25519",
            openSSHPublicKey: "ssh-ed25519 AAAA",
            fingerprintSHA256: "abc123"
        )

        let refreshedWorktrees = [
            makeWorktree(repositoryID: record.id, branchName: "feature/resumed")
        ]
        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.selectedRepositoryID = record.id
        initialState.hostTrustPrompt = RemoteHostTrustPrompt(context: trustedContext)
        initialState.pendingOperation = .fetchRepository(record.id)

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        } withDependencies: {
            $0.remoteWorkspaceClient.trustHost = { context in
                XCTAssertEqual(context, trustedContext)
            }
            $0.remoteWorkspaceClient.trustedHostsCount = { 1 }
            $0.remoteWorkspaceClient.fetch = { repository in
                XCTAssertEqual(repository.id, record.id)
            }
            $0.remoteWorkspaceClient.refreshWorktrees = { repository in
                XCTAssertEqual(repository.id, record.id)
                return refreshedWorktrees
            }
            $0.remoteWorkspaceClient.discoverShellSessions = { _, _ in [] }
        }

        await store.send(RemoteTerminalFeature.Action.resolveHostTrust(true)) {
            $0.hostTrustPrompt = nil
            $0.pendingOperation = nil
        }
        await store.receive(RemoteTerminalFeature.Action.trustedHostsCountLoaded(1)) {
            $0.trustedHostsCount = 1
        }
        await store.receive(RemoteTerminalFeature.Action.fetchRepository(record.id))
        await store.receive(RemoteTerminalFeature.Action.setRemoteWorktrees(record.id, refreshedWorktrees)) {
            $0.worktreesByRepository[record.id] = refreshedWorktrees
        }
        await store.receive(RemoteTerminalFeature.Action.discoverShellSessions(record.id))
        await store.receive(RemoteTerminalFeature.Action.setShellSessions(record.id, [])) {
            $0.shellSessionsByRepository[record.id] = []
        }
    }

    // MARK: - Navigation

    func testSelectRepositoryClearsWorktreeSelectionWhenRepositoryChanges() async {
        let record = makeRepositoryRecord()
        let other = RemoteRepositoryRecord(
            authority: RemoteRepositoryAuthority(
                sshTarget: "mitch@other",
                displayName: "other",
                repositoryPath: "/Users/mitch/Code/other"
            ),
            connection: SSHConnectionConfiguration(
                host: "100.64.0.11",
                port: 22,
                username: "mitch",
                authentication: .password("secret")
            )
        )
        let worktree = makeWorktree(repositoryID: record.id)

        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record, other]
        initialState.worktreesByRepository = [record.id: [worktree]]
        initialState.selectedRepositoryID = record.id
        initialState.selectedWorktreeID = worktree.id

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        }

        await store.send(.selectRepository(other.id)) {
            $0.selectedRepositoryID = other.id
            $0.selectedWorktreeID = nil
        }
    }

    func testSelectRepositoryKeepsWorktreeSelectionWhenRepositoryUnchanged() async {
        let record = makeRepositoryRecord()
        let worktree = makeWorktree(repositoryID: record.id)

        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.worktreesByRepository = [record.id: [worktree]]
        initialState.selectedRepositoryID = record.id
        initialState.selectedWorktreeID = worktree.id

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        }

        await store.send(.selectRepository(record.id))
    }

    func testSelectWorktreeSetsSelectedWorktreeID() async {
        let record = makeRepositoryRecord()
        let worktree = makeWorktree(repositoryID: record.id)

        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.worktreesByRepository = [record.id: [worktree]]
        initialState.selectedRepositoryID = record.id

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        }

        await store.send(.selectWorktree(worktree.id)) {
            $0.selectedWorktreeID = worktree.id
        }
        await store.send(.selectWorktree(nil)) {
            $0.selectedWorktreeID = nil
        }
    }

    func testPresentAndDismissSettingsTogglesIsSettingsPresented() async {
        let store = TestStore(initialState: RemoteTerminalFeature.State()) {
            RemoteTerminalFeature()
        }

        await store.send(.presentSettings) {
            $0.isSettingsPresented = true
        }
        await store.send(.dismissSettings) {
            $0.isSettingsPresented = false
        }
    }

    func testPresentWorktreeCreationUsesPresentedRepositoryInsteadOfSelectedRepository() async {
        let primary = makeRepositoryRecord()
        let secondary = RemoteRepositoryRecord(
            authority: RemoteRepositoryAuthority(
                sshTarget: "mitch@other",
                displayName: "other",
                repositoryPath: "/Users/mitch/Code/other"
            ),
            connection: SSHConnectionConfiguration(
                host: "100.64.0.11",
                port: 22,
                username: "mitch",
                authentication: .password("secret")
            )
        )

        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [primary, secondary]
        initialState.selectedRepositoryID = secondary.id

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        }

        await store.send(.presentWorktreeCreation(primary.id)) {
            $0.worktreeCreationRepositoryID = primary.id
        }
        XCTAssertEqual(store.state.selectedRepositoryID, secondary.id)
        XCTAssertEqual(store.state.worktreeCreationRepository?.id, primary.id)

        await store.send(.dismissWorktreeCreation) {
            $0.worktreeCreationRepositoryID = nil
        }
        XCTAssertNil(store.state.worktreeCreationRepository)
    }

    func testSetRemoteWorktreesClearsSelectedWorktreeIDWhenMissing() async {
        let record = makeRepositoryRecord()
        let worktree = makeWorktree(repositoryID: record.id)
        let replacement = makeWorktree(
            repositoryID: record.id,
            branchName: "feature/other",
            path: "/Users/mitch/Code/devys-feature-other"
        )

        var initialState = RemoteTerminalFeature.State()
        initialState.repositories = [record]
        initialState.worktreesByRepository = [record.id: [worktree]]
        initialState.selectedRepositoryID = record.id
        initialState.selectedWorktreeID = worktree.id

        let store = TestStore(initialState: initialState) {
            RemoteTerminalFeature()
        } withDependencies: {
            $0.remoteWorkspaceClient.discoverShellSessions = { _, _ in [] }
        }

        await store.send(.setRemoteWorktrees(record.id, [replacement])) {
            $0.worktreesByRepository[record.id] = [replacement]
            $0.selectedWorktreeID = nil
        }
        await store.receive(RemoteTerminalFeature.Action.discoverShellSessions(record.id))
        await store.receive(RemoteTerminalFeature.Action.setShellSessions(record.id, [])) {
            $0.shellSessionsByRepository[record.id] = []
        }
    }

    private func makeRepositoryRecord() -> RemoteRepositoryRecord {
        RemoteRepositoryRecord(
            authority: RemoteRepositoryAuthority(
                sshTarget: "mitch@mac-mini",
                displayName: "devys",
                repositoryPath: "/Users/mitch/Code/devys"
            ),
            connection: SSHConnectionConfiguration(
                host: "100.64.0.10",
                port: 22,
                username: "mitch",
                authentication: .password("secret")
            )
        )
    }

    private func makeWorktree(
        repositoryID: RemoteRepositoryAuthority.ID,
        branchName: String = "feature/ios-remote",
        path: String = "/Users/mitch/Code/devys-feature-ios-remote"
    ) -> RemoteWorktree {
        RemoteWorktree(
            repositoryID: repositoryID,
            branchName: branchName,
            remotePath: path,
            detail: "devys-feature-ios-remote",
            isPrimary: false,
            headSHA: "1234567890abcdef",
            status: RemoteWorktreeStatus(isDirty: false)
        )
    }

    private func makeShellSession(
        repositoryID: RemoteRepositoryAuthority.ID,
        worktreeID: RemoteWorktree.ID
    ) -> SSHRemoteShellSession {
        SSHRemoteShellSession(
            repositoryID: repositoryID,
            worktreeID: worktreeID,
            branchName: "feature/ios-remote",
            remotePath: "/Users/mitch/Code/devys-feature-ios-remote",
            sessionName: "devys-shell-12345",
            attachedClientCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_234)
        )
    }
}
