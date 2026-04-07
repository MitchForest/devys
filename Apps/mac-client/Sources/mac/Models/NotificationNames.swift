// NotificationNames.swift
// Devys - Notification name definitions.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

extension Notification.Name {
    /// Open repository picker (Cmd+O)
    static let devysAddRepository = Notification.Name("devys.addRepository")

    /// Save the currently focused editor (Cmd+S)
    static let devysSave = Notification.Name("devys.save")
    
    /// Save the currently focused editor as a new file (Cmd+Shift+S)
    static let devysSaveAs = Notification.Name("devys.saveAs")
    
    /// Save all dirty editors (Cmd+Option+S)
    static let devysSaveAll = Notification.Name("devys.saveAll")
    
    /// Save the current layout as default
    static let devysSaveDefaultLayout = Notification.Name("devys.saveDefaultLayout")

    /// Show Files sidebar
    static let devysShowFilesSidebar = Notification.Name("devys.showFilesSidebar")

    /// Show Changes sidebar
    static let devysShowChangesSidebar = Notification.Name("devys.showChangesSidebar")

    /// Show Ports sidebar
    static let devysShowPortsSidebar = Notification.Name("devys.showPortsSidebar")

    /// Select a workspace by index (0-based), expects userInfo["index"] Int
    static let devysSelectWorkspaceIndex = Notification.Name("devys.selectWorkspaceIndex")

    /// Present the global command palette
    static let devysOpenCommandPalette = Notification.Name("devys.openCommandPalette")

    /// Select the next visible workspace in navigator order
    static let devysSelectNextWorkspace = Notification.Name("devys.selectNextWorkspace")

    /// Select the previous visible workspace in navigator order
    static let devysSelectPreviousWorkspace = Notification.Name("devys.selectPreviousWorkspace")

    /// Toggle the active workspace sidebar
    static let devysToggleSidebar = Notification.Name("devys.toggleSidebar")

    /// Toggle the repository navigator visibility
    static let devysToggleNavigator = Notification.Name("devys.toggleNavigator")

    /// Launch a shell for the selected workspace
    static let devysLaunchShell = Notification.Name("devys.launchShell")

    /// Launch Claude for the selected workspace
    static let devysLaunchClaude = Notification.Name("devys.launchClaude")

    /// Launch Codex for the selected workspace
    static let devysLaunchCodex = Notification.Name("devys.launchCodex")

    /// Run the selected workspace profile
    static let devysRunWorkspaceProfile = Notification.Name("devys.runWorkspaceProfile")

    /// Reveal the current workspace in the navigator
    static let devysRevealCurrentWorkspaceInNavigator = Notification.Name("devys.revealCurrentWorkspaceInNavigator")

    /// Cross-process workspace attention ingress
    static let devysWorkspaceAttentionIngress = Notification.Name("devys.workspaceAttentionIngress")

    /// Jump to the latest workspace that needs attention
    static let devysJumpToLatestUnreadWorkspace = Notification.Name("devys.jumpToLatestUnreadWorkspace")

    /// Present the workspace notifications panel
    static let devysShowWorkspaceNotifications = Notification.Name("devys.showWorkspaceNotifications")
}
