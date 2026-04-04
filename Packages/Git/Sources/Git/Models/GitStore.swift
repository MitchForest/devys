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
    private(set) var repoInfo: GitRepositoryInfo?
    
    /// All file changes (staged and unstaged).
    private(set) var changes: [GitFileChange] = []
    
    /// Whether a refresh is in progress.
    var isLoading: Bool = false
    
    /// Error message if last operation failed.
    var errorMessage: String?
    
    // MARK: - Selection State
    
    /// Currently selected file path.
    private(set) var selectedFilePath: String?
    
    /// Diff snapshot for the selected file.
    private(set) var selectedDiff: DiffSnapshot?
    
    /// Whether viewing staged or unstaged diff.
    private(set) var isViewingStaged: Bool = false

    /// Current diff load task (for cancellation).
    private var diffTask: Task<DiffSnapshot, Never>?
    private var diffRequestID = UUID()
    
    // MARK: - View Settings
    
    /// Diff display mode (unified or split).
    var diffViewMode: DiffViewMode = .unified
    
    /// Whether to ignore whitespace in diffs.
    private(set) var ignoreWhitespace: Bool = false
    
    /// Currently focused hunk index for keyboard navigation.
    private(set) var focusedHunkIndex: Int?
    
    /// Context lines per file path.
    private var diffContextLinesByPath: [String: Int] = [:]
    
    // MARK: - History State
    
    /// Whether showing commit history.
    var isShowingHistory: Bool = false
    
    /// Commit history.
    private(set) var commits: [GitCommit] = []
    
    // MARK: - PR State
    
    /// Whether GitHub CLI is available.
    private(set) var isPRAvailable: Bool = false
    
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
        changes.filter { !$0.isStaged }
    }
    
    // MARK: - Services
    
    let gitService: any GitService
    private let projectFolder: URL?
    private let fileWatchServiceFactory: (URL) -> FileWatchService
    private var fileWatchService: FileWatchService?
    
    // MARK: - Background Tasks
    
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var prPollTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    
    /// Guard against concurrent refreshes to prevent overlapping UI updates.
    private var isRefreshing = false

    // MARK: - Initialization

    public convenience init(projectFolder: URL?) {
        self.init(
            projectFolder: projectFolder,
            gitService: DefaultGitService(repositoryURL: projectFolder)
        ) { RecursiveFileWatchService(rootURL: $0) }
    }

    init(
        projectFolder: URL?,
        gitService: any GitService,
        fileWatchServiceFactory: @escaping (URL) -> FileWatchService
    ) {
        self.projectFolder = projectFolder
        self.gitService = gitService
        self.fileWatchServiceFactory = fileWatchServiceFactory
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
    }

    // MARK: - File Watching

    /// Start filesystem watching for repository changes.
    public func startWatching() {
        guard let projectFolder else { return }
        if fileWatchService == nil {
            fileWatchService = fileWatchServiceFactory(projectFolder)
        }
        fileWatchService?.onFileChange = { [weak self] _, url in
            // Ignore changes inside .git/ directory — git CLI operations
            // (status, diff, etc.) modify .git/index and other internal files,
            // which would otherwise create a refresh → file-change → refresh loop.
            let pathString = url.path
            guard !pathString.contains("/.git/") && !pathString.hasSuffix("/.git") else {
                return
            }
            Task { @MainActor in
                self?.scheduleRefresh()
            }
        }
        fileWatchService?.startWatching()
    }

    /// Stop filesystem watching for repository changes.
    public func stopWatching() {
        fileWatchService?.stopWatching()
        fileWatchService = nil
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
    }

    private func scheduleRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            await self?.refresh()
        }
    }
    
    // MARK: - Refresh
    
    /// Refresh git status.
    public func refresh() async {
        guard gitService.hasRepository else {
            errorMessage = "No project folder configured"
            return
        }
        
        // Prevent concurrent refreshes — overlapping calls cause rapid
        // isLoading toggling (blinking) and duplicate diff reads.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        
        // Cancel any pending debounced refresh so it doesn't fire after
        // this manual/explicit refresh completes.
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        
        isLoading = true
        errorMessage = nil
        
        do {
            let status = try await gitService.status()
            let info = try await gitService.repositoryInfo()
            
            changes = status
            repoInfo = info
            
            // Refresh diff for selected file if any
            if let path = selectedFilePath {
                await refreshDiff(for: path, staged: isViewingStaged)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Check if PR functionality is available.
    public func checkPRAvailability() async {
        isPRAvailable = await gitService.isPRAvailable()
    }

    /// Stop background polling.
    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
    
    // MARK: - File Selection
    
    /// Select a file and load its diff.
    func selectFile(_ path: String, isStaged: Bool) async {
        selectedFilePath = path
        isViewingStaged = isStaged
        isShowingHistory = false
        isShowingPRDetail = false
        focusedHunkIndex = nil
        await refreshDiff(for: path, staged: isStaged)
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
            errorMessage = "Failed to load diff: \(error.localizedDescription)"
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
        guard gitService.hasRepository else { return }
        
        do {
            try await gitService.stage(path)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Unstage a file.
    func unstage(_ path: String) async {
        guard gitService.hasRepository else { return }
        
        do {
            try await gitService.unstage(path)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Stage all changes.
    func stageAll() async {
        guard gitService.hasRepository else { return }
        
        do {
            try await gitService.stageAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    /// Unstage all changes.
    func unstageAll() async {
        guard gitService.hasRepository else { return }
        
        do {
            try await gitService.unstageAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Accept/Reject Hunks
    
    /// Accept a hunk (keep the changes).
    /// - Unstaged hunk: Stage it (include in next commit)
    /// - Staged hunk: No-op (already accepted)
    func acceptHunk(_ hunk: DiffHunk) async {
        guard gitService.hasRepository, let path = selectedFilePath else { return }
        
        // If already staged, nothing to do
        if isViewingStaged { return }
        
        do {
            try await gitService.stageHunk(hunk, for: path)
            await refresh()
        } catch {
            errorMessage = "Failed to accept hunk: \(error.localizedDescription)"
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
        guard gitService.hasRepository, let path = selectedFilePath else { return }
        
        do {
            if isViewingStaged {
                // First unstage, then discard
                try await gitService.unstageHunk(hunk, for: path)
            }
            // Discard the hunk by applying the reverse patch
            try await gitService.discardHunk(hunk, for: path)
            await refresh()
        } catch {
            errorMessage = "Failed to reject hunk: \(error.localizedDescription)"
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
        guard gitService.hasRepository else { return }
        
        do {
            if change.status == .untracked {
                try await gitService.discardUntracked(change.path)
            } else {
                try await gitService.discard(change.path)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Commit
    
    /// Commit staged changes.
    func commit(message: String, push: Bool = false) async throws {
        guard gitService.hasRepository else {
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
            errorMessage = error.localizedDescription
            isLoading = false
            throw error
        }
        
        isLoading = false
    }
    
    // MARK: - Remote Operations
    
    /// Push to remote.
    func push() async {
        guard gitService.hasRepository else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await gitService.push()
            await refresh()
        } catch {
            errorMessage = formatPushError(error)
        }
        
        isLoading = false
    }
    
    /// Pull from remote.
    func pull() async {
        guard gitService.hasRepository else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await gitService.pull()
            await refresh()
        } catch {
            errorMessage = formatPullError(error)
        }
        
        isLoading = false
    }
    
    private func formatPushError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("non-fast-forward") || message.contains("fetch first") || message.contains("rejected") {
            return "Push rejected: remote has new commits. Pull first and resolve any conflicts."
        }
        return "Push failed: \(error.localizedDescription)"
    }
    
    private func formatPullError(_ error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("conflict") || message.contains("merge") || message.contains("unmerged") {
            return "Pull resulted in merge conflicts. Resolve conflicts and commit."
        }
        return "Pull failed: \(error.localizedDescription)"
    }
    
    // MARK: - Branch Operations
    
    /// Load all branches.
    func loadBranches() async -> [GitBranch] {
        guard gitService.hasRepository else { return [] }
        
        do {
            return try await gitService.branches()
        } catch {
            errorMessage = "Failed to load branches: \(error.localizedDescription)"
            return []
        }
    }
    
    /// Checkout a branch.
    func checkout(branch: String) async {
        guard gitService.hasRepository else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await gitService.checkout(branch: branch)
            await refresh()
        } catch {
            errorMessage = "Checkout failed: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Create a new branch.
    func createBranch(name: String) async {
        guard gitService.hasRepository else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await gitService.createBranch(name: name)
            await refresh()
        } catch {
            errorMessage = "Failed to create branch: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Delete a branch.
    func deleteBranch(name: String, force: Bool = false) async {
        guard gitService.hasRepository else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await gitService.deleteBranch(name: name, force: force)
            await refresh()
        } catch {
            errorMessage = "Failed to delete branch: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Commit History
    
    /// Load commit history.
    func loadCommitHistory(count: Int = 50) async {
        guard gitService.hasRepository else { return }
        
        isShowingHistory = true
        isShowingPRDetail = false
        
        do {
            commits = try await gitService.log(count: count)
        } catch {
            errorMessage = "Failed to load commits: \(error.localizedDescription)"
            commits = []
        }
    }
    
    /// Show diff for a commit.
    func showCommit(_ commit: GitCommit) async -> String? {
        guard gitService.hasRepository else { return nil }
        
        do {
            return try await gitService.show(commit: commit.hash)
        } catch {
            errorMessage = "Failed to load commit diff: \(error.localizedDescription)"
            return nil
        }
    }
    
}
