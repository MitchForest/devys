// ToolKind.swift
// Tool classification for display and icon selection.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Categorization of tool calls for UI treatment (icons, grouping, colors).
///
/// Derived from ACP's ToolKind taxonomy and Zed's `toolInfoFromToolUse` mappings.
public enum ToolKind: String, Codable, Sendable, CaseIterable {
    /// Reading files or data.
    case read
    /// Modifying files or content.
    case edit
    /// Removing files or data.
    case delete
    /// Moving or renaming files.
    case move
    /// Searching for information (grep, glob, find).
    case search
    /// Running commands or code in a terminal.
    case execute
    /// Internal reasoning, planning, or sub-agent tasks.
    case think
    /// Retrieving external data (web fetch, web search).
    case fetch
    /// Switching modes (e.g. ExitPlanMode).
    case switchMode
    /// Uncategorized tool.
    case other

    /// SF Symbol name for this kind.
    public var iconName: String {
        switch self {
        case .read: return "doc.text"
        case .edit: return "pencil"
        case .delete: return "trash"
        case .move: return "arrow.right.doc.on.clipboard"
        case .search: return "magnifyingglass"
        case .execute: return "terminal"
        case .think: return "brain"
        case .fetch: return "globe"
        case .switchMode: return "arrow.triangle.2.circlepath"
        case .other: return "wrench"
        }
    }
}
