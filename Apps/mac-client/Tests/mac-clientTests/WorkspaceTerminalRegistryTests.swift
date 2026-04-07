import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Terminal Registry Tests")
struct WorkspaceTerminalRegistryTests {
    @Test("Sessions are owned by the workspace that created them")
    @MainActor
    func workspaceOwnership() {
        let registry = WorkspaceTerminalRegistry()
        let firstWorkspace = "/tmp/devys/worktrees/a"
        let secondWorkspace = "/tmp/devys/worktrees/b"

        let first = registry.createSession(in: firstWorkspace)
        let second = registry.createSession(in: secondWorkspace)

        #expect(registry.workspaceID(for: first.id) == firstWorkspace)
        #expect(registry.workspaceID(for: second.id) == secondWorkspace)
        #expect(registry.sessions(for: firstWorkspace)[first.id] === first)
        #expect(registry.sessions(for: secondWorkspace)[second.id] === second)
    }

    @Test("Unread state is tracked per workspace and can be cleared")
    @MainActor
    func unreadState() {
        let registry = WorkspaceTerminalRegistry()
        let workspaceID = "/tmp/devys/worktrees/a"
        let session = registry.createSession(in: workspaceID)

        session.bellCount = 2
        registry.syncUnreadState()

        #expect(registry.unreadTerminalIds(for: workspaceID) == Set([session.id]))

        registry.markRead(terminalId: session.id, in: workspaceID)

        #expect(registry.unreadTerminalIds(for: workspaceID).isEmpty)

        session.bellCount = 3
        registry.syncUnreadState()

        #expect(registry.unreadTerminalIds(for: workspaceID) == Set([session.id]))
    }

    @Test("Shutting down one workspace does not remove sessions from another")
    @MainActor
    func shutdownWorkspaceIsolation() {
        let registry = WorkspaceTerminalRegistry()
        let firstWorkspace = "/tmp/devys/worktrees/a"
        let secondWorkspace = "/tmp/devys/worktrees/b"

        let first = registry.createSession(in: firstWorkspace)
        let second = registry.createSession(in: secondWorkspace)

        registry.shutdownAllSessions(in: firstWorkspace)

        #expect(registry.workspaceID(for: first.id) == nil)
        #expect(registry.workspaceID(for: second.id) == secondWorkspace)
        #expect(registry.sessions(for: firstWorkspace).isEmpty)
        #expect(registry.sessions(for: secondWorkspace)[second.id] === second)
    }
}
