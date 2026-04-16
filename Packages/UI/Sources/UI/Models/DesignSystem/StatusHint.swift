// StatusHint.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Lightweight status summary for rail and sidebar items.
///
/// Maps to semantic colors from the theme. Used by `RepoItem` (aggregate repo
/// status) and `WorktreeItem` (individual worktree status).
public enum StatusHint: String, Sendable, CaseIterable {
    case clean
    case dirty
    case attention
    case error

    public func color(theme: Theme) -> Color {
        switch self {
        case .clean: theme.success
        case .dirty: theme.warning
        case .attention: theme.accent
        case .error: theme.error
        }
    }
}
