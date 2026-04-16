import ACPClientKit
import Foundation
import Workspace

/// Identifier for tab content.
///
/// This enum intentionally models only semantic tab identity.
/// Dynamic presentation metadata comes from runtime/session state in the app.
public enum WorkspaceTabContent: Equatable, Sendable {
    case terminal(workspaceID: Workspace.ID, id: UUID)
    case agentSession(workspaceID: Workspace.ID, sessionID: ACPSessionID)
    case editor(workspaceID: Workspace.ID, url: URL)
    case gitDiff(workspaceID: Workspace.ID, path: String, isStaged: Bool)
    case settings

    public var workspaceID: Workspace.ID? {
        switch self {
        case .terminal(let workspaceID, _),
             .agentSession(let workspaceID, _),
             .editor(let workspaceID, _),
             .gitDiff(let workspaceID, _, _):
            return workspaceID
        case .settings:
            return nil
        }
    }

    public var fallbackTitle: String {
        switch self {
        case .gitDiff(_, let path, _):
            (path as NSString).lastPathComponent
        case .terminal:
            "Terminal"
        case .agentSession:
            "Agent"
        case .settings:
            "Settings"
        case .editor(_, let url):
            url.lastPathComponent
        }
    }

    public var fallbackIcon: String {
        switch self {
        case .gitDiff:
            return "plus.forwardslash.minus"
        case .terminal:
            return "terminal"
        case .agentSession:
            return "message"
        case .settings:
            return "gearshape"
        case .editor(_, let url):
            let pathExtension = url.pathExtension.lowercased()
            return pathExtension.isEmpty ? "doc.text" : pathExtension
        }
    }

    public var stableId: String {
        switch self {
        case .gitDiff(let workspaceID, let path, let isStaged):
            "gitDiff:\(workspaceID):\(path):\(isStaged)"
        case .terminal(let workspaceID, let id):
            "terminal:\(workspaceID):\(id.uuidString)"
        case .agentSession(let workspaceID, let sessionID):
            "agentSession:\(workspaceID):\(sessionID.rawValue)"
        case .settings:
            "settings"
        case .editor(let workspaceID, let url):
            "editor:\(workspaceID):\(url.absoluteString)"
        }
    }

    public func matchesSemanticIdentity(as other: Self) -> Bool {
        switch (self, other) {
        case let (.editor(workspaceIDA, urlA), .editor(workspaceIDB, urlB)):
            return workspaceIDA == workspaceIDB
                && urlA.standardizedFileURL == urlB.standardizedFileURL
        case let (.gitDiff(workspaceIDA, pathA, isStagedA), .gitDiff(workspaceIDB, pathB, isStagedB)):
            return workspaceIDA == workspaceIDB
                && pathA == pathB
                && isStagedA == isStagedB
        case let (.terminal(workspaceIDA, idA), .terminal(workspaceIDB, idB)):
            return workspaceIDA == workspaceIDB && idA == idB
        case let (.agentSession(workspaceIDA, sessionIDA), .agentSession(workspaceIDB, sessionIDB)):
            return workspaceIDA == workspaceIDB && sessionIDA == sessionIDB
        case (.settings, .settings):
            return true
        default:
            return false
        }
    }
}
