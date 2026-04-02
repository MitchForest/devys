// TabContent.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Workspace

/// Identifier for tab content.
///
/// This enum is intentionally minimal - it only identifies WHAT is in a tab.
/// Dynamic metadata (title, icon, folder) comes from the session via TabContentProvider.
enum TabContent: Equatable {
    case welcome
    case terminal(id: UUID)
    case editor(url: URL)
    case gitDiff(path: String, isStaged: Bool)
    case settings

    var fallbackTitle: String {
        switch self {
        case .welcome: return "Welcome"
        case .gitDiff(let path, _): return (path as NSString).lastPathComponent
        case .terminal: return "Terminal"
        case .settings: return "Settings"
        case .editor(let url): return url.lastPathComponent
        }
    }

    var fallbackIcon: String {
        switch self {
        case .welcome: return "hand.wave"
        case .gitDiff: return "plus.forwardslash.minus"
        case .terminal: return "terminal"
        case .settings: return "gearshape"
        case .editor(let url): return CEWorkspaceFileNode.fileTypeIcon(for: url.pathExtension)
        }
    }

    var stableId: String {
        switch self {
        case .welcome: return "welcome"
        case .gitDiff(let path, let isStaged): return "gitDiff:\(path):\(isStaged)"
        case .terminal(let id): return "terminal:\(id.uuidString)"
        case .settings: return "settings"
        case .editor(let url): return "editor:\(url.absoluteString)"
        }
    }
}
