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
    var diffTask: Task<DiffSnapshot, Never>?
    var diffRequestID = UUID()
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
    var diffContextLinesByPath: [String: Int] = [:]
    
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
    let projectFolder: URL?
    let fileWatchServiceFactory: (URL) -> FileWatchService
    let metadataWatcherFactory: (URL) -> any GitRepositoryMetadataWatcher
    var fileWatchService: FileWatchService?
    var metadataWatcher: (any GitRepositoryMetadataWatcher)?
    let refreshDebounceNanoseconds: UInt64

    // MARK: - Background Tasks

    var refreshTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var prPollTask: Task<Void, Never>?
    var refreshDebounceTask: Task<Void, Never>?
    
    /// Guard against concurrent refreshes to prevent overlapping UI updates.
    var isRefreshing = false
    var pendingMetadataInvalidation = false
    var lastObservedMetadataSnapshot: GitRepositoryMetadataSnapshot?

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
