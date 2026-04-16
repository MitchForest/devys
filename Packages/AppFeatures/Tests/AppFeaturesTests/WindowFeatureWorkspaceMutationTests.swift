import AppFeatures
import ComposableArchitecture
import Foundation
import Testing
import Workspace

@Suite("WindowFeature Workspace Mutation Tests")
struct WindowFeatureWorkspaceMutationTests {
    @Test("Pinning a workspace reorders the repository inventory")
    @MainActor
    func setWorkspacePinned() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspace = Worktree(
            name: "alpha",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("alpha"),
            repositoryRootURL: repository.rootURL
        )
        let secondWorkspace = Worktree(
            name: "beta",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("beta"),
            repositoryRootURL: repository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [firstWorkspace, secondWorkspace]]
            )
        ) {
            WindowFeature()
        }

        await store.send(.setWorkspacePinned(secondWorkspace.id, repositoryID: repository.id, isPinned: true)) {
            $0.workspaceStatesByID[secondWorkspace.id] = WorktreeState(
                worktreeId: secondWorkspace.id,
                isPinned: true
            )
            $0.worktreesByRepository[repository.id] = [secondWorkspace, firstWorkspace]
        }
    }

    @Test("Archiving the selected workspace falls back to the next visible workspace")
    @MainActor
    func setWorkspaceArchived() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspace = Worktree(
            name: "alpha",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("alpha"),
            repositoryRootURL: repository.rootURL
        )
        let secondWorkspace = Worktree(
            name: "beta",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("beta"),
            repositoryRootURL: repository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [firstWorkspace, secondWorkspace]],
                selectedRepositoryID: repository.id,
                selectedWorkspaceID: firstWorkspace.id,
                workspaceShells: [
                    secondWorkspace.id: WindowFeature.WorkspaceShell(activeSidebar: .agents)
                ]
            )
        ) {
            WindowFeature()
        }

        await store.send(.setWorkspaceArchived(firstWorkspace.id, repositoryID: repository.id, isArchived: true)) {
            $0.workspaceStatesByID[firstWorkspace.id] = WorktreeState(
                worktreeId: firstWorkspace.id,
                isArchived: true
            )
            $0.worktreesByRepository[repository.id] = [secondWorkspace, firstWorkspace]
            $0.selectedWorkspaceID = secondWorkspace.id
            $0.activeSidebar = .agents
        }
    }

    @Test("Setting a workspace display name updates ordering and stored metadata")
    @MainActor
    func setWorkspaceDisplayName() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspace = Worktree(
            name: "zeta",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("zeta"),
            repositoryRootURL: repository.rootURL
        )
        let secondWorkspace = Worktree(
            name: "alpha",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("alpha"),
            repositoryRootURL: repository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [firstWorkspace, secondWorkspace]]
            )
        ) {
            WindowFeature()
        }

        await store.send(
            .setWorkspaceDisplayName(
                firstWorkspace.id,
                repositoryID: repository.id,
                displayName: "aardvark"
            )
        ) {
            $0.workspaceStatesByID[firstWorkspace.id] = WorktreeState(
                worktreeId: firstWorkspace.id,
                displayNameOverride: "aardvark"
            )
            $0.worktreesByRepository[repository.id] = [firstWorkspace, secondWorkspace]
        }
    }

    @Test("Removing workspace state clears metadata and restores default ordering")
    @MainActor
    func removeWorkspaceState() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let firstWorkspace = Worktree(
            name: "alpha",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("alpha"),
            repositoryRootURL: repository.rootURL
        )
        let secondWorkspace = Worktree(
            name: "beta",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("beta"),
            repositoryRootURL: repository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [secondWorkspace, firstWorkspace]],
                workspaceStatesByID: [
                    secondWorkspace.id: WorktreeState(worktreeId: secondWorkspace.id, isPinned: true)
                ],
                operational: {
                    var operational = WorkspaceOperationalState()
                    operational.metadataEntriesByWorkspaceID[secondWorkspace.id] = WorktreeInfoEntry(
                        branchName: "feature/remove"
                    )
                    return operational
                }()
            )
        ) {
            WindowFeature()
        }

        await store.send(.removeWorkspaceState(secondWorkspace.id, repositoryID: repository.id)) {
            $0.workspaceStatesByID = [:]
            $0.worktreesByRepository[repository.id] = [firstWorkspace, secondWorkspace]
            $0.operational.metadataEntriesByWorkspaceID = [:]
        }
    }
}
