import Browser
import Foundation
import Observation
import Workspace

struct WorkspaceBrowserState {
    var sessionsByID: [UUID: BrowserSession] = [:]
}

@MainActor
@Observable
final class WorkspaceBrowserRegistry {
    private(set) var statesByWorkspace: [Workspace.ID: WorkspaceBrowserState] = [:]

    func sessions(for workspaceID: Workspace.ID?) -> [UUID: BrowserSession] {
        guard let workspaceID else { return [:] }
        return statesByWorkspace[workspaceID]?.sessionsByID ?? [:]
    }

    func session(id: UUID, in workspaceID: Workspace.ID?) -> BrowserSession? {
        guard let workspaceID else { return nil }
        return statesByWorkspace[workspaceID]?.sessionsByID[id]
    }

    @discardableResult
    func createSession(
        in workspaceID: Workspace.ID,
        url: URL,
        id: UUID = UUID()
    ) -> BrowserSession {
        let session = BrowserSession(id: id, url: url)
        var state = statesByWorkspace[workspaceID] ?? WorkspaceBrowserState()
        state.sessionsByID[session.id] = session
        statesByWorkspace[workspaceID] = state
        return session
    }

    func removeSession(id: UUID, in workspaceID: Workspace.ID) {
        guard var state = statesByWorkspace[workspaceID] else { return }
        state.sessionsByID.removeValue(forKey: id)
        statesByWorkspace[workspaceID] = state
        cleanupWorkspaceIfEmpty(workspaceID)
    }

    func removeAllSessions(in workspaceID: Workspace.ID) {
        statesByWorkspace.removeValue(forKey: workspaceID)
    }

    private func cleanupWorkspaceIfEmpty(_ workspaceID: Workspace.ID) {
        guard let state = statesByWorkspace[workspaceID] else { return }
        guard state.sessionsByID.isEmpty else { return }
        statesByWorkspace.removeValue(forKey: workspaceID)
    }
}
