import AppFeatures
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
        fixture.coordinator.syncCatalog(
            runtimeSnapshot(
                repositories: fixture.repositories,
                worktreesByRepository: fixture.worktreesByRepository,
                selectedRepositoryID: fixture.firstRepository.id,
                selectedWorkspaceID: fixture.firstWorktree.id
            ),
            managedProcessesByWorkspace: [:]
        )
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

        fixture.coordinator.syncCatalog(
            runtimeSnapshot(
                repositories: fixture.repositories,
                worktreesByRepository: fixture.worktreesByRepository,
                selectedRepositoryID: fixture.secondRepository.id,
                selectedWorkspaceID: fixture.secondWorktree.id
            ),
            managedProcessesByWorkspace: [:]
        )
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
        let fixture = await makeManagedProcessFixture()

        fixture.coordinator.syncCatalog(
            runtimeSnapshot(
                repositories: fixture.repositories,
                worktreesByRepository: fixture.worktreesByRepository,
                selectedRepositoryID: fixture.repository.id,
                selectedWorkspaceID: fixture.selectedWorktree.id
            ),
            managedProcessesByWorkspace: [:]
        )
        let activeStore = try #require(fixture.coordinator.activeStore)
        await waitForPorts(in: activeStore, workspaceID: fixture.selectedWorktree.id)

        let start = ContinuousClock.now
        fixture.coordinator.syncCatalog(
            runtimeSnapshot(
                repositories: fixture.repositories,
                worktreesByRepository: fixture.worktreesByRepository,
                selectedRepositoryID: fixture.repository.id,
                selectedWorkspaceID: fixture.selectedWorktree.id
            ),
            managedProcessesByWorkspace: [
                fixture.managedWorktree.id: [ManagedWorkspaceProcess(processID: 222, displayName: "vite")]
            ]
        )
        await waitForPorts(in: activeStore, workspaceID: fixture.managedWorktree.id)
        let elapsed = start.duration(to: .now)

        #expect(
            fixture.coordinator.summary(for: fixture.managedWorktree.id) ==
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
        return PortCoordinatorFixture(
            coordinator: coordinator,
            stores: stores,
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

    @MainActor
    private func makeManagedProcessFixture() async -> ManagedProcessPortFixture {
        let repository = Repository(rootURL: URL(fileURLWithPath: "/tmp/devys/ports-managed"))
        let selectedWorktree = Worktree(
            workingDirectory: repository.rootURL.appendingPathComponent("selected"),
            repositoryRootURL: repository.rootURL
        )
        let managedWorktree = Worktree(
            workingDirectory: repository.rootURL.appendingPathComponent("managed"),
            repositoryRootURL: repository.rootURL
        )
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

        return ManagedProcessPortFixture(
            repository: repository,
            selectedWorktree: selectedWorktree,
            managedWorktree: managedWorktree,
            repositories: [repository],
            worktreesByRepository: [repository.id: [selectedWorktree, managedWorktree]],
            coordinator: coordinator
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

private struct PortCoordinatorFixture {
    let coordinator: WorkspacePortOwnershipCoordinator
    let stores: WorkspacePortStoreRecorder
    let repositories: [Repository]
    let worktreesByRepository: [Repository.ID: [Worktree]]
    let firstRepository: Repository
    let secondRepository: Repository
    let firstWorktree: Worktree
    let secondWorktree: Worktree
}

private struct ManagedProcessPortFixture {
    let repository: Repository
    let selectedWorktree: Worktree
    let managedWorktree: Worktree
    let repositories: [Repository]
    let worktreesByRepository: [Repository.ID: [Worktree]]
    let coordinator: WorkspacePortOwnershipCoordinator
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
