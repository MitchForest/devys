import AppFeatures
import ComposableArchitecture
import Foundation
import Testing
import Workspace

@Suite("WindowFeature Repository Mutation Tests")
struct WindowFeatureRepositoryMutationTests {
    @Test("Opening resolved repositories can switch selection to the last imported repository")
    @MainActor
    func openResolvedRepositoriesSelectingLast() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository],
                selectedRepositoryID: firstRepository.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.recentRepositoriesClient.add = { _ in }
        }

        await store.send(.openResolvedRepositories([secondRepository])) {
            $0.repositories = [firstRepository, secondRepository]
            $0.selectedRepositoryID = secondRepository.id
            $0.selectedWorkspaceID = nil
        }
    }

    @Test("Opening resolved repositories can preserve the current selection")
    @MainActor
    func openResolvedRepositoriesPreservingSelection() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository],
                selectedRepositoryID: firstRepository.id
            )
        ) {
            WindowFeature()
        } withDependencies: {
            $0.recentRepositoriesClient.add = { _ in }
        }

        await store.send(.openResolvedRepositories([secondRepository, firstRepository])) {
            $0.repositories = [firstRepository, secondRepository]
        }
    }

    @Test("Opening resolved repositories de-duplicates repeated repositories")
    @MainActor
    func openResolvedRepositoriesDeduplicatesRepeats() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let store = TestStore(initialState: WindowFeature.State()) {
            WindowFeature()
        } withDependencies: {
            $0.recentRepositoriesClient.add = { _ in }
        }

        await store.send(
            .openResolvedRepositories([repository, secondRepository, repository, secondRepository])
        ) {
            $0.repositories = [repository, secondRepository]
            $0.selectedRepositoryID = secondRepository.id
        }
    }

    @Test("Removing a repository clears its inventory and restores fallback selection")
    @MainActor
    func removeRepository() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let firstWorkspace = Worktree(
            workingDirectory: firstRepository.rootURL.appendingPathComponent("feature-a"),
            repositoryRootURL: firstRepository.rootURL
        )
        let secondWorkspace = Worktree(
            workingDirectory: secondRepository.rootURL.appendingPathComponent("feature-b"),
            repositoryRootURL: secondRepository.rootURL
        )
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository, secondRepository],
                worktreesByRepository: [
                    firstRepository.id: [firstWorkspace],
                    secondRepository.id: [secondWorkspace],
                ],
                workspaceStatesByID: [
                    firstWorkspace.id: WorktreeState(worktreeId: firstWorkspace.id),
                    secondWorkspace.id: WorktreeState(worktreeId: secondWorkspace.id),
                ],
                selectedRepositoryID: firstRepository.id,
                selectedWorkspaceID: firstWorkspace.id,
                workspaceShells: [
                    firstWorkspace.id: WindowFeature.WorkspaceShell(activeSidebar: .files),
                    secondWorkspace.id: WindowFeature.WorkspaceShell(activeSidebar: .agents),
                ]
            )
        ) {
            WindowFeature()
        }

        await store.send(.removeRepository(firstRepository.id)) {
            $0.repositories = [secondRepository]
            $0.worktreesByRepository = [secondRepository.id: [secondWorkspace]]
            $0.workspaceStatesByID = [secondWorkspace.id: WorktreeState(worktreeId: secondWorkspace.id)]
            $0.selectedRepositoryID = secondRepository.id
            $0.selectedWorkspaceID = secondWorkspace.id
            $0.workspaceShells = [
                secondWorkspace.id: WindowFeature.WorkspaceShell(activeSidebar: .agents)
            ]
            $0.activeSidebar = .agents
        }
    }

    @Test("Moving repositories updates order without changing selection")
    @MainActor
    func moveRepository() async {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let thirdRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-notes"))
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [firstRepository, secondRepository, thirdRepository],
                selectedRepositoryID: secondRepository.id
            )
        ) {
            WindowFeature()
        }

        await store.send(.moveRepository(thirdRepository.id, by: -2)) {
            $0.repositories = [thirdRepository, firstRepository, secondRepository]
        }
    }

    @Test("Setting repository source control updates the reducer-owned catalog")
    @MainActor
    func setRepositorySourceControl() async {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let store = TestStore(
            initialState: WindowFeature.State(
                repositories: [repository]
            )
        ) {
            WindowFeature()
        }

        await store.send(.setRepositorySourceControl(.git, for: repository.id)) {
            $0.repositories[0].sourceControl = .git
        }
    }
}
