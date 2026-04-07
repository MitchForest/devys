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
        do {
            return try await client.statusSummary()
        } catch {
            return nil
        }
    }
}
