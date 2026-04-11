import ACPClientKit
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace Agent Runtime Registry Tests")
struct WorkspaceAgentRuntimeRegistryTests {
    @Test("Rekeying a pending session preserves the runtime and updates the lookup")
    @MainActor
    func rekeySessionUpdatesIdentityInPlace() {
        let registry = WorkspaceAgentRuntimeRegistry()
        let pendingID = AgentSessionID(rawValue: "pending-session")
        let finalID = AgentSessionID(rawValue: "session-final")
        let runtime = registry.ensureSession(
            workspaceID: "/tmp/devys/worktrees/rekey",
            sessionID: pendingID,
            descriptor: ACPAgentDescriptor(
                kind: .codex,
                displayName: "Agents",
                executableName: "pending-agent"
            )
        )

        registry.rekeySession(
            runtime,
            to: finalID,
            descriptor: ACPAgentDescriptor.descriptor(for: .claude)
        )

        #expect(registry.session(id: pendingID) == nil)
        #expect(registry.session(id: finalID) === runtime)
        #expect(runtime.sessionID == finalID)
        #expect(runtime.descriptor.kind == .claude)
    }

    @Test("Workspace runtime switching preserves inactive agent sessions")
    @MainActor
    func workspaceSwitchingPreservesAgentState() {
        let registry = WorktreeRuntimeRegistry()
        let firstWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/worktrees/a"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repositories/a")
        )
        let secondWorktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/worktrees/b"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repositories/b")
        )

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        let firstShellState = registry.shellState(for: firstWorktree)
        let firstSession = firstShellState.agentRuntimeRegistry.ensureSession(
            workspaceID: firstWorktree.id,
            sessionID: AgentSessionID(rawValue: "session-a"),
            descriptor: ACPAgentDescriptor.descriptor(for: .codex)
        )
        firstSession.updatePresentation(title: "Codex Session")
        registry.persistShellState(firstShellState)

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)
        let secondShellState = registry.shellState(for: secondWorktree)
        #expect(secondShellState.agentRuntimeRegistry.session(id: AgentSessionID(rawValue: "session-a")) == nil)

        secondShellState.agentRuntimeRegistry.ensureSession(
            workspaceID: secondWorktree.id,
            sessionID: AgentSessionID(rawValue: "session-b"),
            descriptor: ACPAgentDescriptor.descriptor(for: .claude)
        )
        registry.persistShellState(secondShellState)

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        let restoredFirstSession = registry.activeShellState?
            .agentRuntimeRegistry
            .session(id: AgentSessionID(rawValue: "session-a"))

        #expect(restoredFirstSession?.tabTitle == "Codex Session")
        #expect(restoredFirstSession?.workspaceID == firstWorktree.id)
        #expect(
            registry.activeShellState?
                .agentRuntimeRegistry
                .session(id: AgentSessionID(rawValue: "session-b")) == nil
        )
    }
}
