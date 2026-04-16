import Foundation
import AppFeatures
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Port Detection Tests")
struct WorkspacePortDetectionTests {
    @Test("Listening ports inherit workspace ownership from cwd and conflicting ports stay conflicted")
    func detectsPortsAndConflicts() async {
        let firstWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let secondWorkspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-b"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-b")
        )
        let provider = DefaultWorkspacePortSnapshotProvider(
            commandRunner: commandRunner(
                listeningOutput: """
                p101
                cnode
                nTCP *:3000 (LISTEN)
                p202
                cpython
                nTCP 127.0.0.1:3000 (LISTEN)
                """,
                processOutput: """
                1 0
                101 1
                202 1
                """,
                workingDirectoryOutputs: [
                    "1,101,202": """
                    p101
                    n/tmp/devys/repo-a
                    p202
                    n/tmp/devys/repo-b
                    """
                ]
            )
        )

        let snapshot = await provider.snapshot(
            context: WorkspacePortObservationContext(
                worktreesByID: [
                    firstWorkspace.id: firstWorkspace,
                    secondWorkspace.id: secondWorkspace,
                ],
                managedProcessesByWorkspace: [:]
            )
        )

        #expect(snapshot[firstWorkspace.id]?.count == 1)
        #expect(snapshot[secondWorkspace.id]?.count == 1)
        #expect(snapshot[firstWorkspace.id]?.first?.port == 3000)
        #expect(snapshot[secondWorkspace.id]?.first?.port == 3000)
        #expect(snapshot[firstWorkspace.id]?.first?.ownership == .conflicted)
        #expect(snapshot[secondWorkspace.id]?.first?.ownership == .conflicted)
    }

    @Test("Managed Devys processes own ports even when cwd inference is unavailable")
    func detectsManagedProcessOwnership() async {
        let workspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let provider = DefaultWorkspacePortSnapshotProvider(
            commandRunner: commandRunner(
                listeningOutput: """
                p303
                cvite
                nTCP *:5173 (LISTEN)
                """,
                processOutput: """
                1 0
                303 1
                """,
                workingDirectoryOutputs: ["1,303": ""]
            )
        )

        let snapshot = await provider.snapshot(
            context: WorkspacePortObservationContext(
                worktreesByID: [workspace.id: workspace],
                managedProcessesByWorkspace: [
                    workspace.id: [ManagedWorkspaceProcess(processID: 303, displayName: "Vite")]
                ]
            )
        )

        #expect(snapshot[workspace.id]?.count == 1)
        #expect(snapshot[workspace.id]?.first?.port == 5173)
        #expect(snapshot[workspace.id]?.first?.ownership == .owned)
    }
}

@Suite("Workspace Port Store Tests")
struct WorkspacePortStoreTests {
    @Test("Store publishes summaries and clears state when workspaces disappear")
    @MainActor
    func summariesAndCleanup() async {
        let workspace = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-a")
        )
        let store = WorkspacePortStore(
            snapshotProvider: StubWorkspacePortSnapshotProvider(
                snapshots: [
                    [
                        workspace.id: [
                            WorkspacePort(
                                workspaceID: workspace.id,
                                port: 3000,
                                processIDs: [111],
                                processNames: ["node"],
                                ownership: .owned
                            ),
                            WorkspacePort(
                                workspaceID: workspace.id,
                                port: 5173,
                                processIDs: [222],
                                processNames: ["vite"],
                                ownership: .conflicted
                            ),
                        ]
                    ]
                ]
            )
        )

        store.update(worktrees: [workspace], managedProcessesByWorkspace: [:])
        await waitForPorts(in: store, workspaceID: workspace.id, expectedCount: 2)

        let summary = store.summary(for: workspace.id)
        #expect(summary == WorkspacePortSummary(totalCount: 2, conflictCount: 1))

        store.update(worktrees: [], managedProcessesByWorkspace: [:])

        #expect(store.ports(for: workspace.id).isEmpty)
        #expect(store.summary(for: workspace.id) == nil)
    }

    @Test("Background port refresh stays responsive with one hundred workspaces")
    @MainActor
    func refreshAtScale() async {
        let worktrees = (0..<100).map { index in
            let repositoryIndex = index / 10
            return Worktree(
                workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo-\(repositoryIndex)-workspace-\(index)"),
                repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo-\(repositoryIndex)")
            )
        }
        let snapshot = Dictionary(uniqueKeysWithValues: worktrees.enumerated().map { index, workspace in
            (
                workspace.id,
                [
                    WorkspacePort(
                        workspaceID: workspace.id,
                        port: 3000 + index,
                        processIDs: [Int32(index + 100)],
                        processNames: ["server-\(index)"],
                        ownership: .owned
                    )
                ]
            )
        })
        let store = WorkspacePortStore(
            snapshotProvider: StubWorkspacePortSnapshotProvider(snapshots: [snapshot])
        )
        let clock = ContinuousClock()
        let start = clock.now

        store.update(worktrees: worktrees, managedProcessesByWorkspace: [:])
        await waitForWorkspaceCount(in: store, expectedCount: worktrees.count)

        let elapsed = start.duration(to: clock.now)
        let targetWorkspace = worktrees[57]

        #expect(store.summariesByWorkspace.count == worktrees.count)
        #expect(store.summary(for: targetWorkspace.id) == WorkspacePortSummary(totalCount: 1, conflictCount: 0))
        #expect(elapsed < .seconds(2))
    }

    @Test("Selected workspace scope avoids whole-repository port scans")
    @MainActor
    func selectedWorkspaceScopeAvoidsWholeRepositoryPortScans() async {
        let worktrees = (0..<100).map { index in
            Worktree(
                workingDirectory: URL(fileURLWithPath: "/tmp/devys/repo/workspace-\(index)"),
                repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repo")
            )
        }
        let selectedWorkspace = worktrees[42]
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
            worktrees: worktrees,
            managedProcessesByWorkspace: [:],
            selectedWorktreeId: selectedWorkspace.id
        )
        await waitForPorts(in: store, workspaceID: selectedWorkspace.id, expectedCount: 1)

        let requestedWorkspaceIDs = await provider.requestedWorkspaceIDs()
        #expect(requestedWorkspaceIDs == [[selectedWorkspace.id]])
        #expect(store.summariesByWorkspace.count == 1)
    }

    @MainActor
    private func waitForPorts(
        in store: WorkspacePortStore,
        workspaceID: Workspace.ID,
        expectedCount: Int
    ) async {
        for _ in 0..<50 {
            if store.ports(for: workspaceID).count == expectedCount {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for workspace ports")
    }

    @MainActor
    private func waitForWorkspaceCount(
        in store: WorkspacePortStore,
        expectedCount: Int
    ) async {
        for _ in 0..<50 {
            if store.summariesByWorkspace.count == expectedCount {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for workspace port summaries")
    }

}
