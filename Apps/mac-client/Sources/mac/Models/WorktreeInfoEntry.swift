// WorktreeInfoEntry.swift
// Devys - Worktree metadata for sidebar display.

import Foundation
import Git

struct WorktreeInfoEntry: Equatable, Sendable {
    var branchName: String?
    var lineChanges: WorktreeLineChanges?
    var statusSummary: WorktreeStatusSummary?
    var pullRequest: PullRequest?

    init(
        branchName: String? = nil,
        lineChanges: WorktreeLineChanges? = nil,
        statusSummary: WorktreeStatusSummary? = nil,
        pullRequest: PullRequest? = nil
    ) {
        self.branchName = branchName
        self.lineChanges = lineChanges
        self.statusSummary = statusSummary
        self.pullRequest = pullRequest
    }
}
