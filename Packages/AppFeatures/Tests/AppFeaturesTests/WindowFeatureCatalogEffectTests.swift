import AppFeatures
import ComposableArchitecture
import Foundation
import Testing
import Workspace

@Suite("WindowFeature Catalog Effect Tests")
struct WindowFeatureCatalogEffectTests {
    @Test("Refreshing repositories requests a reducer-owned catalog snapshot")
    @MainActor
    func refreshRepositories() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-refresh"))
        let refreshedWorktree = Worktree(
            name: "feature/catalog",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-catalog"),
            repositoryRootURL: repository.rootURL
        )
        let refreshedSnapshot = WindowFeature.RepositoryCatalogSnapshot(
            repositories: [repository],
            worktreesByRepository: [repository.id: [refreshedWorktree]]
        )
        let store = TestStore(
            initialState: WindowFeature.State(repositories: [repository])
        ) {
            WindowFeature()
        } withDependencies: {
            $0.workspaceCatalogRefreshClient.refreshRepositories = { snapshot, repositoryIDs in
                #expect(snapshot.repositories == [repository])
                #expect(repositoryIDs == [repository.id])
                return refreshedSnapshot
            }
        }

        await store.send(.refreshRepositories([repository.id]))
        await store.receive(.setRepositoryCatalogSnapshot(refreshedSnapshot)) {
            $0.repositories = [repository]
            $0.worktreesByRepository = [repository.id: [refreshedWorktree]]
            $0.selectedRepositoryID = repository.id
            $0.selectedWorkspaceID = refreshedWorktree.id
        }
        await store.receive(.workflowWorkspaceLoadRequested(refreshedWorktree.id)) {
            $0.workflowWorkspacesByID[refreshedWorktree.id] = WindowFeature.WorkflowWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(
            .workflowWorkspaceLoaded(refreshedWorktree.id, WorkflowWorkspaceSnapshot())
        ) {
            $0.workflowWorkspacesByID[refreshedWorktree.id] = WindowFeature.WorkflowWorkspaceState()
        }
    }

    @Test("Selecting a workspace updates last-focused ordering and persists workspace states")
    @MainActor
    func selectWorkspacePersistsLastFocusedState() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-selection"))
        let firstWorktree = Worktree(
            name: "main",
            detail: ".",
            workingDirectory: repository.rootURL,
            repositoryRootURL: repository.rootURL
        )
        let secondWorktree = Worktree(
            name: "feature/catalog",
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent("feature-catalog"),
            repositoryRootURL: repository.rootURL
        )
        let fixedDate = Date(timeIntervalSince1970: 1_234_567)
        let recorder = CatalogPersistenceRecorder()
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository],
                worktreesByRepository: [repository.id: [firstWorktree, secondWorktree]],
                selectedRepositoryID: repository.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.date.now = fixedDate
            $0.workspaceCatalogPersistenceClient.saveWorkspaceStates = { states in
                recorder.savedWorkspaceStates.append(states)
            }
        }

        await store.send(.selectWorkspace(secondWorktree.id)) {
            $0.selectedWorkspaceID = secondWorktree.id
            $0.worktreesByRepository = [repository.id: [secondWorktree, firstWorktree]]
            $0.workspaceStatesByID = [
                secondWorktree.id: WorktreeState(
                    worktreeId: secondWorktree.id,
                    lastFocused: fixedDate
                )
            ]
            $0.workspaceShells = [
                repository.id: WindowFeature.WorkspaceShell(activeSidebar: .files)
            ]
        }
        await store.receive(.workflowWorkspaceLoadRequested(secondWorktree.id)) {
            $0.workflowWorkspacesByID[secondWorktree.id] = WindowFeature.WorkflowWorkspaceState(
                isLoading: true
            )
        }
        await store.receive(
            .workflowWorkspaceLoaded(secondWorktree.id, WorkflowWorkspaceSnapshot())
        ) {
            $0.workflowWorkspacesByID[secondWorktree.id] = WindowFeature.WorkflowWorkspaceState()
        }

        #expect(recorder.savedWorkspaceStates.count == 1)
        #expect(recorder.savedWorkspaceStates[0] == [
            WorktreeState(
                worktreeId: secondWorktree.id,
                lastFocused: fixedDate
            )
        ])
    }

    @Test("Removing a repository persists the pruned repository and workspace state lists")
    @MainActor
    func removeRepositoryPersistsPrunedCatalog() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-remove-a"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-remove-b"))
        let firstWorktree = Worktree(
            workingDirectory: firstRepository.rootURL.appendingPathComponent("feature-a"),
            repositoryRootURL: firstRepository.rootURL
        )
        let secondWorktree = Worktree(
            workingDirectory: secondRepository.rootURL.appendingPathComponent("feature-b"),
            repositoryRootURL: secondRepository.rootURL
        )
        let recorder = CatalogPersistenceRecorder()
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository, secondRepository],
                worktreesByRepository: [
                    firstRepository.id: [firstWorktree],
                    secondRepository.id: [secondWorktree]
                ],
                workspaceStatesByID: [
                    firstWorktree.id: WorktreeState(worktreeId: firstWorktree.id),
                    secondWorktree.id: WorktreeState(worktreeId: secondWorktree.id)
                ],
                selectedRepositoryID: firstRepository.id,
                selectedWorkspaceID: firstWorktree.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.workspaceCatalogPersistenceClient.saveRepositories = { repositories in
                recorder.savedRepositories.append(repositories)
            }
            $0.workspaceCatalogPersistenceClient.saveWorkspaceStates = { states in
                recorder.savedWorkspaceStates.append(states)
            }
        }

        await store.send(.removeRepository(firstRepository.id)) {
            $0.repositories = [secondRepository]
            $0.worktreesByRepository = [secondRepository.id: [secondWorktree]]
            $0.workspaceStatesByID = [
                secondWorktree.id: WorktreeState(worktreeId: secondWorktree.id)
            ]
            $0.selectedRepositoryID = secondRepository.id
            $0.selectedWorkspaceID = secondWorktree.id
        }

        #expect(recorder.savedRepositories == [[secondRepository]])
        #expect(recorder.savedWorkspaceStates == [[WorktreeState(worktreeId: secondWorktree.id)]])
    }
}

@MainActor
private final class CatalogPersistenceRecorder {
    var savedRepositories: [[Repository]] = []
    var savedWorkspaceStates: [[WorktreeState]] = []
}
