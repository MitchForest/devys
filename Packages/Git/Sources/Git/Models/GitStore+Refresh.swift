// GitStore+Refresh.swift
// Repository watching, refresh, and initialization helpers for GitStore.

import Foundation
import Workspace

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

                // Ignore changes inside .git/ directory because git CLI
                // operations would otherwise cause refresh loops.
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
}
