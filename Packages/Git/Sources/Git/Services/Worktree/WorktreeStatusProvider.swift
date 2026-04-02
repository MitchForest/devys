// WorktreeStatusProvider.swift
// DevysGit - Worktree git status summary provider.

import Foundation

public protocol WorktreeStatusProvider: Sendable {
    func statusSummary(for worktreeURL: URL) async -> WorktreeStatusSummary?
}

public struct DefaultWorktreeStatusProvider: WorktreeStatusProvider {
    public init() {}

    public func statusSummary(for worktreeURL: URL) async -> WorktreeStatusSummary? {
        let client = GitClient(repositoryURL: worktreeURL)
        let changes: [GitFileChange]
        do {
            changes = try await client.status()
        } catch {
            return nil
        }

        var staged = 0
        var unstaged = 0
        var untracked = 0
        var conflicts = 0

        for change in changes {
            if change.status == .unmerged {
                conflicts += 1
                continue
            }
            if change.status == .untracked {
                untracked += 1
                continue
            }
            if change.isStaged {
                staged += 1
            } else {
                unstaged += 1
            }
        }

        return WorktreeStatusSummary(
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
            conflicts: conflicts
        )
    }
}
