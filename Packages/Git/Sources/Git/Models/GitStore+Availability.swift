// GitStore+Availability.swift
// Availability and error-handling helpers for GitStore.

import Foundation

extension GitStore {
    /// Sets errorMessage only for real errors, ignoring task cancellation.
    func setError(_ error: Error, prefix: String? = nil) {
        guard !(error is CancellationError) else { return }
        if isNotRepositoryError(error) {
            applyRepositoryAvailability(false)
            return
        }
        if let prefix {
            errorMessage = "\(prefix): \(error.localizedDescription)"
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func isNotRepositoryError(_ error: Error) -> Bool {
        guard let gitError = error as? GitError else { return false }
        if case .notRepository = gitError {
            return true
        }
        return false
    }

    func applyRepositoryAvailability(_ isAvailable: Bool) {
        let didChange = isRepositoryAvailable != isAvailable
        isRepositoryAvailable = isAvailable
        if didChange {
            onRepositoryAvailabilityDidUpdate?(isAvailable)
        }
        guard !isAvailable else { return }

        repoInfo = nil
        changes = []
        commits = []
        selectedFilePath = nil
        selectedDiff = nil
        focusedHunkIndex = nil
        isPRAvailable = false
        selectedPR = nil
        prFiles = []
        selectedPRFile = nil
        selectedPRFileDiff = nil
        isShowingPRDetail = false
        errorMessage = nil
        onChangesDidUpdate?([])
    }

    func syncRepositoryAvailability() async -> Bool {
        let isAvailable = await gitService.isRepositoryAvailable()
        applyRepositoryAvailability(isAvailable)
        return isAvailable
    }

    func ensureRepositoryAvailability() async -> Bool {
        if isRepositoryAvailable {
            return true
        }
        return await syncRepositoryAvailability()
    }
}
