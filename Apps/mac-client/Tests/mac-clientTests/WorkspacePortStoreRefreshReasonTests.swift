import Foundation
import AppFeatures
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Port Store Context Refresh Reason Tests")
struct WorkspacePortStoreContextRefreshReasonTests {
    @Test("Identical context updates do not trigger redundant port scans")
    @MainActor
    func identicalContextUpdatesDoNotTriggerRedundantPortScans() async {
        let workspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let provider = CountingWorkspacePortSnapshotProvider(
            snapshot: [workspace.id: [ownedPort(workspaceID: workspace.id)]]
        )
        let store = WorkspacePortStore(
            snapshotProvider: provider,
            configuration: .init(
                selectedRefreshInterval: 60,
                backgroundRefreshInterval: 60,
                refreshDedupInterval: 0
            )
        )

        store.update(
            worktrees: [workspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: workspace.id
        )
        await waitForRefreshRecordCount(1, in: store)

        store.update(
            worktrees: [workspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: workspace.id
        )
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.refreshRecords.map(\.reason) == [.contextChange])
        #expect(await provider.refreshCount() == 1)
    }

    @Test("Managed process changes refresh only the owning workspace")
    @MainActor
    func managedProcessChangesRefreshOnlyTheOwningWorkspace() async {
        let selectedWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a/selected"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let managedWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a/managed"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let provider = ContextRecordingWorkspacePortSnapshotProvider()
        let store = WorkspacePortStore(
            snapshotProvider: provider,
            configuration: .init(
                selectedRefreshInterval: 60,
                backgroundRefreshInterval: 60,
                refreshDedupInterval: 0
            )
        )

        store.update(
            worktrees: [selectedWorkspace, managedWorkspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: selectedWorkspace.id
        )
        await waitForRefreshRecordCount(1, in: store)

        store.update(
            worktrees: [selectedWorkspace, managedWorkspace],
            managedProcessesByWorkspace: [
                managedWorkspace.id: [ManagedWorkspaceProcess(processID: 222, displayName: "vite")]
            ],
            selectedWorktreeId: selectedWorkspace.id
        )
        await waitForRefreshRecordCount(2, in: store)

        let requestedWorkspaceIDs = await provider.requestedWorkspaceIDs()

        #expect(store.refreshRecords.map(\.reason) == [.contextChange, .managedProcessLaunch])
        #expect(store.refreshRecords.last?.workspaceIDs == [managedWorkspace.id])
        #expect(requestedWorkspaceIDs == [[selectedWorkspace.id], [managedWorkspace.id]])
    }

    @Test("Managed process exit records an explicit refresh reason")
    @MainActor
    func managedProcessExitRecordsAnExplicitRefreshReason() async {
        let selectedWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a/selected"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let managedWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a/managed"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let store = WorkspacePortStore(
            snapshotProvider: ContextRecordingWorkspacePortSnapshotProvider(),
            configuration: .init(
                selectedRefreshInterval: 60,
                backgroundRefreshInterval: 60,
                refreshDedupInterval: 0
            )
        )

        store.update(
            worktrees: [selectedWorkspace, managedWorkspace],
            managedProcessesByWorkspace: [
                managedWorkspace.id: [ManagedWorkspaceProcess(processID: 222, displayName: "vite")]
            ],
            selectedWorktreeId: selectedWorkspace.id
        )
        await waitForRefreshRecordCount(2, in: store)

        store.update(
            worktrees: [selectedWorkspace, managedWorkspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: selectedWorkspace.id
        )
        await waitForRefreshRecordCount(3, in: store)

        #expect(
            store.refreshRecords.map(\.reason) == [
                .managedProcessLaunch,
                .contextChange,
                .managedProcessExit,
            ]
        )
        #expect(store.refreshRecords.last?.workspaceIDs == [managedWorkspace.id])
    }

}

@Suite("Workspace Port Store Scheduled Refresh Reason Tests")
struct WorkspacePortStoreScheduledRefreshReasonTests {
    @Test("Selected periodic refresh records an explicit reason")
    @MainActor
    func selectedPeriodicRefreshRecordsAnExplicitReason() async {
        let workspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let store = WorkspacePortStore(
            snapshotProvider: ContextRecordingWorkspacePortSnapshotProvider(),
            configuration: .init(
                selectedRefreshInterval: 0.05,
                backgroundRefreshInterval: 60,
                refreshDedupInterval: 0
            )
        )

        store.update(
            worktrees: [workspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: workspace.id
        )
        await waitForRefreshRecordCount(2, in: store)
        let refreshRecords = Array(store.refreshRecords.prefix(2))

        #expect(refreshRecords.map(\.reason) == [.contextChange, .selectedPeriodic])
        #expect(refreshRecords.last?.workspaceIDs == [workspace.id])
    }

    @Test("Background workspaces use the slower background inference lane")
    @MainActor
    func backgroundWorkspacesUseTheSlowerBackgroundInferenceLane() async {
        let selectedWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a/selected"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let backgroundWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a/background"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let store = WorkspacePortStore(
            snapshotProvider: ContextRecordingWorkspacePortSnapshotProvider(),
            configuration: .init(
                selectedRefreshInterval: 60,
                backgroundRefreshInterval: 0.05,
                refreshDedupInterval: 0
            )
        )

        store.update(
            worktrees: [selectedWorkspace, backgroundWorkspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: selectedWorkspace.id
        )
        await waitForRefreshRecordCount(2, in: store)

        #expect(store.refreshRecords.map(\.reason) == [.contextChange, .backgroundPeriodic])
        #expect(store.refreshRecords.last?.workspaceIDs == [backgroundWorkspace.id])
    }

    @Test("Manual refresh records an explicit reason")
    @MainActor
    func manualRefreshRecordsAnExplicitReason() async {
        let workspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let store = WorkspacePortStore(
            snapshotProvider: ContextRecordingWorkspacePortSnapshotProvider(),
            configuration: .init(
                selectedRefreshInterval: 60,
                backgroundRefreshInterval: 60,
                refreshDedupInterval: 0
            )
        )

        store.update(
            worktrees: [workspace],
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: workspace.id
        )
        await waitForRefreshRecordCount(1, in: store)

        store.refresh(workspaceIDs: [workspace.id])
        await waitForRefreshRecordCount(2, in: store)

        #expect(store.refreshRecords.map(\.reason) == [.contextChange, .manual])
        #expect(store.refreshRecords.last?.workspaceIDs == [workspace.id])
    }
}

@MainActor
private func waitForRefreshRecordCount(_ expectedCount: Int, in store: WorkspacePortStore) async {
    for _ in 0..<50 {
        if store.refreshRecords.count >= expectedCount {
            return
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for workspace port refresh records")
}

private func ownedPort(workspaceID: Workspace.ID) -> WorkspacePort {
    WorkspacePort(
        workspaceID: workspaceID,
        port: 3000,
        processIDs: [111],
        processNames: ["node"],
        ownership: .owned
    )
}
