// NotificationNames.swift
// Devys - Notification name definitions.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

extension Notification.Name {
    /// Open folder picker (Cmd+O)
    static let devysOpenFolder = Notification.Name("devys.openFolder")

    /// Save the currently focused editor (Cmd+S)
    static let devysSave = Notification.Name("devys.save")
    
    /// Save the currently focused editor as a new file (Cmd+Shift+S)
    static let devysSaveAs = Notification.Name("devys.saveAs")
    
    /// Save all dirty editors (Cmd+Option+S)
    static let devysSaveAll = Notification.Name("devys.saveAll")
    
    /// Save the current layout as default
    static let devysSaveDefaultLayout = Notification.Name("devys.saveDefaultLayout")

    /// Show Worktrees sidebar
    static let devysShowWorktrees = Notification.Name("devys.showWorktrees")

    /// Show Explorer sidebar
    static let devysShowExplorer = Notification.Name("devys.showExplorer")

    /// Show Git sidebar
    static let devysShowGit = Notification.Name("devys.showGit")

    /// Select a worktree by index (0-based), expects userInfo["index"] Int
    static let devysSelectWorktreeIndex = Notification.Name("devys.selectWorktreeIndex")
}
