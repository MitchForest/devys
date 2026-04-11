// TabContent.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import ACPClientKit
import Workspace

/// Identifier for tab content.
///
/// This enum is intentionally minimal - it only identifies WHAT is in a tab.
/// Dynamic metadata (title, icon, folder) comes from the session via TabContentProvider.
enum TabContent: Equatable {
    case welcome
    case terminal(workspaceID: Workspace.ID, id: UUID)
    case agentSession(workspaceID: Workspace.ID, sessionID: AgentSessionID)
    case editor(workspaceID: Workspace.ID, url: URL)
    case gitDiff(workspaceID: Workspace.ID, path: String, isStaged: Bool)
    case settings

    var workspaceID: Workspace.ID? {
        switch self {
        case .terminal(let workspaceID, _),
             .agentSession(let workspaceID, _),
             .editor(let workspaceID, _),
             .gitDiff(let workspaceID, _, _):
            return workspaceID
        case .welcome, .settings:
            return nil
        }
    }

    var fallbackTitle: String {
        switch self {
        case .welcome: return "Welcome"
        case .gitDiff(_, let path, _): return (path as NSString).lastPathComponent
        case .terminal: return "Terminal"
        case .agentSession: return "Agent"
        case .settings: return "Settings"
        case .editor(_, let url): return url.lastPathComponent
        }
    }

    var fallbackIcon: String {
        switch self {
        case .welcome: return "hand.wave"
        case .gitDiff: return "plus.forwardslash.minus"
        case .terminal: return "terminal"
        case .agentSession: return "message"
        case .settings: return "gearshape"
        case .editor(_, let url): return CEWorkspaceFileNode.fileTypeIcon(for: url.pathExtension)
        }
    }

    var stableId: String {
        switch self {
        case .welcome: return "welcome"
        case .gitDiff(let workspaceID, let path, let isStaged):
            return "gitDiff:\(workspaceID):\(path):\(isStaged)"
        case .terminal(let workspaceID, let id):
            return "terminal:\(workspaceID):\(id.uuidString)"
        case .agentSession(let workspaceID, let sessionID):
            return "agentSession:\(workspaceID):\(sessionID.rawValue)"
        case .settings: return "settings"
        case .editor(let workspaceID, let url):
            return "editor:\(workspaceID):\(url.absoluteString)"
        }
    }
}
