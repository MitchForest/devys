// GitStore+RepositoryOperations.swift
// Remote, branch, and history operations for GitStore.

import Foundation

extension GitStore {
    // MARK: - Remote Operations

    /// Fetch from the remote.
    public func fetch() async {
        guard await ensureRepositoryAvailability() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.fetch()
            await refresh()
        } catch {
            if isNotRepositoryError(error) {
                applyRepositoryAvailability(false)
            } else if !(error is CancellationError) {
                errorMessage = formatFetchError(error)
            }
        }

        isLoading = false
    }

    /// Push to remote.
    public func push() async {
        guard await ensureRepositoryAvailability() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.push()
            await refresh()
        } catch {
            if isNotRepositoryError(error) {
                applyRepositoryAvailability(false)
            } else if !(error is CancellationError) {
                errorMessage = formatPushError(error)
            }
        }

        isLoading = false
    }

    /// Pull from remote.
    public func pull() async {
        guard await ensureRepositoryAvailability() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.pull()
            await refresh()
        } catch {
            if isNotRepositoryError(error) {
                applyRepositoryAvailability(false)
            } else if !(error is CancellationError) {
                errorMessage = formatPullError(error)
            }
        }

        isLoading = false
    }

    // MARK: - Branch Operations

    /// Load all branches.
    func loadBranches() async -> [GitBranch] {
        guard await ensureRepositoryAvailability() else { return [] }

        do {
            return try await gitService.branches()
        } catch {
            setError(error, prefix: "Failed to load branches")
            return []
        }
    }

    /// Checkout a branch.
    func checkout(branch: String) async {
        guard await ensureRepositoryAvailability() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.checkout(branch: branch)
            await refresh()
        } catch {
            setError(error, prefix: "Checkout failed")
        }

        isLoading = false
    }

    /// Create a new branch.
    func createBranch(name: String) async {
        guard await ensureRepositoryAvailability() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.createBranch(name: name)
            await refresh()
        } catch {
            setError(error, prefix: "Failed to create branch")
        }

        isLoading = false
    }

    /// Delete a branch.
    func deleteBranch(name: String, force: Bool = false) async {
        guard await ensureRepositoryAvailability() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.deleteBranch(name: name, force: force)
            await refresh()
        } catch {
            setError(error, prefix: "Failed to delete branch")
        }

        isLoading = false
    }

    // MARK: - Commit History

    /// Load commit history.
    func loadCommitHistory(count: Int = 50) async {
        guard await ensureRepositoryAvailability() else { return }

        isShowingHistory = true
        isShowingPRDetail = false

        do {
            commits = try await gitService.log(count: count)
        } catch {
            setError(error, prefix: "Failed to load commits")
            commits = []
        }
    }

    /// Show diff for a commit.
    func showCommit(_ commit: GitCommit) async -> String? {
        guard await ensureRepositoryAvailability() else { return nil }

        do {
            return try await gitService.show(commit: commit.hash)
        } catch {
            setError(error, prefix: "Failed to load commit diff")
            return nil
        }
    }

    private func formatFetchError(_ error: Error) -> String {
        "Fetch failed: \(error.localizedDescription)"
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
}
