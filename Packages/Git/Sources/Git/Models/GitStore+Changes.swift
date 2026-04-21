// GitStore+Changes.swift
// Diff, staging, and commit operations for GitStore.

import Foundation

extension GitStore {
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

    public func stageFile(_ path: String) async {
        await stage(path)
    }

    public func unstageFile(_ path: String) async {
        await unstage(path)
    }

    public func stageAllChanges() async {
        await stageAll()
    }

    public func unstageAllChanges() async {
        await unstageAll()
    }

    public func discardChange(_ change: GitFileChange) async {
        await discard(change)
    }

    public func stageDiffPatch(_ patch: String) async throws {
        guard await ensureRepositoryAvailability() else {
            throw GitError.notRepository(projectFolder ?? URL(fileURLWithPath: "/"))
        }
        try await gitService.stagePatch(patch)
    }

    public func unstageDiffPatch(_ patch: String) async throws {
        guard await ensureRepositoryAvailability() else {
            throw GitError.notRepository(projectFolder ?? URL(fileURLWithPath: "/"))
        }
        try await gitService.unstagePatch(patch)
    }

    public func discardDiffPatch(
        _ patch: String,
        wasStaged: Bool
    ) async throws {
        guard await ensureRepositoryAvailability() else {
            throw GitError.notRepository(projectFolder ?? URL(fileURLWithPath: "/"))
        }
        if wasStaged {
            try await gitService.unstagePatch(patch)
        }
        try await gitService.discardPatch(patch)
    }

    func setFocusedHunkIndex(_ index: Int?) {
        focusedHunkIndex = index
    }

    // MARK: - Diff

    func refreshDiff(for path: String, staged: Bool) async {
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

        // If already staged, nothing to do.
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
                // First unstage, then discard.
                try await gitService.unstageHunk(hunk, for: path)
            }
            // Discard the hunk by applying the reverse patch.
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
