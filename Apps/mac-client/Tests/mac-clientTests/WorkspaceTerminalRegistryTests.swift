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

    @Test("Shutting down the last session removes the workspace entry")
    @MainActor
    func shutdownLastSessionCleansUpWorkspace() {
        let registry = WorkspaceTerminalRegistry()
        let workspaceID = "/tmp/devys/worktrees/a"
        let session = registry.createSession(in: workspaceID)

        registry.shutdownSession(id: session.id, in: workspaceID)

        #expect(registry.workspaceID(for: session.id) == nil)
        #expect(registry.sessions(for: workspaceID).isEmpty)
        #expect(registry.statesByWorkspace[workspaceID] == nil)
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

    @Test("Sessions preserve the requested startup phase")
    @MainActor
    func sessionStartupPhase() {
        let registry = WorkspaceTerminalRegistry()
        let workspaceID = "/tmp/devys/worktrees/a"

        let session = registry.createSession(
            in: workspaceID,
            startupPhase: .startingHost
        )

        #expect(session.startupPhase == .startingHost)
        #expect(registry.sessions(for: workspaceID)[session.id] === session)
    }

    @Test("Preferred viewport size seeds the hosted controller before first measurement")
    @MainActor
    func preferredViewportSizeSeedsController() {
        let registry = WorkspaceTerminalRegistry()
        let workspaceID = "/tmp/devys/worktrees/a"
        let session = registry.createSession(
            in: workspaceID,
            preferredViewportSize: HostedTerminalViewportSize(cols: 132, rows: 42)
        )

        let controller = registry.ensureController(
            for: session.id,
            in: workspaceID,
            socketPath: "/tmp/devys-terminal-test.sock",
            appearance: .defaultDark
        )

        #expect(controller?.surfaceState.cols == 132)
        #expect(controller?.surfaceState.rows == 42)
    }
}
