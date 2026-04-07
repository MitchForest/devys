import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Port Ownership Coordinator Tests")
struct WorkspacePortOwnershipCoordinatorTests {
    @Test("Coordinator keeps inactive repositories cold until selected")
    @MainActor
    func keepsInactiveRepositoriesColdUntilSelected() async throws {
        let fixture = await makeFixture()
        fixture.catalog.selectWorkspace(fixture.firstWorktree.id, in: fixture.firstRepository.id)
        fixture.coordinator.syncCatalog(fixture.catalog, managedProcessesByWorkspace: [:])
        let firstStore = try #require(fixture.stores.items.first)
        await waitForPorts(in: firstStore, workspaceID: fixture.firstWorktree.id)
        let secondStore = try #require(fixture.stores.items.last)

        #expect(fixture.stores.items.count == 2)
        #expect(fixture.coordinator.activeRepositoryID == fixture.firstRepository.id)
        #expect(
            fixture.coordinator.summary(for: fixture.firstWorktree.id) ==
            WorkspacePortSummary(totalCount: 1, conflictCount: 0)
        )
        #expect(fixture.coordinator.summary(for: fixture.secondWorktree.id) == nil)
        #expect(secondStore.summariesByWorkspace.isEmpty)

        fixture.catalog.selectWorkspace(fixture.secondWorktree.id, in: fixture.secondRepository.id)
        fixture.coordinator.syncCatalog(fixture.catalog, managedProcessesByWorkspace: [:])
        let refreshedSecondStore = try #require(fixture.stores.items.last)
        await waitForPorts(in: refreshedSecondStore, workspaceID: fixture.secondWorktree.id)

