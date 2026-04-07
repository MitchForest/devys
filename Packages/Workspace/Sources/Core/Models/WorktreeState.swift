// WorktreeState.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Persistent state for a worktree (pinning, ordering, and archive state).
public struct WorktreeState: Codable, Equatable, Sendable {
    /// Worktree identifier (matches Worktree.id).
    public let worktreeId: String

    /// Whether the worktree is pinned.
    public var isPinned: Bool

    /// Whether the worktree is archived (hidden by default).
    public var isArchived: Bool

    /// Optional explicit ordering value.
    public var order: Int?

    /// Last time the worktree was focused.
    public var lastFocused: Date?

    /// Assigned agent name for multi-agent workflows.
    public var assignedAgentName: String?

    /// Optional user-visible display name override.
    public var displayNameOverride: String?

    /// Creates a new worktree state record.
    /// - Parameters:
    ///   - worktreeId: Worktree identifier.
    ///   - isPinned: Pin state.
    ///   - isArchived: Archive state.
    ///   - order: Optional ordering index.
    ///   - lastFocused: Last focused date.
    public init(
        worktreeId: String,
        isPinned: Bool = false,
        isArchived: Bool = false,
        order: Int? = nil,
        lastFocused: Date? = nil,
        assignedAgentName: String? = nil,
        displayNameOverride: String? = nil
    ) {
        self.worktreeId = worktreeId
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.order = order
        self.lastFocused = lastFocused
        self.assignedAgentName = assignedAgentName
        self.displayNameOverride = displayNameOverride
    }
}
