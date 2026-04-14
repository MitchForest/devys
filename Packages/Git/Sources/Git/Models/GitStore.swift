// GitStore.swift
// Observable state container for git UI.

import Foundation
import Observation
import Workspace

/// Observable state container for git UI.
/// One instance per workspace.
@MainActor
@Observable
public final class GitStore {
    
    // MARK: - Repository State
    
    /// Current repository info (branch, ahead/behind).
    var repoInfo: GitRepositoryInfo?

    /// Whether the current project folder is backed by Git.
    public internal(set) var isRepositoryAvailable: Bool = false
    
    /// All file changes (staged and unstaged).
    var changes: [GitFileChange] = []

    /// Whether there are any uncommitted changes.
    public var hasChanges: Bool { !changes.isEmpty }
    
    /// Whether a refresh is in progress.
    var isLoading: Bool = false
    
    /// Error message if last operation failed.
    public internal(set) var errorMessage: String?
    
    // MARK: - Selection State
    
    /// Currently selected file path.
    var selectedFilePath: String?
    
    /// Diff snapshot for the selected file.
    var selectedDiff: DiffSnapshot?
    
    /// Whether viewing staged or unstaged diff.
    var isViewingStaged: Bool = false

    /// Current diff load task (for cancellation).
    private var diffTask: Task<DiffSnapshot, Never>?
    private var diffRequestID = UUID()
    @ObservationIgnored public var onChangesDidUpdate: (([GitFileChange]) -> Void)?
    @ObservationIgnored public var onRepositoryAvailabilityDidUpdate: ((Bool) -> Void)?
    
    // MARK: - View Settings
    
    /// Diff display mode (unified or split).
    var diffViewMode: DiffViewMode = .unified
    
    /// Whether to ignore whitespace in diffs.
    var ignoreWhitespace: Bool = false
    
    /// Currently focused hunk index for keyboard navigation.
    var focusedHunkIndex: Int?
    
    /// Context lines per file path.
    private var diffContextLinesByPath: [String: Int] = [:]
    
    // MARK: - History State
    
    /// Whether showing commit history.
    var isShowingHistory: Bool = false
    
    /// Commit history.
    var commits: [GitCommit] = []
    
    // MARK: - PR State
    
    /// Whether GitHub CLI is available.
    var isPRAvailable: Bool = false
    
    /// Selected PR for detail view.
    var selectedPR: PullRequest?
    
    /// Files in the selected PR.
    var prFiles: [PRFile] = []
    
    /// Selected PR file for diff.
    var selectedPRFile: PRFile?
    
    /// Parsed diff for selected PR file.
    var selectedPRFileDiff: ParsedDiff?
    
    /// Whether showing PR detail view.
    var isShowingPRDetail: Bool = false
    
    // MARK: - Derived Properties
    
    /// Staged changes.
    var stagedChanges: [GitFileChange] {
        changes.filter(\.isStaged)
    }
    
    /// Unstaged changes.
    var unstagedChanges: [GitFileChange] {
        changes.filter {
            !$0.isStaged &&
            $0.status != .untracked &&
            $0.status != .ignored
        }
    }

    /// Untracked changes.
    var untrackedChanges: [GitFileChange] {
        changes.filter { !$0.isStaged && $0.status == .untracked }
    }

    /// Ignored files.
    var ignoredChanges: [GitFileChange] {
        changes.filter { !$0.isStaged && $0.status == .ignored }
    }

    /// All visible changes returned by the default status path.
    public var allChanges: [GitFileChange] {
        changes
    }
    
    // MARK: - Services
    
    let gitService: any GitService
    private let projectFolder: URL?
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    private let metadataWatcherFactory: (URL) -> any GitRepositoryMetadataWatcher
    private var fileWatchService: FileWatchService?
    private var metadataWatcher: (any GitRepositoryMetadataWatcher)?
    private let refreshDebounceNanoseconds: UInt64

    // MARK: - Background Tasks

    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var prPollTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    
    /// Guard against concurrent refreshes to prevent overlapping UI updates.
    private var isRefreshing = false
    private var pendingMetadataInvalidation = false
    private var lastObservedMetadataSnapshot: GitRepositoryMetadataSnapshot?

    // MARK: - Initialization

    public convenience init(projectFolder: URL?) {
        self.init(
            projectFolder: projectFolder,
            gitService: DefaultGitService(repositoryURL: projectFolder),
            fileWatchServiceFactory: { RecursiveFileWatchService(rootURL: $0) },
            metadataWatcherFactory: { DefaultGitRepositoryMetadataWatcher(repositoryURL: $0) }
        )
    }

