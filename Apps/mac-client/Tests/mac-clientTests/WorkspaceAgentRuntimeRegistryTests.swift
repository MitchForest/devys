import ACPClientKit
import AppFeatures
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Worktree Chat Runtime Tests")
struct WorktreeChatRuntimeTests {
    @Test("Rekeying a pending session preserves the runtime and updates the lookup")
    @MainActor
    func rekeySessionUpdatesIdentityInPlace() throws {
        let registry = WorktreeRuntimeRegistry()
        let worktree = Worktree(
            workingDirectory: URL(fileURLWithPath: "/tmp/devys/worktrees/rekey"),
            repositoryRootURL: URL(fileURLWithPath: "/tmp/devys/repositories/rekey")
        )
        registry.activate(worktree: worktree, filesSidebarVisible: false)
        let pendingID = ChatSessionID(rawValue: "pending-session")
        let finalID = ChatSessionID(rawValue: "session-final")
        let runtime = try #require(registry.ensureChatSession(
            in: worktree.id,
            sessionID: pendingID,
            descriptor: ACPAgentDescriptor(
                kind: .codex,
                displayName: "Chat",
                executableName: "pending-chat"
            )
        ))

        registry.rekeyChatSession(
            runtime,
            in: worktree.id,
            to: finalID,
            descriptor: ACPAgentDescriptor.descriptor(for: .claude)
        )

        #expect(registry.chatSession(id: pendingID, in: worktree.id) == nil)
        #expect(registry.chatSession(id: finalID, in: worktree.id) === runtime)
        #expect(runtime.sessionID == finalID)
        #expect(runtime.descriptor.kind == .claude)
    }

    @Test("Workspace runtime switching preserves inactive chat sessions")
    @MainActor
    func workspaceSwitchingPreservesChatState() throws {
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
        let firstSession = try #require(registry.ensureChatSession(
            in: firstWorktree.id,
            sessionID: ChatSessionID(rawValue: "session-a"),
            descriptor: ACPAgentDescriptor.descriptor(for: .codex)
        ))
        firstSession.updatePresentation(title: "Codex Session")

        registry.activate(worktree: secondWorktree, filesSidebarVisible: false)
        #expect(
            registry.chatSession(
                id: ChatSessionID(rawValue: "session-a"),
                in: secondWorktree.id
            ) == nil
        )

        _ = try #require(registry.ensureChatSession(
            in: secondWorktree.id,
            sessionID: ChatSessionID(rawValue: "session-b"),
            descriptor: ACPAgentDescriptor.descriptor(for: .claude)
        ))

        registry.activate(worktree: firstWorktree, filesSidebarVisible: false)
        let restoredFirstSession = registry.chatSession(
            id: ChatSessionID(rawValue: "session-a"),
            in: firstWorktree.id
        )

        #expect(restoredFirstSession?.tabTitle == "Codex Session")
        #expect(restoredFirstSession?.workspaceID == firstWorktree.id)
        #expect(
            registry.chatSession(
                id: ChatSessionID(rawValue: "session-b"),
                in: firstWorktree.id
            ) == nil
        )
    }
}
