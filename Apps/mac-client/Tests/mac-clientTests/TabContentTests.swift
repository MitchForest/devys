import Foundation
import Testing
@testable import mac_client

@Suite("TabContent Tests")
struct TabContentTests {
    @Test("Editor tabs derive fallback title and stable id from URL")
    func editorTabMetadata() {
        let url = URL(fileURLWithPath: "/tmp/Notes.swift")
        let tab = TabContent.editor(workspaceID: "/tmp/devys/worktrees/main", url: url)

        #expect(tab.fallbackTitle == "Notes.swift")
        #expect(tab.fallbackIcon == "swift")
        #expect(tab.stableId == "editor:/tmp/devys/worktrees/main:\(url.absoluteString)")
    }

    @Test("Git diff tabs use the last path component in their title")
    func gitDiffMetadata() {
        let tab = TabContent.gitDiff(
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
        let first = TabContent.editor(workspaceID: "/tmp/devys/worktrees/a", url: url)
        let second = TabContent.editor(workspaceID: "/tmp/devys/worktrees/b", url: url)

        #expect(first.stableId != second.stableId)
        #expect(first.workspaceID == "/tmp/devys/worktrees/a")
        #expect(second.workspaceID == "/tmp/devys/worktrees/b")
    }

    @Test("Terminal and diff tabs stay isolated by workspace")
    func nonEditorWorkspaceScopedIdentity() {
        let sharedTerminalID = UUID()
        let firstTerminal = TabContent.terminal(
            workspaceID: "/tmp/devys/worktrees/a",
            id: sharedTerminalID
        )
        let secondTerminal = TabContent.terminal(
            workspaceID: "/tmp/devys/worktrees/b",
            id: sharedTerminalID
        )
        let firstDiff = TabContent.gitDiff(
            workspaceID: "/tmp/devys/worktrees/a",
            path: "Sources/Feature/Thing.swift",
            isStaged: false
        )
        let secondDiff = TabContent.gitDiff(
            workspaceID: "/tmp/devys/worktrees/b",
            path: "Sources/Feature/Thing.swift",
            isStaged: false
        )

        #expect(firstTerminal.stableId != secondTerminal.stableId)
        #expect(firstDiff.stableId != secondDiff.stableId)
        #expect(firstTerminal.workspaceID == "/tmp/devys/worktrees/a")
        #expect(secondDiff.workspaceID == "/tmp/devys/worktrees/b")
    }

    @Test("Welcome and settings tabs use stable built-in identifiers")
    func builtInMetadata() {
        #expect(TabContent.welcome.stableId == "welcome")
        #expect(TabContent.welcome.fallbackTitle == "Welcome")
        #expect(TabContent.settings.stableId == "settings")
        #expect(TabContent.settings.fallbackIcon == "gearshape")
        #expect(TabContent.welcome.workspaceID == nil)
        #expect(TabContent.settings.workspaceID == nil)
    }
}
