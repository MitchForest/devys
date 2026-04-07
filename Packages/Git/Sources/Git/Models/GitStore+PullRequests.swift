// GitStore+PullRequests.swift
// Pull request operations for GitStore.

import Foundation

@MainActor
extension GitStore {
    /// Load pull requests.
    func loadPRs(state: PRStateFilter = .open) async -> [PullRequest] {
        guard gitService.hasPRClient else { return [] }

        do {
            return try await gitService.listPRs(state: state)
        } catch {
            setError(error, prefix: "Failed to load PRs")
            return []
        }
    }

    /// Select a PR and load its files.
    func selectPR(_ pr: PullRequest) async {
        guard gitService.hasPRClient else { return }

        isLoading = true
        errorMessage = nil
        isShowingHistory = false
        isShowingPRDetail = true
        selectedPR = pr
        selectedPRFile = nil
        selectedPRFileDiff = nil

        do {
            let files = try await gitService.getPRFiles(number: pr.number)
            prFiles = files
            if let first = files.first {
                selectPRFile(first)
            }
        } catch {
            setError(error, prefix: "Failed to load PR files")
        }

        isLoading = false
    }

    /// Select a PR file and parse its diff.
    func selectPRFile(_ file: PRFile) {
        selectedPRFile = file
        if let patch = file.patch, !patch.isEmpty {
            selectedPRFileDiff = DiffParser.parse(patch)
        } else {
            selectedPRFileDiff = nil
        }
    }

    /// Checkout a PR.
    func checkoutPR(_ pr: PullRequest) async {
        guard gitService.hasPRClient else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.checkoutPR(number: pr.number)
            await refresh()
        } catch {
            setError(error, prefix: "Failed to checkout PR")
        }

        isLoading = false
    }

    /// Create a new PR.
    func createPR(title: String, body: String, base: String, draft: Bool) async throws -> Int {
        guard gitService.hasPRClient else {
            throw PRError.ghNotInstalled
        }

        return try await gitService.createPR(title: title, body: body, base: base, draft: draft)
    }

    /// Merge a PR.
    func mergePR(_ pr: PullRequest, method: MergeMethod = .squash) async {
        guard gitService.hasPRClient else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await gitService.mergePR(number: pr.number, method: method)
            await refresh()
        } catch {
            setError(error, prefix: "Failed to merge PR")
        }

        isLoading = false
    }

    /// Get PR URL.
    public func prURL(_ pr: PullRequest) async -> URL? {
        guard gitService.hasPRClient else { return nil }
        return await gitService.prURL(number: pr.number)
    }
}
