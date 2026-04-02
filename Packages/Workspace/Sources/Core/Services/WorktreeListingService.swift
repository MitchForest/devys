// WorktreeListingService.swift
// Abstraction for listing worktrees.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public protocol WorktreeListingService: Sendable {
    func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree]
}

public struct NoopWorktreeListingService: WorktreeListingService {
    public init() {}

    public func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree] {
        _ = repositoryRoot
        return []
    }
}
