import Foundation
import Testing
import Git
import Workspace
@testable import mac_client

@Suite("Worktree Metadata Coordinator Tests")
struct WorktreeMetadataCoordinatorTests {
    @Test("Coordinator keeps inactive repositories cold until selected")
    @MainActor
    func keepsInactiveRepositoriesColdUntilSelected() async throws {
        let fixture = await makeFixture()
        fixture.catalog.selectWorkspace(fixture.firstWorktree.id, in: fixture.firstRepository.id)
        fixture.coordinator.syncCatalog(fixture.catalog)

        let activeFirstStore = try #require(fixture.coordinator.activeStore)
        await waitForEntry(in: activeFirstStore, worktreeID: fixture.firstWorktree.id)
        let firstStore = try #require(fixture.stores.items.first)
        let secondStore = try #require(fixture.stores.items.last)

        #expect(fixture.stores.items.count == 2)
        #expect(fixture.coordinator.activeRepositoryID == fixture.firstRepository.id)
        #expect(firstStore.entriesById[fixture.firstWorktree.id] != nil)
        #expect(secondStore.entriesById[fixture.secondWorktree.id] == nil)
        #expect(await fixture.provider.requestedWorktreeIDs() == [fixture.firstWorktree.id])
        #expect(await fixture.statusProvider.requestedWorktreeIDs() == [fixture.firstWorktree.id])

        fixture.catalog.selectWorkspace(fixture.secondWorktree.id, in: fixture.secondRepository.id)
        fixture.coordinator.syncCatalog(fixture.catalog)

        let activeSecondStore = try #require(fixture.coordinator.activeStore)
        await waitForEntry(in: activeSecondStore, worktreeID: fixture.secondWorktree.id)
        let refreshedSecondStore = try #require(fixture.stores.items.last)

        #expect(fixture.coordinator.activeRepositoryID == fixture.secondRepository.id)
        #expect(refreshedSecondStore.entriesById[fixture.secondWorktree.id] != nil)
        #expect(await fixture.provider.requestedWorktreeIDs() == [
            fixture.firstWorktree.id,
            fixture.secondWorktree.id,
        ])
        #expect(await fixture.statusProvider.requestedWorktreeIDs() == [
            fixture.firstWorktree.id,
            fixture.secondWorktree.id,
        ])
    }

    @MainActor
    private func waitForEntry(in store: WorktreeInfoStore, worktreeID: Worktree.ID) async {
        for _ in 0..<50 {
            if store.entriesById[worktreeID] != nil { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for coordinated worktree metadata")
    }

    @MainActor
    private func makeFixture() async -> MetadataCoordinatorFixture {
        let repositories = makeRepositories()
        let firstRepository = repositories.first
        let secondRepository = repositories.second
        let firstWorktree = makeWorktree(name: "feature/a", repository: firstRepository, path: "feature-a")
        let secondWorktree = makeWorktree(name: "feature/b", repository: secondRepository, path: "feature-b")
        let listingService = StubCatalogWorktreeListingService(worktreesByRepositoryRoot: [
            firstRepository.id: [firstWorktree],
            secondRepository.id: [secondWorktree],
        ])
        let catalog = WindowWorkspaceCatalogStore { WorktreeManager(listingService: listingService) }
        let provider = RecordingMetadataProvider()
        let statusProvider = RecordingMetadataStatusProvider()
        let stores = WorktreeInfoStoreRecorder()
        let coordinator = makeCoordinator(
            provider: provider,
            statusProvider: statusProvider,
            stores: stores
        )
        await prepareCatalog(
            catalog,
            repositories: [firstRepository, secondRepository]
        )
        return MetadataCoordinatorFixture(
            catalog: catalog,
            coordinator: coordinator,
            stores: stores,
            provider: provider,
            statusProvider: statusProvider,
            firstRepository: firstRepository,
            secondRepository: secondRepository,
            firstWorktree: firstWorktree,
            secondWorktree: secondWorktree
        )
    }

    @MainActor
    private func prepareCatalog(
        _ catalog: WindowWorkspaceCatalogStore,
        repositories: [Repository]
    ) async {
        for repository in repositories {
            catalog.importRepository(repository)
        }
        await catalog.refreshRepositories()
    }

    private func makeWorktree(
        name: String,
        repository: Repository,
        path: String
    ) -> Worktree {
        Worktree(
            name: name,
            detail: ".",
            workingDirectory: repository.rootURL.appendingPathComponent(path),
            repositoryRootURL: repository.rootURL
        )
    }

    private func makeRepositories() -> (first: Repository, second: Repository) {
        (
            Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/metadata-a")),
            Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/metadata-b"))
        )
    }

    @MainActor
    private func makeCoordinator(
        provider: RecordingMetadataProvider,
        statusProvider: RecordingMetadataStatusProvider,
        stores: WorktreeInfoStoreRecorder
    ) -> WorktreeMetadataCoordinator {
        let coordinator = WorktreeMetadataCoordinator {
            let store = WorktreeInfoStore(
                infoProvider: provider,
                infoWatcher: NoopWorktreeInfoWatcher(),
                statusProvider: statusProvider,
                configuration: .init(
                    selectedRefreshInterval: 60,
                    backgroundRefreshInterval: 60,
                    deferredHydrationDelay: 60,
                    refreshDedupInterval: 0,
                    prRefreshInterval: 60
                )
            )
            stores.items.append(store)
            return store
        }
        return coordinator
    }
}

private struct MetadataCoordinatorFixture {
    let catalog: WindowWorkspaceCatalogStore
    let coordinator: WorktreeMetadataCoordinator
    let stores: WorktreeInfoStoreRecorder
    let provider: RecordingMetadataProvider
    let statusProvider: RecordingMetadataStatusProvider
    let firstRepository: Repository
    let secondRepository: Repository
    let firstWorktree: Worktree
    let secondWorktree: Worktree
}

@MainActor
private final class WorktreeInfoStoreRecorder {
    var items: [WorktreeInfoStore] = []
}

private actor RecordingMetadataProvider: WorktreeInfoProvider {
    private var requestedWorktreeIDsStorage: [Worktree.ID] = []

    func branchName(for worktreeURL: URL) async -> String? {
        requestedWorktreeIDsStorage.append(worktreeURL.path)
        return worktreeURL.lastPathComponent
    }

    func lineChanges(for worktreeURL: URL) async -> WorktreeLineChanges? {
        _ = worktreeURL
        return nil
    }

    func repositoryInfo(for worktreeURL: URL) async -> GitRepositoryInfo? {
        _ = worktreeURL
        return nil
    }

    func isPullRequestAvailable(for repositoryRoot: URL) async -> Bool {
        _ = repositoryRoot
        return false
    }

    func pullRequests(for repositoryRoot: URL, branches: [String]) async -> [String: PullRequest] {
        _ = repositoryRoot
        _ = branches
        return [:]
    }

    func requestedWorktreeIDs() -> [Worktree.ID] {
        requestedWorktreeIDsStorage
    }
}

private actor RecordingMetadataStatusProvider: WorktreeStatusProvider {
    private var requestedWorktreeIDsStorage: [Worktree.ID] = []

    func statusSummary(for worktreeURL: URL) async -> WorktreeStatusSummary? {
        requestedWorktreeIDsStorage.append(worktreeURL.path)
        return nil
    }

    func requestedWorktreeIDs() -> [Worktree.ID] {
        requestedWorktreeIDsStorage
    }
}
