import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("WindowState Tests")
struct WindowStateTests {
    @Test("A new window starts without repositories or workspace selection")
    @MainActor
    func initialState() {
        let state = WindowState()

        #expect(state.repositories.isEmpty)
        #expect(state.selectedRepositoryID == nil)
        #expect(state.selectedWorkspaceID == nil)
        #expect(!state.hasRepositories)
    }

    @Test("Opening repositories updates repository selection")
    @MainActor
    func openRepository() {
        let state = WindowState()
        let firstRepositoryURL = URL(fileURLWithPath: "/tmp/devys-project")
        let secondRepositoryURL = URL(fileURLWithPath: "/tmp/devys-tools")

        state.openRepository(firstRepositoryURL)

        #expect(state.repositories.count == 1)
        #expect(state.selectedRepositoryRootURL == firstRepositoryURL)
        #expect(state.selectedWorkspaceID == nil)
        #expect(state.hasRepositories)

        state.openRepository(secondRepositoryURL)

        #expect(state.repositories.count == 2)
        #expect(state.selectedRepositoryRootURL == secondRepositoryURL)
    }

    @Test("Selecting a repository clears workspace selection")
    @MainActor
    func selectRepositoryClearsWorkspaceSelection() {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let state = WindowState(
            repositories: [firstRepository, secondRepository],
            selectedRepositoryID: firstRepository.id
        )

        state.selectWorkspace("/tmp/devys-project/workspaces/main")
        state.selectRepository(secondRepository.id)

        #expect(state.selectedRepositoryID == secondRepository.id)
        #expect(state.selectedWorkspaceID == nil)
    }

    @Test("Restoring selection preserves repository and workspace without interactive switching")
    @MainActor
    func restoreSelection() {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-project"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-tools"))
        let state = WindowState(repositories: [firstRepository, secondRepository])
        let workspaceID = "/tmp/devys-project/workspaces/feature"

        state.restoreSelection(
            repositoryID: firstRepository.id,
            workspaceID: workspaceID
        )

        #expect(state.selectedRepositoryID == firstRepository.id)
        #expect(state.selectedWorkspaceID == workspaceID)
        #expect(state.selectedRepositoryRootURL == firstRepository.rootURL)
    }

    @Test("Workspace switching stays responsive across ten repositories and one hundred workspaces")
    @MainActor
    func workspaceSwitchingAtScale() {
        let repositories = (0..<10).map { index in
            Repository(rootURL: URL(fileURLWithPath: "/tmp/devys-repo-\(index)"))
        }
        let workspaceIDsByRepository = Dictionary(
            uniqueKeysWithValues: repositories.map { repository in
                (
                    repository.id,
                    (0..<10).map { workspaceIndex in
                        "\(repository.rootURL.path)/workspaces/\(workspaceIndex)"
                    }
                )
            }
        )
        let state = WindowState(
            repositories: repositories,
            selectedRepositoryID: repositories.first?.id
        )
        let clock = ContinuousClock()
        let start = clock.now

        for iteration in 0..<100 {
            for repository in repositories {
                state.selectRepository(repository.id)
                if let workspaceID = workspaceIDsByRepository[repository.id]?[iteration % 10] {
                    state.selectWorkspace(workspaceID)
                }
            }
        }

        let elapsed = start.duration(to: clock.now)
        let lastRepository = repositories[9]
        let lastWorkspaceID = workspaceIDsByRepository[lastRepository.id]?[9]

        #expect(state.selectedRepositoryID == lastRepository.id)
        #expect(state.selectedWorkspaceID == lastWorkspaceID)
        #expect(elapsed < .seconds(1))
    }
}