    init(
        projectFolder: URL?,
        gitService: any GitService,
        fileWatchServiceFactory: @escaping (URL) -> FileWatchService,
        metadataWatcherFactory: @escaping (URL) -> any GitRepositoryMetadataWatcher = {
            DefaultGitRepositoryMetadataWatcher(repositoryURL: $0)
        },
        refreshDebounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.projectFolder = projectFolder
        self.gitService = gitService
        self.fileWatchServiceFactory = fileWatchServiceFactory
        self.metadataWatcherFactory = metadataWatcherFactory
        self.refreshDebounceNanoseconds = refreshDebounceNanoseconds
    }

}

extension GitStore {
    /// Clean up resources.
    public func cleanup() {
        stopWatching()
        pollTask?.cancel()
        pollTask = nil
        prPollTask?.cancel()
        prPollTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        diffTask?.cancel()
        diffTask = nil
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        stopMetadataWatching()
    }

    // MARK: - File Watching

    /// Start filesystem watching for repository changes.
    public func startWatching() {
        guard let projectFolder else { return }
        if fileWatchService == nil {
            fileWatchService = fileWatchServiceFactory(projectFolder)
        }
        fileWatchService?.onFileChange = { [weak self] changeType, url in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isRepositoryRootGitEntry(url) {
                    if self.shouldReconcileRepositoryAvailability(
                        for: url,
                        changeType: changeType
                    ) {
                        let isRepositoryAvailable = await self.reconcileRepositoryAvailability(
                            forceMetadataRestart: true
                        )
                        if isRepositoryAvailable {
                            self.scheduleRefresh()
                        }
                    }
                    return
                }

                // Ignore changes inside .git/ directory — git CLI operations
                // (status, diff, etc.) modify .git/index and other internal files,
                // which would otherwise create a refresh → file-change → refresh loop.
                let pathString = url.path
                guard !pathString.contains("/.git/"),
                      !pathString.hasSuffix("/.git") else {
                    return
                }
                self.scheduleRefresh()
            }
        }
        fileWatchService?.startWatching()
        if isRepositoryAvailable {
            configureMetadataWatcherIfNeeded()
        }
    }

    /// Stop filesystem watching for repository changes.
    public func stopWatching() {
        fileWatchService?.stopWatching()
        fileWatchService = nil
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        stopMetadataWatching()
    }

    private func scheduleRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.refreshDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self.refresh()
        }
    }
    
    // MARK: - Refresh
    
    /// Refresh git status.
    public func refresh() async {
        guard projectFolder != nil else {
            applyRepositoryAvailability(false)
            return
        }
        
        // Prevent overlapping refresh work, but let concurrent callers wait
        // for the in-flight refresh so explicit hydrations cannot race
        // against watcher-triggered updates and observe stale state.
        while isRefreshing {
            await Task.yield()
        }

        isRefreshing = true
        defer { isRefreshing = false }
        
        // Cancel any pending debounced refresh so it doesn't fire after
        // this manual/explicit refresh completes.
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        
        isLoading = true
        errorMessage = nil
        pendingMetadataInvalidation = false
        
        do {
            guard await ensureRepositoryAvailability() else {
                isLoading = false
                return
            }

            let status = try await gitService.status()
            let info = try await gitService.repositoryInfo()
            
            changes = status
            onChangesDidUpdate?(status)
            repoInfo = info
            syncObservedMetadataSnapshot()
            
            await refreshSelectionAfterStatusUpdate(status)
        } catch {
            if isNotRepositoryError(error) {
                _ = await reconcileRepositoryAvailability(forceMetadataRestart: true)
            } else {
                setError(error)
            }
        }

        let shouldScheduleFollowUpRefresh = pendingMetadataInvalidation && metadataSnapshotHasChanged()
        pendingMetadataInvalidation = false
        isLoading = false

        if shouldScheduleFollowUpRefresh {
            scheduleRefresh()
        }
    }

    private func refreshSelectionAfterStatusUpdate(_ status: [GitFileChange]) async {
        guard let selectedFilePath else { return }

        let matchingChanges = status.filter { $0.path == selectedFilePath }
        guard !matchingChanges.isEmpty else {
            clearSelectedFileState()
            return
        }

        if !matchingChanges.contains(where: { $0.isStaged == isViewingStaged }),
           let fallback = matchingChanges.first {
            isViewingStaged = fallback.isStaged
        }

        await refreshDiff(for: selectedFilePath, staged: isViewingStaged)
    }

    private func clearSelectedFileState() {
        diffTask?.cancel()
        diffTask = nil
        selectedFilePath = nil
        selectedDiff = nil
        focusedHunkIndex = nil
        isViewingStaged = false
    }

    func configureMetadataWatcherIfNeeded(forceRestart: Bool = false) {
        guard let projectFolder else { return }
        let hasResolvableGitDirectory =
            GitRepositoryReferenceResolver.resolveGitDirectory(for: projectFolder) != nil

        if forceRestart || !hasResolvableGitDirectory {
            stopMetadataWatching()
        }

        guard hasResolvableGitDirectory, metadataWatcher == nil else { return }

        let watcher = metadataWatcherFactory(projectFolder)
        watcher.onChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleMetadataInvalidation()
            }
        }
        watcher.startWatching()
        metadataWatcher = watcher
        syncObservedMetadataSnapshot()
    }

    func stopMetadataWatching() {
        metadataWatcher?.stopWatching()
        metadataWatcher = nil
        lastObservedMetadataSnapshot = nil
        pendingMetadataInvalidation = false
    }

    private func isRepositoryRootGitEntry(_ url: URL) -> Bool {
        guard let projectFolder else { return false }
        let normalizedProjectFolder = projectFolder.standardizedFileURL
        let normalizedURL = url.standardizedFileURL
        return normalizedURL.deletingLastPathComponent() == normalizedProjectFolder
            && normalizedURL.lastPathComponent == ".git"
    }

    private func shouldReconcileRepositoryAvailability(
        for url: URL,
        changeType: FileChangeType
    ) -> Bool {
        guard isRepositoryRootGitEntry(url) else { return false }

        switch changeType {
        case .created, .deleted, .renamed, .overflow:
            return true
        case .modified:
            return isRepositoryReferenceFile()
        }
    }

    private func isRepositoryReferenceFile() -> Bool {
        guard let projectFolder else { return false }
        let gitURL = projectFolder.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private func handleMetadataInvalidation() async {
        guard isRepositoryAvailable else { return }

        guard let snapshot = currentMetadataSnapshot() else {
            _ = await reconcileRepositoryAvailability(forceMetadataRestart: true)
            return
        }

        guard snapshot != lastObservedMetadataSnapshot else { return }

        if isRefreshing {
            pendingMetadataInvalidation = true
            return
        }

        scheduleRefresh()
    }

    private func currentMetadataSnapshot() -> GitRepositoryMetadataSnapshot? {
        guard let projectFolder else { return nil }
        return GitRepositoryReferenceResolver.metadataSnapshot(for: projectFolder)
    }

    func syncObservedMetadataSnapshot() {
        lastObservedMetadataSnapshot = currentMetadataSnapshot()
    }

    private func metadataSnapshotHasChanged() -> Bool {
        currentMetadataSnapshot() != lastObservedMetadataSnapshot
    }

    /// Check if PR functionality is available.
    public func checkPRAvailability() async {
        guard await ensureRepositoryAvailability() else {
            isPRAvailable = false
            return
        }
        isPRAvailable = await gitService.isPRAvailable()
    }

    /// Initialize Git in the current project folder.
    public func initializeRepository() async {
        guard projectFolder != nil else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.initializeRepository()
            _ = await reconcileRepositoryAvailability(forceMetadataRestart: true)
            await refresh()
            await checkPRAvailability()
        } catch {
            setError(error, prefix: "Failed to initialize Git")
        }

        isLoading = false
    }

    /// Stop background polling.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
    
    // MARK: - File Selection
    
    /// Select a file and load its diff.
    public func selectFile(_ path: String, isStaged: Bool) async {
        selectedFilePath = path
        isViewingStaged = isStaged
        isShowingHistory = false
        isShowingPRDetail = false
        focusedHunkIndex = nil
        await refreshDiff(for: path, staged: isStaged)
    }

    public func diffText(
        for path: String,
        isStaged: Bool,
        contextLines: Int = 3,
        ignoreWhitespace: Bool = false
    ) async throws -> String {
        try await gitService.diff(
            for: path,
            staged: isStaged,
            contextLines: contextLines,
            ignoreWhitespace: ignoreWhitespace
        )
    }

    func setFocusedHunkIndex(_ index: Int?) {
        focusedHunkIndex = index
    }
    
    // MARK: - Diff
    
    private func refreshDiff(for path: String, staged: Bool) async {
        diffTask?.cancel()
        let requestID = UUID()
        diffRequestID = requestID
        do {
            let contextLines = diffContextLinesByPath[path] ?? 3
            let snapshot = try await gitService.diffSnapshot(
                for: path,
                staged: staged,
                contextLines: contextLines,
                ignoreWhitespace: ignoreWhitespace
            )
            let loadTask = Task { snapshot }
            diffTask = loadTask
            let parsed = await loadTask.value
            if diffRequestID == requestID {
                selectedDiff = parsed
            }
            diffTask = nil
        } catch {
            selectedDiff = nil
            setError(error, prefix: "Failed to load diff")
        }
    }
    
    /// Increase context lines for current file.
    func increaseContext(by amount: Int = 10) async {
        guard let path = selectedFilePath else { return }
        let current = diffContextLinesByPath[path] ?? 3
        diffContextLinesByPath[path] = current + amount
        await refreshDiff(for: path, staged: isViewingStaged)
    }
    
    /// Show all context for current file.
    func showAllContext() async {
        guard let path = selectedFilePath else { return }
        diffContextLinesByPath[path] = 9999
        await refreshDiff(for: path, staged: isViewingStaged)
    }
    
    /// Toggle ignore whitespace.
    func toggleIgnoreWhitespace() async {
        ignoreWhitespace.toggle()
        if let path = selectedFilePath {
            await refreshDiff(for: path, staged: isViewingStaged)
        }
    }
    
    // MARK: - Staging
    
    /// Stage a file.
    func stage(_ path: String) async {
        guard await ensureRepositoryAvailability() else { return }
        
        do {
            try await gitService.stage(path)
            await refresh()
        } catch {
            setError(error)
        }
    }

    /// Unstage a file.
    func unstage(_ path: String) async {
        guard await ensureRepositoryAvailability() else { return }
        
        do {
            try await gitService.unstage(path)
            await refresh()
        } catch {
            setError(error)
        }
    }
    
    /// Stage all changes.
    func stageAll() async {
        guard await ensureRepositoryAvailability() else { return }
        
        do {
            try await gitService.stageAll()
            await refresh()
        } catch {
            setError(error)
        }
    }
    
    /// Unstage all changes.
    func unstageAll() async {
        guard await ensureRepositoryAvailability() else { return }
        
        do {
            try await gitService.unstageAll()
            await refresh()
        } catch {
            setError(error)
        }
    }
    
    // MARK: - Accept/Reject Hunks
    
    /// Accept a hunk (keep the changes).
    /// - Unstaged hunk: Stage it (include in next commit)
    /// - Staged hunk: No-op (already accepted)
    func acceptHunk(_ hunk: DiffHunk) async {
        guard await ensureRepositoryAvailability(),
              let path = selectedFilePath else { return }
        
        // If already staged, nothing to do
        if isViewingStaged { return }
        
        do {
            try await gitService.stageHunk(hunk, for: path)
            await refresh()
        } catch {
            setError(error, prefix: "Failed to accept hunk")
        }
    }
    
    /// Accept hunk at index.
    func acceptHunk(at index: Int) async {
        guard let diff = selectedDiff, index >= 0, index < diff.hunks.count else { return }
        await acceptHunk(diff.hunks[index])
    }
    
    /// Reject a hunk (discard the changes entirely).
    /// - Unstaged hunk: Discard (revert to HEAD)
    /// - Staged hunk: Unstage + discard (revert to HEAD)
    func rejectHunk(_ hunk: DiffHunk) async {
        guard await ensureRepositoryAvailability(),
              let path = selectedFilePath else { return }
        
        do {
            if isViewingStaged {
                // First unstage, then discard
                try await gitService.unstageHunk(hunk, for: path)
            }
            // Discard the hunk by applying the reverse patch
            try await gitService.discardHunk(hunk, for: path)
            await refresh()
        } catch {
            setError(error, prefix: "Failed to reject hunk")
        }
    }
    
    /// Reject hunk at index.
    func rejectHunk(at index: Int) async {
        guard let diff = selectedDiff, index >= 0, index < diff.hunks.count else { return }
        await rejectHunk(diff.hunks[index])
    }

    /// Accept the currently focused hunk.
    func acceptFocusedHunk() async {
        guard let index = focusedHunkIndex else { return }
        await acceptHunk(at: index)
    }

    /// Reject the currently focused hunk.
    func rejectFocusedHunk() async {
        guard let index = focusedHunkIndex else { return }
        await rejectHunk(at: index)
    }
    
    // MARK: - Discard
    
    /// Discard changes to a file.
    func discard(_ change: GitFileChange) async {
        guard await ensureRepositoryAvailability() else { return }
        
        do {
            if change.status == .untracked {
                try await gitService.discardUntracked(change.path)
            } else {
                try await gitService.discard(change.path)
            }
            await refresh()
        } catch {
            setError(error)
        }
    }
    
    // MARK: - Commit
    
    /// Commit staged changes.
    public func commit(message: String, push: Bool = false) async throws {
        guard await ensureRepositoryAvailability() else {
            throw GitError.notRepository(projectFolder ?? URL(fileURLWithPath: "/"))
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await gitService.commit(message: message)
            
            if push {
                try await gitService.push()
            }
            
            await refresh()
        } catch {
            setError(error)
            isLoading = false
            throw error
        }
        
        isLoading = false
    }
    
}
