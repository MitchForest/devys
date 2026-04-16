// WorktreeInfoStore.swift
// Devys - Worktree info aggregation for sidebar.

import AppFeatures
import Foundation
import Observation
import Workspace
import Git
import OSLog

@MainActor
@Observable
final class WorktreeInfoStore {
    struct Configuration {
        let selectedRefreshInterval: TimeInterval
        let backgroundRefreshInterval: TimeInterval
        let deferredHydrationDelay: TimeInterval
        let refreshDedupInterval: TimeInterval
        let prRefreshInterval: TimeInterval

        static let `default` = Configuration(
            selectedRefreshInterval: 5,
            backgroundRefreshInterval: 60,
            deferredHydrationDelay: 1,
            refreshDedupInterval: 1.5,
            prRefreshInterval: 60
        )
    }

    struct UpdateResult {
        let immediateRefreshWorktreeIds: [Worktree.ID]
    }

    enum RefreshReason: String {
        case initialSelection
        case fileChange
        case branchChange
        case manual
        case selectedPeriodic
        case backgroundPeriodic
        case deferredHydration
    }

    private static let logger = Logger(subsystem: "com.devys.mac-client", category: "WorktreeInfoStore")

    private let infoProvider: WorktreeInfoProvider
    private let infoWatcher: WorktreeInfoWatcher
    private let statusProvider: WorktreeStatusProvider
    private let configuration: Configuration
    private var watchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskToken: UUID?
    private var selectedPeriodicTask: Task<Void, Never>?
    private var backgroundPeriodicTask: Task<Void, Never>?
    private var deferredHydrationTask: Task<Void, Never>?
    private var worktreesById: [Worktree.ID: Worktree] = [:]
    private var repositoryRootURL: URL?
    private var lastRefreshById: [Worktree.ID: Date] = [:]
    private var lastPullRequestRefresh: Date?
    private var pendingHydrationWorktreeIds: [Worktree.ID] = []
    private var backgroundRefreshCursor = 0
    private(set) var selectedWorktreeId: Worktree.ID?
    private var isActiveRepository = true

    var entriesById: [Worktree.ID: WorktreeInfoEntry] = [:]
    var isLoading = false
    var isPRAvailable: Bool?

    init(
        infoProvider: WorktreeInfoProvider = DefaultWorktreeInfoProvider(),
        infoWatcher: WorktreeInfoWatcher = DefaultWorktreeInfoWatcher(),
        statusProvider: WorktreeStatusProvider = DefaultWorktreeStatusProvider(),
        configuration: Configuration = .default
    ) {
        self.infoProvider = infoProvider
        self.infoWatcher = infoWatcher
        self.statusProvider = statusProvider
        self.configuration = configuration
        startWatching()
    }

    deinit {
        MainActor.assumeIsolated {
            stopWatching()
        }
    }
}

