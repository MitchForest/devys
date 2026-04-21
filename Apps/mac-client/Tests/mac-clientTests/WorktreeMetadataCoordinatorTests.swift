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
        fixture.coordinator.syncCatalog(
            runtimeSnapshot(
                repositories: fixture.repositories,
                worktreesByRepository: fixture.worktreesByRepository,
                selectedRepositoryID: fixture.firstRepository.id,
                selectedWorkspaceID: fixture.firstWorktree.id
            )
        )

        let activeFirstStore = try #require(fixture.coordinator.activeStore)
        await waitForEntry(in: activeFirstStore, worktreeID: fixture.firstWorktree.id)
        let firstStore = try #require(fixture.stores.items.first)
        let secondStore = try #require(fixture.stores.items.last)

        #expect(fixture.stores.items.count == 2)
        #expect(fixture.coordinator.activeRepositoryID == fixture.firstRepository.id)
        #expect(firstStore.entriesById[fixture.firstWorktree.id] != nil)
        #expect(secondStore.entriesById[fixture.secondWorktree.id] == nil)
        #expect(await fixture.provider.requestedWorktreeIDs() == [fixture.firstWorktree.id])

        fixture.coordinator.syncCatalog(
            runtimeSnapshot(
                repositories: fixture.repositories,
                worktreesByRepository: fixture.worktreesByRepository,
                selectedRepositoryID: fixture.secondRepository.id,
                selectedWorkspaceID: fixture.secondWorktree.id
            )
        )

        let activeSecondStore = try #require(fixture.coordinator.activeStore)
        await waitForEntry(in: activeSecondStore, worktreeID: fixture.secondWorktree.id)
        let refreshedSecondStore = try #require(fixture.stores.items.last)

        #expect(fixture.coordinator.activeRepositoryID == fixture.secondRepository.id)
        #expect(refreshedSecondStore.entriesById[fixture.secondWorktree.id] != nil)
        #expect(await fixture.provider.requestedWorktreeIDs() == [
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
        let provider = RecordingMetadataProvider()
        let stores = WorktreeInfoStoreRecorder()
        let coordinator = makeCoordinator(
            provider: provider,
            stores: stores
        )
        return MetadataCoordinatorFixture(
            coordinator: coordinator,
            stores: stores,
            provider: provider,
            repositories: [firstRepository, secondRepository],
            worktreesByRepository: [
                firstRepository.id: [firstWorktree],
                secondRepository.id: [secondWorktree],
            ],
            firstRepository: firstRepository,
            secondRepository: secondRepository,
            firstWorktree: firstWorktree,
            secondWorktree: secondWorktree
        )
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
        stores: WorktreeInfoStoreRecorder
    ) -> WorktreeMetadataCoordinator {
        let coordinator = WorktreeMetadataCoordinator {
            let store = WorktreeInfoStore(
                infoProvider: provider,
                infoWatcher: NoopWorktreeInfoWatcher(),
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

@MainActor
private func runtimeSnapshot(
    repositories: [Repository],
    worktreesByRepository: [Repository.ID: [Worktree]],
    selectedRepositoryID: Repository.ID?,
    selectedWorkspaceID: Workspace.ID?
) -> WindowCatalogRuntimeSnapshot {
    WindowCatalogRuntimeSnapshot(
        repositories: repositories,
        worktreesByRepository: worktreesByRepository,
        selectedRepositoryID: selectedRepositoryID,
        selectedWorkspaceID: selectedWorkspaceID
    )
}

private struct MetadataCoordinatorFixture {
    let coordinator: WorktreeMetadataCoordinator
    let stores: WorktreeInfoStoreRecorder
    let provider: RecordingMetadataProvider
    let repositories: [Repository]
    let worktreesByRepository: [Repository.ID: [Worktree]]
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

    func snapshot(for worktreeURL: URL) async -> WorktreeGitSnapshot {
        requestedWorktreeIDsStorage.append(worktreeURL.path)
        return WorktreeGitSnapshot(
            isRepositoryAvailable: true,
            branchName: worktreeURL.lastPathComponent,
            repositoryInfo: nil,
            lineChanges: nil,
            statusSummary: nil,
            changes: []
        )
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
