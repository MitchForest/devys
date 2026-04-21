import Foundation
import Testing
import Git
import Workspace
@testable import mac_client

@Suite("Worktree Info Store Tests")
struct WorktreeInfoStoreTests {
    @Test("Refresh populates branch, sync, and dirty metadata for navigator rows")
    @MainActor
    func refreshPopulatesMetadata() async {
        let worktree = Worktree(
            name: "feature/navigator",
            detail: ".",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-repo"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-repo")
        )

        let store = WorktreeInfoStore(
            infoProvider: StubWorktreeInfoProvider(
                snapshot: WorktreeGitSnapshot(
                    isRepositoryAvailable: true,
                    branchName: "feature/navigator",
                    repositoryInfo: GitRepositoryInfo(
                        currentBranch: "feature/navigator",
                        aheadCount: 2,
                        behindCount: 1
                    ),
                    lineChanges: WorktreeLineChanges(added: 12, removed: 4),
                    statusSummary: WorktreeStatusSummary(
                        staged: 1,
                        unstaged: 2,
                        untracked: 3,
                        conflicts: 0
                    ),
                    changes: []
                ),
            ),
            infoWatcher: NoopWorktreeInfoWatcher()
        )

        _ = store.update(worktrees: [worktree], repositoryRootURL: worktree.repositoryRootURL)
        store.refreshAll()
        await waitForEntry(in: store, worktreeID: worktree.id)

        let entry = store.entriesById[worktree.id]
        #expect(entry?.branchName == "feature/navigator")
        #expect(entry?.repositoryInfo?.aheadCount == 2)
        #expect(entry?.repositoryInfo?.behindCount == 1)
        #expect(entry?.lineChanges == WorktreeLineChanges(added: 12, removed: 4))
        #expect(
            entry?.statusSummary ==
            WorktreeStatusSummary(staged: 1, unstaged: 2, untracked: 3, conflicts: 0)
        )
    }

    @Test("File change events refresh only the selected workspace metadata")
    @MainActor
    func fileChangesRefreshOnlySelectedWorkspace() async {
        let selected = Worktree(
            name: "selected",
            detail: ".",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-selected"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-repo")
        )
        let background = Worktree(
            name: "background",
            detail: ".",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-background"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-repo")
        )
        let watcher = TestWorktreeInfoWatcher()
        let provider = RecordingWorktreeInfoProvider()
        let store = WorktreeInfoStore(
            infoProvider: provider,
            infoWatcher: watcher,
            configuration: .init(
                selectedRefreshInterval: 60,
                backgroundRefreshInterval: 60,
                deferredHydrationDelay: 60,
                refreshDedupInterval: 60,
                prRefreshInterval: 60
            )
        )

        _ = store.update(worktrees: [selected, background], repositoryRootURL: selected.repositoryRootURL)
        store.setSelectedWorktreeId(selected.id)
        await waitForEntry(in: store, worktreeID: selected.id)
        await provider.resetRequestedWorktreeIDs()

        await watcher.waitUntilReady()
        watcher.emit(.filesChanged(worktreeId: background.id))
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(await provider.requestedWorktreeIDs().isEmpty)

        watcher.emit(.filesChanged(worktreeId: selected.id))
        await waitForRecordedRefresh(provider: provider, worktreeID: selected.id)

        #expect(await provider.requestedWorktreeIDs() == [selected.id])
        #expect(store.entriesById[background.id] == nil)
    }

    @Test("Initial selection hydrates only the selected worktree immediately")
    @MainActor
    func initialSelectionHydratesOnlySelectedWorktreeImmediately() async {
        let selected = Worktree(
            name: "selected",
            detail: ".",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-selected"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-repo")
        )
        let background = Worktree(
            name: "background",
            detail: ".",
            workingDirectory: URL(fileURLWithPath: "/tmp/devys-background"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys-repo")
        )
        let provider = RecordingWorktreeInfoProvider()
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

        _ = store.update(worktrees: [selected, background], repositoryRootURL: selected.repositoryRootURL)
        store.setSelectedWorktreeId(selected.id)
        await waitForEntry(in: store, worktreeID: selected.id)

        #expect(await provider.requestedWorktreeIDs() == [selected.id])
        #expect(store.entriesById[selected.id] != nil)
        #expect(store.entriesById[background.id] == nil)
    }

    @MainActor
    private func waitForEntry(in store: WorktreeInfoStore, worktreeID: Worktree.ID) async {
        for _ in 0..<50 {
            if store.entriesById[worktreeID] != nil {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for worktree metadata")
    }

    private func waitForRecordedRefresh(
        provider: RecordingWorktreeInfoProvider,
        worktreeID: Worktree.ID
    ) async {
        for _ in 0..<50 {
            let infoIDs = await provider.requestedWorktreeIDs()
            if infoIDs == [worktreeID] {
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("Timed out waiting for worktree refresh recording")
    }

}

private struct StubWorktreeInfoProvider: WorktreeInfoProvider {
    let snapshot: WorktreeGitSnapshot

    func snapshot(for worktreeURL: URL) async -> WorktreeGitSnapshot {
        _ = worktreeURL
        return snapshot
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
}

private final class TestWorktreeInfoWatcher: WorktreeInfoWatcher, @unchecked Sendable {
    private let readyStream = AsyncStream.makeStream(of: Void.self)
    private let eventStreamStorage = AsyncStream.makeStream(of: WorktreeInfoEvent.self)
    private let stateQueue = DispatchQueue(label: "WorktreeInfoStoreTests.TestWorktreeInfoWatcher")
    private var isReady = false

    func handle(_ command: WorktreeInfoCommand) {
        _ = command
    }

    func eventStream() -> AsyncStream<WorktreeInfoEvent> {
        let shouldSignalReady = stateQueue.sync { () -> Bool in
            guard !isReady else { return false }
            isReady = true
            return true
        }
        if shouldSignalReady {
            readyStream.continuation.yield(())
            readyStream.continuation.finish()
        }
        return eventStreamStorage.stream
    }

    func emit(_ event: WorktreeInfoEvent) {
        eventStreamStorage.continuation.yield(event)
    }

    func waitUntilReady() async {
        let alreadyReady = stateQueue.sync { isReady }
        if alreadyReady {
            return
        }

        for await _ in readyStream.stream {
            return
        }
    }
}

private actor RecordingWorktreeInfoProvider: WorktreeInfoProvider {
    private var requestedWorktreeIDsStorage: Set<Worktree.ID> = []

    func snapshot(for worktreeURL: URL) async -> WorktreeGitSnapshot {
        requestedWorktreeIDsStorage.insert(worktreeURL.path)
        return WorktreeGitSnapshot(
            isRepositoryAvailable: true,
            branchName: worktreeURL.lastPathComponent,
            repositoryInfo: GitRepositoryInfo(currentBranch: worktreeURL.lastPathComponent),
            lineChanges: WorktreeLineChanges(added: 1, removed: 0),
            statusSummary: WorktreeStatusSummary(staged: 0, unstaged: 1, untracked: 0, conflicts: 0),
            changes: [
                GitFileChange(path: "notes.txt", status: .modified, isStaged: false)
            ]
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
        Array(requestedWorktreeIDsStorage).sorted()
    }

    func resetRequestedWorktreeIDs() {
        requestedWorktreeIDsStorage = []
    }
}
