import ACPClientKit
import AppFeatures
import Foundation
import Testing

@Suite("WorkspaceTabContent Tests")
struct TabContentTests {
    @Test("Editor tabs derive fallback title and stable id from URL")
    func editorTabMetadata() {
        let url = URL(fileURLWithPath: "/tmp/Notes.swift")
        let tab = WorkspaceTabContent.editor(workspaceID: "/tmp/devys/worktrees/main", url: url)

        #expect(tab.fallbackTitle == "Notes.swift")
        #expect(tab.fallbackIcon == "swift")
        #expect(tab.stableId == "editor:/tmp/devys/worktrees/main:\(url.absoluteString)")
    }

    @Test("Git diff tabs use the last path component in their title")
    func gitDiffMetadata() {
        let tab = WorkspaceTabContent.gitDiff(
            workspaceID: "/tmp/devys/worktrees/feature",
            path: "Sources/Feature/Thing.swift",
            isStaged: true
        )

        #expect(tab.fallbackTitle == "Thing.swift")
        #expect(tab.fallbackIcon == "plus.forwardslash.minus")
        #expect(tab.stableId == "gitDiff:/tmp/devys/worktrees/feature:Sources/Feature/Thing.swift:true")
    }

    @Test("Workspace ownership participates in tab identity")
    func workspaceScopedIdentity() {
        let url = URL(fileURLWithPath: "/tmp/Notes.swift")
        let first = WorkspaceTabContent.editor(workspaceID: "/tmp/devys/worktrees/a", url: url)
        let second = WorkspaceTabContent.editor(workspaceID: "/tmp/devys/worktrees/b", url: url)

        #expect(first.stableId != second.stableId)
        #expect(first.workspaceID == "/tmp/devys/worktrees/a")
        #expect(second.workspaceID == "/tmp/devys/worktrees/b")
    }

    @Test("Terminal and diff tabs stay isolated by workspace")
    func nonEditorWorkspaceScopedIdentity() {
        let sharedTerminalID = UUID()
        let sharedAgentSessionID = ACPSessionID(rawValue: "agent-session")
        let firstTerminal = WorkspaceTabContent.terminal(
            workspaceID: "/tmp/devys/worktrees/a",
            id: sharedTerminalID
        )
        let secondTerminal = WorkspaceTabContent.terminal(
            workspaceID: "/tmp/devys/worktrees/b",
            id: sharedTerminalID
        )
        let firstDiff = WorkspaceTabContent.gitDiff(
            workspaceID: "/tmp/devys/worktrees/a",
            path: "Sources/Feature/Thing.swift",
            isStaged: false
        )
        let secondDiff = WorkspaceTabContent.gitDiff(
            workspaceID: "/tmp/devys/worktrees/b",
            path: "Sources/Feature/Thing.swift",
            isStaged: false
        )
        let firstAgent = WorkspaceTabContent.agentSession(
            workspaceID: "/tmp/devys/worktrees/a",
            sessionID: sharedAgentSessionID
        )
        let secondAgent = WorkspaceTabContent.agentSession(
            workspaceID: "/tmp/devys/worktrees/b",
            sessionID: sharedAgentSessionID
        )

        #expect(firstTerminal.stableId != secondTerminal.stableId)
        #expect(firstDiff.stableId != secondDiff.stableId)
        #expect(firstAgent.stableId != secondAgent.stableId)
        #expect(firstTerminal.workspaceID == "/tmp/devys/worktrees/a")
        #expect(secondDiff.workspaceID == "/tmp/devys/worktrees/b")
        #expect(firstAgent.fallbackTitle == "Agent")
        #expect(secondAgent.fallbackIcon == "message")
    }

    @Test("Settings tabs use stable built-in identifiers")
    func builtInMetadata() {
        #expect(WorkspaceTabContent.settings.stableId == "settings")
        #expect(WorkspaceTabContent.settings.fallbackIcon == "gearshape")
        #expect(WorkspaceTabContent.settings.workspaceID == nil)
    }
}
