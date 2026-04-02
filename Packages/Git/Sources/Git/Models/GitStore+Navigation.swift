// GitStore+Navigation.swift
// Navigation helpers for GitStore.

import Foundation

@MainActor
extension GitStore {
    // MARK: - Hunk Navigation

    /// Navigate to next hunk.
    func nextHunk() {
        guard let diff = selectedDiff, !diff.hunks.isEmpty else { return }

        if let current = focusedHunkIndex {
            setFocusedHunkIndex(min(current + 1, diff.hunks.count - 1))
        } else {
            setFocusedHunkIndex(0)
        }
    }

    /// Navigate to previous hunk.
    func previousHunk() {
        guard let diff = selectedDiff, !diff.hunks.isEmpty else { return }

        if let current = focusedHunkIndex {
            setFocusedHunkIndex(max(current - 1, 0))
        } else {
            setFocusedHunkIndex(diff.hunks.count - 1)
        }
    }

    // MARK: - File Navigation

    /// Navigate to next changed file.
    func nextFile() async {
        let allFiles = stagedChanges + unstagedChanges
        guard !allFiles.isEmpty else { return }

        if let current = selectedFilePath,
           let currentIndex = allFiles.firstIndex(where: { $0.path == current }) {
            let nextIndex = min(currentIndex + 1, allFiles.count - 1)
            let nextFile = allFiles[nextIndex]
            await selectFile(nextFile.path, isStaged: nextFile.isStaged)
        } else if let first = allFiles.first {
            await selectFile(first.path, isStaged: first.isStaged)
        }
    }

    /// Navigate to previous changed file.
    func previousFile() async {
        let allFiles = stagedChanges + unstagedChanges
        guard !allFiles.isEmpty else { return }

        if let current = selectedFilePath,
           let currentIndex = allFiles.firstIndex(where: { $0.path == current }) {
            let prevIndex = max(currentIndex - 1, 0)
            let prevFile = allFiles[prevIndex]
            await selectFile(prevFile.path, isStaged: prevFile.isStaged)
        } else if let last = allFiles.last {
            await selectFile(last.path, isStaged: last.isStaged)
        }
    }
}