@MainActor
extension WorktreeInfoStore {
    func update(
        worktrees: [Worktree],
        repositoryRootURL: URL?,
        isActiveRepository: Bool = true
    ) -> UpdateResult {
        let previousRepositoryRootURL = self.repositoryRootURL
        let nextWorktreesById = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.id, $0) })
        let repositoryChanged = previousRepositoryRootURL != repositoryRootURL

        self.repositoryRootURL = repositoryRootURL
        self.isActiveRepository = isActiveRepository
        worktreesById = nextWorktreesById
        entriesById = entriesById.filter { worktreesById[$0.key] != nil }
        lastRefreshById = lastRefreshById.filter { worktreesById[$0.key] != nil }
        pendingHydrationWorktreeIds.removeAll { worktreesById[$0] == nil }
        if backgroundRefreshCursor >= worktrees.count {
            backgroundRefreshCursor = 0
        }

        if repositoryChanged {
            entriesById = [:]
            lastRefreshById = [:]
            lastPullRequestRefresh = nil
            isPRAvailable = nil
            pendingHydrationWorktreeIds = []
            backgroundRefreshCursor = 0
        }

        infoWatcher.handle(.setWorktrees(worktrees))
        infoWatcher.handle(.setPullRequestTrackingEnabled(isActiveRepository && repositoryRootURL != nil))
        updatePeriodicRefresh(isActive: isActiveRepository && !worktrees.isEmpty)

        guard isActiveRepository else {
            pendingHydrationWorktreeIds = []
            return UpdateResult(
                immediateRefreshWorktreeIds: []
            )
        }

        let missingWorktreeIds = worktrees.compactMap { worktree in
            entriesById[worktree.id] == nil ? worktree.id : nil
        }
        let immediateRefreshWorktreeIds: [Worktree.ID]
        if let selectedWorktreeId,
           missingWorktreeIds.contains(selectedWorktreeId) {
            immediateRefreshWorktreeIds = [selectedWorktreeId]
        } else {
            immediateRefreshWorktreeIds = []
        }
        let deferredHydrationWorktreeIds = missingWorktreeIds.filter { id in
            !immediateRefreshWorktreeIds.contains(id)
        }
        enqueueDeferredHydration(worktreeIds: deferredHydrationWorktreeIds)
        return UpdateResult(
            immediateRefreshWorktreeIds: immediateRefreshWorktreeIds
        )
    }

    func setSelectedWorktreeId(_ worktreeId: Worktree.ID?) {
        selectedWorktreeId = worktreeId
        infoWatcher.handle(.setSelectedWorktreeId(worktreeId))
        guard isActiveRepository else { return }
        if let worktreeId,
           entriesById[worktreeId] == nil {
            refresh(worktreeIds: [worktreeId], reason: .initialSelection)
        }
    }

    func refreshAll() {
        refreshTask?.cancel()
        let worktrees = Array(worktreesById.values)
        guard !worktrees.isEmpty else {
            entriesById = [:]
            return
        }
        let taskToken = UUID()
        refreshTaskToken = taskToken
        refreshTask = Task { [weak self] in
            await self?.refresh(worktrees: worktrees, reason: .manual, taskToken: taskToken)
        }
    }

    func refresh(worktreeIds: [Worktree.ID], reason: RefreshReason = .manual) {
        let now = Date()
        let shouldDedup = shouldDedupRefresh(reason: reason)
        let filteredIds = worktreeIds.filter { id in
            guard shouldDedup else { return true }
            guard let last = lastRefreshById[id] else { return true }
            return now.timeIntervalSince(last) >= configuration.refreshDedupInterval
        }
        let worktrees = filteredIds.compactMap { worktreesById[$0] }
        guard !worktrees.isEmpty else { return }

        // If a refresh is already in flight, let it complete rather than
        // cancelling and restarting (which wastes the in-flight git work).
        // File-change and periodic reasons are deferrable; manual/initial are not.
        if refreshTask != nil {
            switch reason {
            case .fileChange, .selectedPeriodic, .backgroundPeriodic, .deferredHydration:
                return
            case .manual, .initialSelection, .branchChange:
                refreshTask?.cancel()
            }
        }

        let taskToken = UUID()
        refreshTaskToken = taskToken
        refreshTask = Task { [weak self] in
            await self?.refresh(worktrees: worktrees, reason: reason, taskToken: taskToken)
        }
    }

    func enqueueDeferredHydration(worktreeIds: [Worktree.ID]) {
        guard !worktreeIds.isEmpty else { return }
        for worktreeId in worktreeIds where !pendingHydrationWorktreeIds.contains(worktreeId) {
            pendingHydrationWorktreeIds.append(worktreeId)
        }
        scheduleDeferredHydrationIfNeeded()
    }

    private func shouldDedupRefresh(reason: RefreshReason) -> Bool {
        switch reason {
        case .initialSelection, .fileChange, .branchChange, .manual:
            false
        case .selectedPeriodic, .backgroundPeriodic, .deferredHydration:
            true
        }
    }
}

@MainActor
extension WorktreeInfoStore {
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
        refreshTaskToken = nil
        selectedPeriodicTask?.cancel()
        selectedPeriodicTask = nil
        backgroundPeriodicTask?.cancel()
        backgroundPeriodicTask = nil
        deferredHydrationTask?.cancel()
        deferredHydrationTask = nil
        infoWatcher.handle(.stop)
    }

    private func handle(_ event: WorktreeInfoEvent) async {
        guard isActiveRepository else { return }
        switch event {
        case .branchChanged(let worktreeId):
            refresh(worktreeIds: [worktreeId], reason: .branchChange)
        case .filesChanged(let worktreeId):
            guard shouldRefreshMetadata(for: worktreeId) else { return }
            refresh(worktreeIds: [worktreeId], reason: .fileChange)
        case .repositoryPullRequestRefresh:
            await refreshPullRequests()
        }
    }

    private func shouldRefreshMetadata(for worktreeId: Worktree.ID) -> Bool {
        guard let selectedWorktreeId else { return true }
        return selectedWorktreeId == worktreeId
    }
}

