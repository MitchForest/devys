// WorktreeInfoWatcher.swift
// Worktree info watcher abstraction.

import Foundation
import Workspace

public enum WorktreeInfoCommand: Equatable, Sendable {
    case setWorktrees([Worktree])
    case setSelectedWorktreeId(Worktree.ID?)
    case setPullRequestTrackingEnabled(Bool)
    case stop
}

public enum WorktreeInfoEvent: Equatable, Sendable {
    case branchChanged(worktreeId: Worktree.ID)
    case filesChanged(worktreeId: Worktree.ID)
    case repositoryPullRequestRefresh(repositoryRootURL: URL, worktreeIds: [Worktree.ID])
}

public protocol WorktreeInfoWatcher: AnyObject, Sendable {
    func handle(_ command: WorktreeInfoCommand)
    func eventStream() -> AsyncStream<WorktreeInfoEvent>
}

public final class NoopWorktreeInfoWatcher: WorktreeInfoWatcher {
    public init() {}

    public func handle(_ command: WorktreeInfoCommand) {
        _ = command
    }

    public func eventStream() -> AsyncStream<WorktreeInfoEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
