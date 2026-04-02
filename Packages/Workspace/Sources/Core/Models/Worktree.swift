// Worktree.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents a git worktree tracked by Devys.
public struct Worktree: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier for this worktree.
    /// Uses the working directory path for stable identity.
    public let id: String

    /// Branch or display name for the worktree.
    public var name: String

    /// Secondary detail (relative path or descriptor).
    public var detail: String

    /// URL to the worktree directory.
    public var workingDirectory: URL

    /// URL to the repository root.
    public var repositoryRootURL: URL

    /// When this worktree was created, if known.
    public var createdAt: Date?

    /// Creates a new worktree record.
    /// - Parameters:
    ///   - name: Branch or display name.
    ///   - detail: Secondary detail, such as relative path.
    ///   - workingDirectory: Worktree directory URL.
    ///   - repositoryRootURL: Repository root URL.
    ///   - createdAt: Optional creation date.
    public init(
        name: String,
        detail: String,
        workingDirectory: URL,
        repositoryRootURL: URL,
        createdAt: Date? = nil
    ) {
        self.id = workingDirectory.path
        self.name = name
        self.detail = detail
        self.workingDirectory = workingDirectory
        self.repositoryRootURL = repositoryRootURL
        self.createdAt = createdAt
    }

    /// Creates a worktree with defaults derived from paths.
    /// - Parameters:
    ///   - workingDirectory: Worktree directory URL.
    ///   - repositoryRootURL: Repository root URL.
    ///   - name: Optional display name. Defaults to folder name.
    ///   - detail: Optional detail. Defaults to folder name.
    ///   - createdAt: Optional creation date.
    public init(
        workingDirectory: URL,
        repositoryRootURL: URL,
        name: String? = nil,
        detail: String? = nil,
        createdAt: Date? = nil
    ) {
        let resolvedName = name ?? workingDirectory.lastPathComponent
        let resolvedDetail = detail ?? workingDirectory.lastPathComponent
        self.init(
            name: resolvedName,
            detail: resolvedDetail,
            workingDirectory: workingDirectory,
            repositoryRootURL: repositoryRootURL,
            createdAt: createdAt
        )
    }
}
