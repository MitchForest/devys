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
        let sharedBrowserID = UUID()
        let sharedChatSessionID = ACPSessionID(rawValue: "chat-session")
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
        let firstBrowser = WorkspaceTabContent.browser(
            workspaceID: "/tmp/devys/worktrees/a",
            id: sharedBrowserID,
            initialURL: URL(string: "http://localhost:3000")!
        )
        let secondBrowser = WorkspaceTabContent.browser(
            workspaceID: "/tmp/devys/worktrees/b",
            id: sharedBrowserID,
            initialURL: URL(string: "http://localhost:5173")!
        )
        let firstAgent = WorkspaceTabContent.chatSession(
            workspaceID: "/tmp/devys/worktrees/a",
            sessionID: sharedChatSessionID
        )
        let secondAgent = WorkspaceTabContent.chatSession(
            workspaceID: "/tmp/devys/worktrees/b",
            sessionID: sharedChatSessionID
        )

        #expect(firstTerminal.stableId != secondTerminal.stableId)
        #expect(firstDiff.stableId != secondDiff.stableId)
        #expect(firstBrowser.stableId != secondBrowser.stableId)
        #expect(firstBrowser.matchesSemanticIdentity(as: .browser(
            workspaceID: "/tmp/devys/worktrees/a",
            id: sharedBrowserID,
            initialURL: URL(string: "http://localhost:9999")!
        )))
        #expect(firstAgent.stableId != secondAgent.stableId)
        #expect(firstTerminal.workspaceID == "/tmp/devys/worktrees/a")
        #expect(secondDiff.workspaceID == "/tmp/devys/worktrees/b")
        #expect(firstBrowser.fallbackTitle == "Browser")
        #expect(secondBrowser.fallbackIcon == "globe")
        #expect(firstAgent.fallbackTitle == "Chat")
        #expect(secondAgent.fallbackIcon == "person.crop.circle")
    }

    @Test("Settings tabs use stable built-in identifiers")
    func builtInMetadata() {
        #expect(WorkspaceTabContent.settings.stableId == "settings")
        #expect(WorkspaceTabContent.settings.fallbackIcon == "gearshape")
        #expect(WorkspaceTabContent.settings.workspaceID == nil)
    }

    @Test("Workflow tabs participate in workspace-scoped identity")
    func workflowMetadata() {
        let runID = UUID()
        let reviewRunID = UUID()
        let definition = WorkspaceTabContent.workflowDefinition(
            workspaceID: "/tmp/devys/worktrees/a",
            definitionID: "delivery"
        )
        let run = WorkspaceTabContent.workflowRun(
            workspaceID: "/tmp/devys/worktrees/a",
            runID: runID
        )
        let review = WorkspaceTabContent.reviewRun(
            workspaceID: "/tmp/devys/worktrees/a",
            runID: reviewRunID
        )

        #expect(definition.fallbackTitle == "Workflow")
        #expect(run.fallbackIcon == "point.3.connected.trianglepath.dotted")
        #expect(review.fallbackTitle == "Review")
        #expect(review.fallbackIcon == "checklist")
        #expect(definition.stableId == "workflowDefinition:/tmp/devys/worktrees/a:delivery")
        #expect(run.stableId == "workflowRun:/tmp/devys/worktrees/a:\(runID.uuidString)")
        #expect(review.stableId == "reviewRun:/tmp/devys/worktrees/a:\(reviewRunID.uuidString)")
    }
}