        #expect(fixture.coordinator.activeRepositoryID == fixture.secondRepository.id)
        #expect(
            fixture.coordinator.summary(for: fixture.secondWorktree.id) ==
            WorkspacePortSummary(totalCount: 1, conflictCount: 0)
        )
        #expect(fixture.coordinator.activeSummariesByWorkspace == [
            fixture.secondWorktree.id: WorkspacePortSummary(totalCount: 1, conflictCount: 0)
        ])
    }

    @Test("Managed process sync updates the active repository immediately")
    @MainActor
    func managedProcessSyncRefreshesActiveRepositoryWithoutDebounce() async throws {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/ports-managed"))
        let selectedWorktree = Worktree(
            workingDirectory: repository.rootURL.appendingPathComponent("selected"),
            repositoryRootURL: repository.rootURL
        )
        let managedWorktree = Worktree(
            workingDirectory: repository.rootURL.appendingPathComponent("managed"),
            repositoryRootURL: repository.rootURL
        )
        let listingService = StubCatalogWorktreeListingService(
            worktreesByRepositoryRoot: [repository.id: [selectedWorktree, managedWorktree]]
        )
        let catalog = WindowWorkspaceCatalogStore { WorktreeManager(listingService: listingService) }
        catalog.importRepository(repository)
        await catalog.refreshRepositories()
        catalog.selectWorkspace(selectedWorktree.id, in: repository.id)

        let provider = SequencedWorkspacePortSnapshotProvider(
            snapshots: [
                [selectedWorktree.id: [ownedPort(workspaceID: selectedWorktree.id, port: 3001, processID: 111)]],
                [managedWorktree.id: [ownedPort(workspaceID: managedWorktree.id, port: 3002, processID: 222)]],
            ]
        )
        let coordinator = WorkspacePortOwnershipCoordinator {
            WorkspacePortStore(
                snapshotProvider: provider,
                configuration: .init(
                    selectedRefreshInterval: 60,
                    backgroundRefreshInterval: 60,
                    refreshDedupInterval: 0
                )
            )
        }

        coordinator.syncCatalog(catalog, managedProcessesByWorkspace: [:])
        let activeStore = try #require(coordinator.activeStore)
        await waitForPorts(in: activeStore, workspaceID: selectedWorktree.id)

        let start = ContinuousClock.now
        coordinator.syncCatalog(
            catalog,
            managedProcessesByWorkspace: [
                managedWorktree.id: [ManagedWorkspaceProcess(processID: 222, displayName: "vite")]
            ]
        )
        await waitForPorts(in: activeStore, workspaceID: managedWorktree.id)
        let elapsed = start.duration(to: .now)

        #expect(
            coordinator.summary(for: managedWorktree.id) ==
            WorkspacePortSummary(totalCount: 1, conflictCount: 0)
        )
        #expect(elapsed < .milliseconds(250))
    }

    @MainActor
    private func waitForPorts(in store: WorkspacePortStore, workspaceID: Workspace.ID) async {
        for _ in 0..<50 {
            if store.ports(for: workspaceID).count == 1 { return }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for coordinated workspace ports")
    }

    @MainActor
    private func makeFixture() async -> PortCoordinatorFixture {
        let firstRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/ports-a"))
        let secondRepository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/ports-b"))
        let firstWorktree = Worktree(
            workingDirectory: firstRepository.rootURL.appendingPathComponent("feature-a"),
            repositoryRootURL: firstRepository.rootURL
        )
        let secondWorktree = Worktree(
            workingDirectory: secondRepository.rootURL.appendingPathComponent("feature-b"),
            repositoryRootURL: secondRepository.rootURL
        )
        let listingService = StubCatalogWorktreeListingService(
            worktreesByRepositoryRoot: [
                firstRepository.id: [firstWorktree],
                secondRepository.id: [secondWorktree],
            ]
        )
        let catalog = WindowWorkspaceCatalogStore { WorktreeManager(listingService: listingService) }
        let snapshots: [[Workspace.ID: [WorkspacePort]]] = [
            [firstWorktree.id: [ownedPort(workspaceID: firstWorktree.id, port: 3001, processID: 111)]],
            [secondWorktree.id: [ownedPort(workspaceID: secondWorktree.id, port: 3002, processID: 222)]],
        ]
        let stores = WorkspacePortStoreRecorder()
        let coordinator = WorkspacePortOwnershipCoordinator {
            let store = WorkspacePortStore(
                snapshotProvider: StaticWorkspacePortSnapshotProvider(
                    snapshot: snapshots[stores.items.count]
                ),
                configuration: .init(
                    selectedRefreshInterval: 60,
                    backgroundRefreshInterval: 60,
                    refreshDedupInterval: 0
                )
            )
            stores.items.append(store)
            return store
        }
        catalog.importRepository(firstRepository)
        catalog.importRepository(secondRepository)
        await catalog.refreshRepositories()
        return PortCoordinatorFixture(
            catalog: catalog,
            coordinator: coordinator,
            stores: stores,
            firstRepository: firstRepository,
            secondRepository: secondRepository,
            firstWorktree: firstWorktree,
            secondWorktree: secondWorktree
        )
    }

    private func ownedPort(
        workspaceID: Workspace.ID,
        port: Int,
        processID: Int32
    ) -> WorkspacePort {
        WorkspacePort(
            workspaceID: workspaceID,
            port: port,
            processIDs: [processID],
            processNames: ["node"],
            ownership: .owned
        )
    }
}

private struct PortCoordinatorFixture {
    let catalog: WindowWorkspaceCatalogStore
    let coordinator: WorkspacePortOwnershipCoordinator
    let stores: WorkspacePortStoreRecorder
    let firstRepository: Repository
    let secondRepository: Repository
    let firstWorktree: Worktree
    let secondWorktree: Worktree
}

@MainActor
private final class WorkspacePortStoreRecorder {
    var items: [WorkspacePortStore] = []
}

private struct StaticWorkspacePortSnapshotProvider: WorkspacePortSnapshotProvider {
    let snapshot: [Workspace.ID: [WorkspacePort]]

    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]] {
        _ = context
        return snapshot
    }
}

private actor SequencedWorkspacePortSnapshotProvider: WorkspacePortSnapshotProvider {
    private let snapshots: [[Workspace.ID: [WorkspacePort]]]
    private var index = 0

    init(snapshots: [[Workspace.ID: [WorkspacePort]]]) {
        self.snapshots = snapshots
    }

    func snapshot(context: WorkspacePortObservationContext) async -> [Workspace.ID: [WorkspacePort]] {
        _ = context
        let currentIndex = index
        index += 1
        if currentIndex < snapshots.count {
            return snapshots[currentIndex]
        }
        return snapshots.last ?? [:]
    }
}
