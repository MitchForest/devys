// TabContentProvider.swift
// DevysCore - Core functionality for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Protocol for objects that provide tab metadata.
///
/// This is the single source of truth pattern for tab display.
/// Sessions (ChatSession, TerminalSession, etc.) conform to this
/// protocol to provide their current tab title, icon, and folder.
///
/// ## Usage Pattern
///
/// ```swift
/// // Tab bar reads from provider, not frozen state
/// Text(session.tabTitle)
/// Image(systemName: session.tabIcon)
///
/// // Folder chip reads from provider
/// if let folder = session.tabFolder {
///     FolderChip(folder: folder)
/// }
/// ```
///
/// ## Why This Exists
///
/// Without this protocol, tab metadata gets "frozen" at creation time:
/// - User creates chat with Claude Code
/// - Tab title shows "Claude Code"
/// - User switches to Codex in composer
/// - Tab title still shows "Claude Code" ← BUG
///
/// With TabContentProvider, the session IS the source of truth.
/// The tab reads from the session dynamically.
@MainActor
public protocol TabContentProvider: AnyObject {
    /// The title to display in the tab.
    /// For terminals: shell title or current directory
    /// For chats: harness name (e.g., "Claude Code", "Codex")
    /// For editors: filename (with • prefix if dirty)
    var tabTitle: String { get }
    
    /// The SF Symbol icon name for the tab.
    var tabIcon: String { get }
    
    /// The folder this tab is associated with, if any.
    /// Displayed as a chip in the tab bar or header.
    var tabFolder: URL? { get }
    
    /// Optional subtitle for additional context.
    /// For chats: model name
    /// For terminals: current command
    var tabSubtitle: String? { get }

    /// Whether this tab should display a busy indicator.
    var tabShowsBusyIndicator: Bool { get }

    /// Whether the underlying session is currently busy.
    var tabIsBusy: Bool { get }
}

// MARK: - Default Implementations

public extension TabContentProvider {
    /// Default: no subtitle
    var tabSubtitle: String? { nil }
    
    /// Default: no folder
    var tabFolder: URL? { nil }

    /// Default: no busy indicator
    var tabShowsBusyIndicator: Bool { false }

    /// Default: not busy
    var tabIsBusy: Bool { false }
}
