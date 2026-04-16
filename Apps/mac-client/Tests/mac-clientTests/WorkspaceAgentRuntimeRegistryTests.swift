import ACPClientKit
import AppFeatures
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Worktree Agent Runtime Tests")
struct WorktreeAgentRuntimeTests {
    @Test("Rekeying a pending session preserves the runtime and updates the lookup")
    @MainActor
    func rekeySessionUpdatesIdentityInPlace() throws {
        let registry = WorktreeRuntimeRegistry()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/worktrees/rekey"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repositories/rekey")
        )
        registry.activate(worktree: worktree, filesSidebarVisible: false)
        let pendingID = AgentSessionID(rawValue: "pending-session")
        let finalID = AgentSessionID(rawValue: "session-final")
        let runtime = try #require(registry.ensureAgentSession(
            in: worktree.id,
            sessionID: pendingID,
            descriptor: ACPAgentDescriptor(
                kind: .codex,
                displayName: "Agents",
                executableName: "pending-agent"
            )
        ))

        registry.rekeyAgentSession(
            runtime,
            in: worktree.id,
            to: finalID,
            descriptor: ACPAgentDescriptor.descriptor(for: .claude)
        )

        #expect(registry.agentSession(id: pendingID, in: worktree.id) == nil)
        #expect(registry.agentSession(id: finalID, in: worktree.id) === runtime)
        #expect(runtime.sessionID == finalID)
        #expect(runtime.descriptor.kind == .claude)
    }

    @Test("Workspace runtime switching preserves inactive agent sessions")
    @MainActor
    func workspaceSwitchingPreservesAgentState() throws {
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
        #expect(registry.worktree(for: firstWorktree.id)?.id == firstWorktree.id)
        let firstSession = try #require(registry.ensureAgentSession(
            in: firstWorktree.id,
            sessionID: AgentSessionID(rawValue: "session-a"),
            descriptor: ACPAgentDescriptor.descriptor(for: .codex)
        ))
        firstSession.updatePresentation(title: "Codex Session")

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)
        #expect(
            registry.agentSession(
                id: AgentSessionID(rawValue: "session-a"),
                in: secondWorktree.id
            ) == nil
        )

        _ = try #require(registry.ensureAgentSession(
            in: secondWorktree.id,
            sessionID: AgentSessionID(rawValue: "session-b"),
            descriptor: ACPAgentDescriptor.descriptor(for: .claude)
        ))

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        let restoredFirstSession = registry.agentSession(
            id: AgentSessionID(rawValue: "session-a"),
            in: firstWorktree.id
        )

        #expect(restoredFirstSession?.tabTitle == "Codex Session")
        #expect(restoredFirstSession?.workspaceID == firstWorktree.id)
        #expect(
            registry.agentSession(
                id: AgentSessionID(rawValue: "session-b"),
                in: firstWorktree.id
            ) == nil
        )
    }
}
