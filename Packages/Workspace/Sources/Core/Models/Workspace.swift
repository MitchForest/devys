// Workspace.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents the product-level workspace primitive.
/// One workspace is exactly one branch and one git worktree.
public struct Workspace: Identifiable, Codable, Equatable, Hashable, Sendable {
    public typealias ID = String

    /// Stable identifier for this workspace.
    /// Uses the standardized worktree path.
    public let id: ID

    /// Owning repository identifier.
    public var repositoryID: Repository.ID

    /// Branch checked out in this workspace.
    public var branchName: String

    /// URL to the git worktree directory.
    public var worktreeURL: URL

    /// Workspace creation/import kind.
    public var kind: WorkspaceKind

    public init(
        repositoryID: Repository.ID,
        branchName: String,
        worktreeURL: URL,
        kind: WorkspaceKind = .branch
    ) {
        let normalizedWorktreeURL = worktreeURL.standardizedFileURL

        self.id = normalizedWorktreeURL.path
        self.repositoryID = repositoryID
        self.branchName = branchName
        self.worktreeURL = normalizedWorktreeURL
        self.kind = kind
    }
}

public enum WorkspaceKind: String, Codable, CaseIterable, Sendable {
    case branch
    case pullRequest
    case imported
}
