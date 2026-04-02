// WorktreeInfoStore.swift
// Devys - Worktree info aggregation for sidebar.

import Foundation
import Observation
import Workspace
import Git

@MainActor
@Observable
final class WorktreeInfoStore {
    private let infoProvider: WorktreeInfoProvider
    private let infoWatcher: WorktreeInfoWatcher
    private let statusProvider: WorktreeStatusProvider
    private var watchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var periodicTask: Task<Void, Never>?
    private var worktreesById: [Worktree.ID: Worktree] = [:]
    private var repositoryRootURL: URL?
    private var lastRefreshById: [Worktree.ID: Date] = [:]
    private var lastPullRequestRefresh: Date?
    private let refreshInterval: TimeInterval = 1.5
    private let prRefreshInterval: TimeInterval = 60

    var entriesById: [Worktree.ID: WorktreeInfoEntry] = [:]
    var isLoading = false
    var isPRAvailable: Bool?

    init(
        infoProvider: WorktreeInfoProvider = DefaultWorktreeInfoProvider(),
        infoWatcher: WorktreeInfoWatcher = DefaultWorktreeInfoWatcher(),
        statusProvider: WorktreeStatusProvider = DefaultWorktreeStatusProvider()
    ) {
        self.infoProvider = infoProvider
        self.infoWatcher = infoWatcher
        self.statusProvider = statusProvider
        startWatching()
    }

    deinit {
        MainActor.assumeIsolated {
            stopWatching()
        }
    }

    func update(worktrees: [Worktree], repositoryRootURL: URL?) {
        self.repositoryRootURL = repositoryRootURL
        worktreesById = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
        entriesById = entriesById.filter { worktreesById[$0.key] != nil }
        infoWatcher.handle(.setWorktrees(worktrees))
        if repositoryRootURL != nil {
            infoWatcher.handle(.setPullRequestTrackingEnabled(true))
        }
        updatePeriodicRefresh(isActive: !worktrees.isEmpty)
    }

    func setSelectedWorktreeId(_ worktreeId: Worktree.ID?) {
        infoWatcher.handle(.setSelectedWorktreeId(worktreeId))
    }

    func refreshAll() {
        refreshTask?.cancel()
        let worktrees = Array(worktreesById.values)
        guard !worktrees.isEmpty else {
            entriesById = [:]
            return
        }
        refreshTask = Task { [weak self] in
            await self?.refresh(worktrees: worktrees)
        }
    }

    func refresh(worktreeIds: [Worktree.ID]) {
        let now = Date()
        let filteredIds = worktreeIds.filter { id in
            guard let last = lastRefreshById[id] else { return true }
            return now.timeIntervalSince(last) >= refreshInterval
        }
        let worktrees = filteredIds.compactMap { worktreesById[$0] }
        guard !worktrees.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.refresh(worktrees: worktrees)
        }
    }

    private func startWatching() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in infoWatcher.eventStream() {
                await handle(event)
            }
        }
    }

    private func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        periodicTask?.cancel()
        periodicTask = nil
        infoWatcher.handle(.stop)
    }

    private func handle(_ event: WorktreeInfoEvent) async {
        switch event {
        case .branchChanged(let worktreeId):
            refresh(worktreeIds: [worktreeId])
        case .filesChanged(let worktreeId):
            refresh(worktreeIds: [worktreeId])
        case .repositoryPullRequestRefresh:
            await refreshPullRequests()
        }
    }

    private func refresh(worktrees: [Worktree]) async {
        guard !worktrees.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let now = Date()
        for worktree in worktrees {
            lastRefreshById[worktree.id] = now
        }

        let provider = infoProvider
        let statusProvider = statusProvider
        let existingPRs = entriesById.compactMapValues { $0.pullRequest }
        let results = await withTaskGroup(of: (Worktree.ID, WorktreeInfoEntry).self) { group in
            for worktree in worktrees {
                group.addTask {
                    let branchName = await provider.branchName(for: worktree.workingDirectory)
                    let lineChanges = await provider.lineChanges(for: worktree.workingDirectory)
                    let statusSummary = await statusProvider.statusSummary(for: worktree.workingDirectory)
                    let existingPR = existingPRs[worktree.id]
                    return (
                        worktree.id,
                        WorktreeInfoEntry(
                            branchName: branchName,
                            lineChanges: lineChanges,
                            statusSummary: statusSummary,
                            pullRequest: existingPR
                        )
                    )
                }
            }

            var collected: [(Worktree.ID, WorktreeInfoEntry)] = []
            for await entry in group {
                collected.append(entry)
            }
            return collected
        }

        var updated = entriesById
        for (id, entry) in results {
            updated[id] = entry
        }
        entriesById = updated
    }

    private func refreshPullRequests() async {
        guard let repositoryRootURL else { return }
        let now = Date()
        if let last = lastPullRequestRefresh, now.timeIntervalSince(last) < prRefreshInterval {
            return
        }
        lastPullRequestRefresh = now
        let available = await infoProvider.isPullRequestAvailable(for: repositoryRootURL)
        isPRAvailable = available
        guard available else {
            var updated = entriesById
            for (worktreeId, entry) in entriesById where entry.pullRequest != nil {
                var nextEntry = entry
                nextEntry.pullRequest = nil
                updated[worktreeId] = nextEntry
            }
            entriesById = updated
            return
        }

        let provider = infoProvider
        let branches = worktreesById.values.map { worktree -> String in
            entriesById[worktree.id]?.branchName ?? worktree.name
        }

        let prs = await provider.pullRequests(for: repositoryRootURL, branches: branches)

        var updated = entriesById
        for (worktreeId, entry) in entriesById {
            let branch = entry.branchName ?? worktreesById[worktreeId]?.name
            var nextEntry = entry
            if let branch {
                nextEntry.pullRequest = prs[branch]
            } else {
                nextEntry.pullRequest = nil
            }
            updated[worktreeId] = nextEntry
        }
        entriesById = updated
    }

    private func updatePeriodicRefresh(isActive: Bool) {
        if !isActive {
            periodicTask?.cancel()
            periodicTask = nil
            return
        }
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    self.refreshAll()
                }
            }
        }
    }
}