@MainActor
extension WorktreeInfoStore {
    private func refresh(
        worktrees: [Worktree],
        reason: RefreshReason,
        taskToken: UUID
    ) async {
        guard !worktrees.isEmpty else { return }
        isLoading = true
        defer {
            isLoading = false
            if refreshTaskToken == taskToken {
                refreshTask = nil
                refreshTaskToken = nil
            }
        }
        let now = Date()
        for worktree in worktrees {
            lastRefreshById[worktree.id] = now
        }
        let start = Date()

        let provider = infoProvider
        let statusProvider = statusProvider
        let existingPRs = entriesById.compactMapValues { $0.pullRequest }
        let results = await withTaskGroup(of: (Worktree.ID, WorktreeInfoEntry).self) { group in
            for worktree in worktrees {
                group.addTask {
                    let branchName = await provider.branchName(for: worktree.workingDirectory)
                    let repositoryInfo = await provider.repositoryInfo(for: worktree.workingDirectory)
                    let lineChanges = await provider.lineChanges(for: worktree.workingDirectory)
                    let statusSummary = await statusProvider.statusSummary(for: worktree.workingDirectory)
                    let existingPR = existingPRs[worktree.id]
                    return (
                        worktree.id,
                        WorktreeInfoEntry(
                            branchName: branchName,
                            repositoryInfo: repositoryInfo,
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
        guard !Task.isCancelled else { return }

        var updated = entriesById
        for (id, entry) in results {
            updated[id] = entry
        }
        entriesById = updated

        logRefresh(reason: reason, worktreeCount: worktrees.count, startedAt: start)
    }

    private func refreshPullRequests() async {
        guard let repositoryRootURL else { return }
        let now = Date()
        if let last = lastPullRequestRefresh, now.timeIntervalSince(last) < configuration.prRefreshInterval {
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
}

@MainActor
extension WorktreeInfoStore {
    private func updatePeriodicRefresh(isActive: Bool) {
        if !isActive {
            selectedPeriodicTask?.cancel()
            selectedPeriodicTask = nil
            backgroundPeriodicTask?.cancel()
            backgroundPeriodicTask = nil
            deferredHydrationTask?.cancel()
            deferredHydrationTask = nil
            return
        }

        if selectedPeriodicTask == nil {
            selectedPeriodicTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(configuration.selectedRefreshInterval * 1_000_000_000))
                    if Task.isCancelled { break }
                    await MainActor.run {
                        guard let selectedWorktreeId = self.selectedWorktreeId else { return }
                        self.refresh(worktreeIds: [selectedWorktreeId], reason: .selectedPeriodic)
                    }
                }
            }
        }

        guard backgroundPeriodicTask == nil else {
            scheduleDeferredHydrationIfNeeded()
            return
        }
        backgroundPeriodicTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(configuration.backgroundRefreshInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await MainActor.run {
                    guard let backgroundWorktreeId = self.nextBackgroundRefreshWorktreeId() else { return }
                    self.refresh(worktreeIds: [backgroundWorktreeId], reason: .backgroundPeriodic)
                }
            }
        }
        scheduleDeferredHydrationIfNeeded()
    }

    private func scheduleDeferredHydrationIfNeeded() {
        guard deferredHydrationTask == nil,
              !pendingHydrationWorktreeIds.isEmpty else {
            return
        }

        deferredHydrationTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(configuration.deferredHydrationDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.deferredHydrationTask = nil
                guard !self.pendingHydrationWorktreeIds.isEmpty else { return }
                let nextWorktreeId = self.pendingHydrationWorktreeIds.removeFirst()
                self.refresh(worktreeIds: [nextWorktreeId], reason: .deferredHydration)
                self.scheduleDeferredHydrationIfNeeded()
            }
        }
    }

    private func nextBackgroundRefreshWorktreeId() -> Worktree.ID? {
        let candidateIds = worktreesById.keys.sorted().filter { worktreeId in
            worktreeId != selectedWorktreeId && entriesById[worktreeId] != nil
        }
        guard !candidateIds.isEmpty else { return nil }
        if backgroundRefreshCursor >= candidateIds.count {
            backgroundRefreshCursor = 0
        }
        let worktreeId = candidateIds[backgroundRefreshCursor]
        backgroundRefreshCursor = (backgroundRefreshCursor + 1) % candidateIds.count
        return worktreeId
    }

    private func logRefresh(
        reason: RefreshReason,
        worktreeCount: Int,
        startedAt: Date
    ) {
        let durationMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
        let message =
            "refresh reason=\(reason.rawValue) " +
            "worktrees=\(worktreeCount) " +
            "duration_ms=\(durationMilliseconds)"
        Self.logger.debug("\(message, privacy: .public)")
    }
}
