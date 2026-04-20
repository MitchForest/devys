import AppFeatures
import ComposableArchitecture
import Foundation
import RemoteCore
import Split
import Testing

@Suite("WindowFeature Remote Operation Tests")
struct WindowFeatureRemoteOperationTests {
    @Test("Refreshing a remote repository updates worktrees in reducer state")
    @MainActor
    func refreshRemoteRepositoryUpdatesWorktrees() async {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            displayName: "devys",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let refreshedWorktree = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "feature/remote",
            remotePath: "/Users/mitch/Code/devys-feature-remote",
            isPrimary: false
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                remoteRepositories: [repository],
                selectedRemoteRepositoryID: repository.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.remoteTerminalWorkspaceClient.refreshWorktrees = { refreshedRepository in
                #expect(refreshedRepository.id == repository.id)
                return [refreshedWorktree]
            }
        }

        await store.send(.refreshRemoteRepository(repository.id))
        await store.receive(
            .refreshRemoteRepositoryResponse(
                repositoryID: repository.id,
                result: .success([refreshedWorktree])
            )
        ) {
            $0.remoteWorktreesByRepository[repository.id] = [refreshedWorktree]
            $0.selectedRemoteWorktreeID = refreshedWorktree.id
            $0.selectedWorkspaceID = refreshedWorktree.id
        }
    }

    @Test("Requesting a remote shell emits a host launch request")
    @MainActor
    func requestOpenRemoteTerminalCreatesLaunchRequest() async {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            displayName: "devys",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let worktree = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "feature/remote",
            remotePath: "/Users/mitch/Code/devys-feature-remote",
            isPrimary: false
        )
        let requestID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let preferredPaneID = PaneID(uuid: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)

        let store = TestStore(
            initialState: WindowFeature.State(
                remoteRepositories: [repository],
                remoteWorktreesByRepository: [repository.id: [worktree]],
                selectedRemoteRepositoryID: repository.id,
                selectedRemoteWorktreeID: worktree.id,
                selectedWorkspaceID: worktree.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.remoteTerminalWorkspaceClient.prepareShellLaunch = { preparedRepository, preparedWorktree in
                #expect(preparedRepository.id == repository.id)
                #expect(preparedWorktree.id == worktree.id)
                return "/usr/bin/ssh -tt mac-mini"
            }
            $0.uuid = .constant(requestID)
        }

        await store.send(.requestOpenRemoteTerminal(preferredPaneID: preferredPaneID))
        await store.receive(.remoteTerminalLaunchPrepared(.success(.init(
            workspaceID: worktree.id,
            attachCommand: "/usr/bin/ssh -tt mac-mini",
            preferredPaneID: preferredPaneID,
            id: requestID
        )))) {
            $0.remoteTerminalLaunchRequest = WindowFeature.RemoteTerminalLaunchRequest(
                workspaceID: worktree.id,
                attachCommand: "/usr/bin/ssh -tt mac-mini",
                preferredPaneID: preferredPaneID,
                id: requestID
            )
        }
    }

    @Test("Creating a remote worktree emits a reducer-owned remote workspace transition request")
    @MainActor
    func createRemoteWorktreeCreatesTransitionRequest() async {
        let repository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            displayName: "devys",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let existingWorktree = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "main",
            remotePath: "/Users/mitch/Code/devys",
            isPrimary: true
        )
        let createdWorktree = RemoteWorktree(
            repositoryID: repository.id,
            branchName: "feature/remote",
            remotePath: "/Users/mitch/Code/devys-feature-remote",
            isPrimary: false
        )
        let requestID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let draft = RemoteWorktreeDraft(
            repositoryID: repository.id,
            branchName: "feature/remote",
            startPoint: "origin/main",
            directoryName: "devys-feature-remote"
        )

        let store = TestStore(
            initialState: WindowFeature.State(
                remoteRepositories: [repository],
                remoteWorktreesByRepository: [repository.id: [existingWorktree]],
                selectedRemoteRepositoryID: repository.id,
                selectedRemoteWorktreeID: existingWorktree.id,
                selectedWorkspaceID: existingWorktree.id,
                remoteWorktreeCreationPresentation: RemoteWorktreeCreationPresentation(draft: draft)
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.remoteTerminalWorkspaceClient.createWorktree = { createdRepository, createdDraft in
                #expect(createdRepository.id == repository.id)
                #expect(createdDraft == draft)
                return createdWorktree
            }
            $0.remoteTerminalWorkspaceClient.refreshWorktrees = { refreshedRepository in
                #expect(refreshedRepository.id == repository.id)
                return [existingWorktree, createdWorktree]
            }
            $0.uuid = .constant(requestID)
        }

        await store.send(.createRemoteWorktree(draft))
        await store.receive(
            .createRemoteWorktreeResponse(
                .success(
                    WindowFeature.RemoteWorktreeCreationResult(
                        createdWorktree: createdWorktree,
                        worktrees: [existingWorktree, createdWorktree]
                    )
                )
            )
        ) {
            $0.remoteWorktreesByRepository[repository.id] = [existingWorktree, createdWorktree]
            $0.remoteWorktreeCreationPresentation = nil
            $0.remoteWorkspaceTransitionRequest = WindowFeature.RemoteWorkspaceTransitionRequest(
                sourceWorkspaceID: existingWorktree.id,
                targetRepositoryID: repository.id,
                targetWorkspaceID: createdWorktree.id,
                shouldPersistVisibleWorkspaceState: true,
                shouldResetHostWorkspaceState: true,
                id: requestID
            )
        }
    }
}
