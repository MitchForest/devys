import Foundation
import Observation

/// Observable state for a git pane.
///
/// Manages the git client, file changes, and commit operations.
@MainActor
@Observable
public final class GitState {
    // MARK: - Properties

    /// The repository URL
    public var repositoryURL: URL?

    /// Repository information
    public var repositoryInfo: GitRepositoryInfo?

    /// Staged changes
    public var stagedChanges: [GitFileChange] = []

    /// Unstaged changes
    public var unstagedChanges: [GitFileChange] = []

    /// Commit message
    public var commitMessage: String = ""

    /// Whether a git operation is in progress
    public var isLoading: Bool = false

    /// Error message if any
    public var errorMessage: String?

    /// Selected file for diff view
    public var selectedChange: GitFileChange?

    /// Diff content for selected file
    public var selectedDiff: String?

    /// Recent commits
    public var recentCommits: [GitLogEntry] = []

    // MARK: - Computed Properties

    /// Whether there are any changes
    public var hasChanges: Bool {
        !stagedChanges.isEmpty || !unstagedChanges.isEmpty
    }

    /// Whether there are staged changes ready to commit
    public var canCommit: Bool {
        !stagedChanges.isEmpty && !commitMessage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Total number of changes
    public var totalChanges: Int {
        stagedChanges.count + unstagedChanges.count
    }

    // MARK: - Private

    private var client: GitClient?

    // MARK: - Initialization

    public init(repositoryURL: URL? = nil) {
        self.repositoryURL = repositoryURL
        if let url = repositoryURL {
            self.client = GitClient(repositoryURL: url)
        }
    }

    // MARK: - Public Methods

    /// Set the repository URL and refresh
    public func setRepository(_ url: URL) {
        repositoryURL = url
        client = GitClient(repositoryURL: url)
        Task {
            await refresh()
        }
    }

    /// Refresh the git status
    public func refresh() async {
        guard let client = client else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Get status
            let allChanges = try await client.status()
            stagedChanges = allChanges.filter { $0.isStaged }
            unstagedChanges = allChanges.filter { !$0.isStaged }

            // Get repository info
            repositoryInfo = try await client.repositoryInfo()

            // Get recent commits
            recentCommits = try await client.log(count: 5)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Stage a file
    public func stage(_ change: GitFileChange) async {
        guard let client = client else { return }

        do {
            try await client.stage(change.path)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stage all changes
    public func stageAll() async {
        guard let client = client else { return }

        do {
            try await client.stageAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unstage a file
    public func unstage(_ change: GitFileChange) async {
        guard let client = client else { return }

        do {
            try await client.unstage(change.path)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unstage all changes
    public func unstageAll() async {
        guard let client = client else { return }

        do {
            try await client.unstageAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Commit staged changes
    public func commit() async {
        guard let client = client, canCommit else { return }

        let message = commitMessage.trimmingCharacters(in: .whitespaces)

        do {
            try await client.commit(message: message)
            commitMessage = ""
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Load diff for a change
    public func loadDiff(for change: GitFileChange) async {
        guard let client = client else { return }

        selectedChange = change

        do {
            selectedDiff = try await client.diff(for: change.path, staged: change.isStaged)
        } catch {
            selectedDiff = "Error loading diff: \(error.localizedDescription)"
        }
    }

    /// Clear selected change
    public func clearSelection() {
        selectedChange = nil
        selectedDiff = nil
    }

    // MARK: - Discard

    /// Discard changes to a file
    public func discard(_ change: GitFileChange) async {
        guard let client = client else { return }

        do {
            if change.status == .untracked {
                try await client.discardUntracked(change.path)
            } else {
                try await client.discard(change.path)
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Discard all changes
    public func discardAll() async {
        guard let client = client else { return }

        do {
            try await client.discardAll()
            try await client.discardAllUntracked()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Hunk Operations

    /// Stage a single hunk
    ///
    /// - Parameters:
    ///   - hunk: The hunk to stage
    ///   - filePath: The file path for the patch
    public func stageHunk(_ hunk: DiffHunk, filePath: String) async {
        guard let client = client else { return }

        let patch = hunk.toPatch(oldPath: filePath, newPath: filePath)

        do {
            try await client.stageHunk(patch)
            await refresh()
            // Reload diff for the current file
            if let change = selectedChange {
                await loadDiff(for: change)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unstage a single hunk
    ///
    /// - Parameters:
    ///   - hunk: The hunk to unstage
    ///   - filePath: The file path for the patch
    public func unstageHunk(_ hunk: DiffHunk, filePath: String) async {
        guard let client = client else { return }

        let patch = hunk.toPatch(oldPath: filePath, newPath: filePath)

        do {
            try await client.unstageHunk(patch)
            await refresh()
            // Reload diff for the current file
            if let change = selectedChange {
                await loadDiff(for: change)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Discard a single hunk from working directory
    ///
    /// - Parameters:
    ///   - hunk: The hunk to discard
    ///   - filePath: The file path for the patch
    public func discardHunk(_ hunk: DiffHunk, filePath: String) async {
        guard let client = client else { return }

        let patch = hunk.toPatch(oldPath: filePath, newPath: filePath)

        do {
            try await client.discardHunk(patch)
            await refresh()
            // Reload diff for the current file
            if let change = selectedChange {
                await loadDiff(for: change)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
