import AppFeatures
import ComposableArchitecture
import Foundation
import RemoteCore
import Testing
import Workspace

@Suite("WindowFeature Selection Tests")
struct WindowFeatureSelectionTests {
    @Test("Selecting a repository clears workspace selection")
    @MainActor
    func selectRepositoryClearsWorkspaceSelection() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository, secondRepository],
                selectedRepositoryID: firstRepository.id,
                selectedWorkspaceID: "/tmp/devys-project/workspaces/main"
            )
        ) {
            WindowFeature()
        }

        await store.send(.selectRepository(secondRepository.id)) {
            $0.selectedRepositoryID = secondRepository.id
            $0.selectedWorkspaceID = nil
        }
    }

    @Test("Selecting a remote repository clears local selection and restores the remote worktree")
    @MainActor
    func selectRemoteRepositoryClearsLocalSelection() async {
        let localRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let remoteRepository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            displayName: "devys",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let remoteWorktree = RemoteWorktree(
            repositoryID: remoteRepository.id,
            branchName: "feature/remote-agent",
            remotePath: "/Users/mitch/Code/devys-feature-remote-agent",
            isPrimary: false
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [localRepository],
                remoteRepositories: [remoteRepository],
                remoteWorktreesByRepository: [remoteRepository.id: [remoteWorktree]],
                selectedRepositoryID: localRepository.id,
                selectedWorkspaceID: "/tmp/devys-project/workspaces/main"
            )
        ) {
            WindowFeature()
        }

        await store.send(WindowFeature.Action.selectRemoteRepository(remoteRepository.id)) {
            $0.selectedRepositoryID = nil
            $0.selectedRemoteRepositoryID = remoteRepository.id
            $0.selectedRemoteWorktreeID = remoteWorktree.id
            $0.selectedWorkspaceID = remoteWorktree.id
        }
    }

    @Test("Selecting a local repository clears remote authority selection")
    @MainActor
    func selectLocalRepositoryClearsRemoteSelection() async {
        let localRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let remoteRepository = RemoteRepositoryAuthority(
            sshTarget: "mac-mini",
            displayName: "devys",
            repositoryPath: "/Users/mitch/Code/devys"
        )
        let remoteWorktree = RemoteWorktree(
            repositoryID: remoteRepository.id,
            branchName: "feature/remote-agent",
            remotePath: "/Users/mitch/Code/devys-feature-remote-agent",
            isPrimary: false
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [localRepository],
                remoteRepositories: [remoteRepository],
                remoteWorktreesByRepository: [remoteRepository.id: [remoteWorktree]],
                selectedRemoteRepositoryID: remoteRepository.id,
                selectedRemoteWorktreeID: remoteWorktree.id,
                selectedWorkspaceID: remoteWorktree.id
            )
        ) {
            WindowFeature()
        }

        await store.send(WindowFeature.Action.selectRepository(localRepository.id)) {
            $0.selectedRepositoryID = localRepository.id
            $0.selectedRemoteRepositoryID = nil
            $0.selectedRemoteWorktreeID = nil
            $0.selectedWorkspaceID = nil
            $0.workspaceShells = [
                remoteWorktree.id: WindowFeature.WorkspaceShell(activeSidebar: .files)
            ]
        }
    }

    @Test("Catalog snapshots fall back to the first visible workspace when selection disappears")
    @MainActor
    func setRepositoryCatalogSnapshotFallsBackToFirstWorkspace() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspace = Worktree(
            name: "main",
            detail: ".",
            workingDirectory: repository.rootURL,
            repositoryRootURL: repository.rootURL
        )
        let secondWorkspace = Worktree(
            name: "feature",
            detail: "feature",
            workingDirectory: repository.rootURL.appendingPathComponent("feature"),
            repositoryRootURL: repository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: "/tmp/devys-project/workspaces/missing"
            )
        ) {
            WindowFeature()
        }

        await store.send(
            .setRepositoryCatalogSnapshot(
                WindowFeature.RepositoryCatalogSnapshot(
                    repositories: [repository],
                    worktreesByRepository: [repository.id: [firstWorkspace, secondWorkspace]]
                )
            )
        ) {
            $0.worktreesByRepository = [repository.id: [secondWorkspace, firstWorkspace]]
            $0.selectedWorkspaceID = secondWorkspace.id
        }
        await store.receive(.reviewWorkspaceLoadRequested(secondWorkspace.id)) {
            $0.reviewWorkspacesByID[secondWorkspace.id] = WindowFeature.ReviewWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(.workflowWorkspaceLoadRequested(secondWorkspace.id)) {
            $0.workflowWorkspacesByID[secondWorkspace.id] = WindowFeature.WorkflowWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(
            .reviewWorkspaceLoaded(secondWorkspace.id, ReviewWorkspaceSnapshot())
        ) {
            $0.reviewWorkspacesByID[secondWorkspace.id] = WindowFeature.ReviewWorkspaceState()
        }
        await store.receive(
            .workflowWorkspaceLoaded(secondWorkspace.id, WorkflowWorkspaceSnapshot())
        ) {
            $0.workflowWorkspacesByID[secondWorkspace.id] = WindowFeature.WorkflowWorkspaceState()
        }
    }

    @Test("Catalog snapshots normalize workspace ordering with reducer rules")
    @MainActor
    func setRepositoryCatalogSnapshotNormalizesOrdering() async {
        let fixture = SnapshotOrderingFixture()
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        }

        await store.send(
            .setRepositoryCatalogSnapshot(
                fixture.snapshot
            )
        ) {
            $0.repositories = [fixture.repository]
            $0.workspaceStatesByID = fixture.workspaceStatesByID
            $0.worktreesByRepository = [
                fixture.repository.id: [
                    fixture.pinnedWorkspace,
                    fixture.renamedWorkspace,
                    fixture.archivedWorkspace
                ]
            ]
            $0.selectedRepositoryID = fixture.repository.id
            $0.selectedWorkspaceID = fixture.pinnedWorkspace.id
        }
        await store.receive(.reviewWorkspaceLoadRequested(fixture.pinnedWorkspace.id)) {
            $0.reviewWorkspacesByID[fixture.pinnedWorkspace.id] = WindowFeature.ReviewWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(.workflowWorkspaceLoadRequested(fixture.pinnedWorkspace.id)) {
            $0.workflowWorkspacesByID[fixture.pinnedWorkspace.id] = WindowFeature.WorkflowWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(
            .reviewWorkspaceLoaded(fixture.pinnedWorkspace.id, ReviewWorkspaceSnapshot())
        ) {
            $0.reviewWorkspacesByID[fixture.pinnedWorkspace.id] = WindowFeature.ReviewWorkspaceState()
        }
        await store.receive(
            .workflowWorkspaceLoaded(fixture.pinnedWorkspace.id, WorkflowWorkspaceSnapshot())
        ) {
            $0.workflowWorkspacesByID[fixture.pinnedWorkspace.id] = WindowFeature.WorkflowWorkspaceState()
        }
    }
}

private struct SnapshotOrderingFixture {
    let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-ordering"))

    var archivedWorkspace: Worktree {
        Worktree(
            name: "zeta",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("zeta"),
            repositoryRootURL: repository.rootURL
        )
    }

    var pinnedWorkspace: Worktree {
        Worktree(
            name: "beta",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("beta"),
            repositoryRootURL: repository.rootURL
        )
    }

    var renamedWorkspace: Worktree {
        Worktree(
            name: "gamma",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("gamma"),
            repositoryRootURL: repository.rootURL
        )
    }

    var workspaceStatesByID: [Worktree.ID: WorktreeState] {
        [
            archivedWorkspace.id: WorktreeState(
                worktreeId: archivedWorkspace.id,
                isArchived: true
            ),
            pinnedWorkspace.id: WorktreeState(
                worktreeId: pinnedWorkspace.id,
                isPinned: true
            ),
            renamedWorkspace.id: WorktreeState(
                worktreeId: renamedWorkspace.id,
                displayNameOverride: "aardvark"
            )
        ]
    }

    var snapshot: WindowFeature.RepositoryCatalogSnapshot {
        WindowFeature.RepositoryCatalogSnapshot(
            repositories: [repository],
            worktreesByRepository: [
                repository.id: [archivedWorkspace, renamedWorkspace, pinnedWorkspace]
            ],
            workspaceStatesByID: workspaceStatesByID
        )
    }
}
