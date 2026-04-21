// WorktreeStatusSummary.swift
// DevysGit - Summary of git status for a worktree.

import Foundation

public struct WorktreeStatusSummary: Equatable, Sendable {
    public let staged: Int
    public let unstaged: Int
    public let untracked: Int
    public let conflicts: Int

    public init(staged: Int, unstaged: Int, untracked: Int, conflicts: Int) {
        self.staged = staged
        self.unstaged = unstaged
        self.untracked = untracked
        self.conflicts = conflicts
    }

    public init(changes: [GitFileChange]) {
        self.staged = changes.filter(\.isStaged).count
        self.unstaged = changes.filter {
            !$0.isStaged &&
            $0.status != .untracked &&
            $0.status != .ignored &&
            $0.status != .unmerged
        }.count
        self.untracked = changes.filter { !$0.isStaged && $0.status == .untracked }.count
        self.conflicts = changes.filter { $0.status == .unmerged }.count
    }

    public var isClean: Bool {
        staged == 0 && unstaged == 0 && untracked == 0 && conflicts == 0
    }
}
