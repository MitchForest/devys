import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Repository Navigator Catalog Planner Tests")
struct RepositoryNavigatorCatalogPlannerTests {
    @Test("Added repositories refresh without reloading unchanged cached repositories")
    func addedRepositoriesRefreshWithoutReloadingUnchangedCache() {
        let existingRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/repo-a"))
        let addedRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/repo-b"))

        let plan = RepositoryNavigatorCatalogPlanner.makePlan(
            previousRepositories: [existingRepository],
            currentRepositories: [existingRepository, addedRepository],
            cachedRepositoryIDs: [existingRepository.id]
        )

        #expect(plan.repositoryIDsToRemove.isEmpty)
        #expect(plan.repositoryIDsToRefresh == [addedRepository.id])
    }

    @Test("Removed repositories are pruned from the navigator cache")
    func removedRepositoriesArePrunedFromNavigatorCache() {
        let retainedRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/repo-a"))
        let removedRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/repo-b"))

        let plan = RepositoryNavigatorCatalogPlanner.makePlan(
            previousRepositories: [retainedRepository, removedRepository],
            currentRepositories: [retainedRepository],
            cachedRepositoryIDs: [retainedRepository.id, removedRepository.id]
        )

        #expect(plan.repositoryIDsToRemove == [removedRepository.id])
        #expect(plan.repositoryIDsToRefresh.isEmpty)
    }

    @Test("Missing cache entries for unchanged repositories are refilled")
    func missingCacheEntriesForUnchangedRepositoriesAreRefilled() {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/repo-a"))

        let plan = RepositoryNavigatorCatalogPlanner.makePlan(
            previousRepositories: [repository],
            currentRepositories: [repository],
            cachedRepositoryIDs: []
        )

        #expect(plan.repositoryIDsToRemove.isEmpty)
        #expect(plan.repositoryIDsToRefresh == [repository.id])
    }
}
