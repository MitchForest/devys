// WorktreeLineChanges.swift
// DevysGit - Worktree line change summary.

import Foundation

public struct WorktreeLineChanges: Equatable, Sendable {
    public let added: Int
    public let removed: Int

    public init(added: Int, removed: Int) {
        self.added = added
        self.removed = removed
    }

    public var isEmpty: Bool {
        added == 0 && removed == 0
    }
}
