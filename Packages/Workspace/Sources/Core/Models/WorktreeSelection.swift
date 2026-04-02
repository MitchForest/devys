// WorktreeSelection.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents the current worktree selection state.
public struct WorktreeSelection: Codable, Equatable, Sendable {
    /// Currently selected worktree identifier.
    public var selectedWorktreeId: String?

    /// Creates a new selection state.
    /// - Parameter selectedWorktreeId: Selected worktree identifier.
    public init(selectedWorktreeId: String? = nil) {
        self.selectedWorktreeId = selectedWorktreeId
    }

    /// Empty selection state.
    public static var empty: WorktreeSelection {
        WorktreeSelection(selectedWorktreeId: nil)
    }
}
