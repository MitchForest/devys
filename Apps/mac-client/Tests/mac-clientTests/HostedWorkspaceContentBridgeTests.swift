import ACPClientKit
import AppFeatures
import Browser
import Editor
import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Hosted Workspace Content Bridge Tests")
struct HostedWorkspaceContentBridgeTests {
    @Test("Bridge publishes editor summaries from focused session observation")
    @MainActor
    func publishesEditorSummariesFromSessionObservation() async {
        let workspaceID = Workspace.ID("/tmp/devys-hosted-editor")
        let bridge = HostedWorkspaceContentBridge()
        var publishedByWorkspaceID: [Workspace.ID: HostedWorkspaceContentState] = [:]
        bridge.setPublishHandler { workspaceID, content in
            publishedByWorkspaceID[workspaceID] = content
        }

        let session = EditorSession(url: URL(fileURLWithPath: "/tmp/devys-hosted-editor/main.swift"))

        bridge.attachEditorSession(session, workspaceID: workspaceID)

        #expect(publishedByWorkspaceID[workspaceID]?.editorDocuments.map { $0.title } == ["main.swift"])
        #expect(publishedByWorkspaceID[workspaceID]?.dirtyEditorCount == 0)

        let document = EditorDocument(content: "print(\"updated\")")
        document.isDirty = true
        session.document = document
        await flushObservationUpdates()

        #expect(publishedByWorkspaceID[workspaceID]?.editorDocuments.first?.isDirty == true)

        session.updateURL(URL(fileURLWithPath: "/tmp/devys-hosted-editor/App.swift"))
        await flushObservationUpdates()

        #expect(publishedByWorkspaceID[workspaceID]?.editorDocuments.map { $0.title } == ["App.swift"])

        bridge.detachEditorSession(session, workspaceID: workspaceID)

        #expect(publishedByWorkspaceID[workspaceID]?.editorDocuments.isEmpty == true)
    }

    @Test("Bridge republishes chat summaries when session identity and presentation change")
    @MainActor
    func republishesChatSummariesForChatRuntimeChanges() async {
        let workspaceID = Workspace.ID("/tmp/devys-hosted-chat")
        let descriptor = ACPAgentDescriptor.descriptor(for: .codex)
        let runtime = ChatSessionRuntime(
            workspaceID: workspaceID,
            sessionID: ChatSessionID(rawValue: "pending-chat"),
            descriptor: descriptor
        )
        let bridge = HostedWorkspaceContentBridge()
        var publishedByWorkspaceID: [Workspace.ID: HostedWorkspaceContentState] = [:]
        bridge.setPublishHandler { workspaceID, content in
            publishedByWorkspaceID[workspaceID] = content
        }

        bridge.attachChatSession(runtime, workspaceID: workspaceID)

        #expect(
            publishedByWorkspaceID[workspaceID]?.chatSessions.map { $0.sessionID.rawValue } == ["pending-chat"]
        )

        runtime.prepareForRestore(title: "Codex Restore", subtitle: "Restoring")
        await flushObservationUpdates()

        #expect(publishedByWorkspaceID[workspaceID]?.chatSessions.first?.subtitle == "Restoring")
        #expect(publishedByWorkspaceID[workspaceID]?.chatSessions.first?.isBusy == true)

        let restoredSessionID = ChatSessionID(rawValue: "session-123")
        runtime.updateSessionIdentity(sessionID: restoredSessionID, descriptor: descriptor)
        await flushObservationUpdates()

        #expect(
            publishedByWorkspaceID[workspaceID]?.chatSessions.map { $0.sessionID.rawValue } == ["session-123"]
        )

        bridge.detachChatSession(runtime, workspaceID: workspaceID)

        #expect(publishedByWorkspaceID[workspaceID]?.chatSessions.isEmpty == true)
    }

    @Test("Bridge republishes browser summaries when the browser session URL changes")
    @MainActor
    func republishesBrowserSummariesForBrowserSessionChanges() async throws {
        let workspaceID = Workspace.ID("/tmp/devys-hosted-browser")
        let bridge = HostedWorkspaceContentBridge()
        var publishedByWorkspaceID: [Workspace.ID: HostedWorkspaceContentState] = [:]
        bridge.setPublishHandler { workspaceID, content in
            publishedByWorkspaceID[workspaceID] = content
        }

        let initialURL = try #require(URL(string: "http://localhost:3000"))
        let updatedURL = try #require(URL(string: "https://example.com/docs"))
        let session = BrowserSession(url: initialURL)

        bridge.attachBrowserSession(session, workspaceID: workspaceID)

        #expect(
            publishedByWorkspaceID[workspaceID]?.browserSessions.map(\.url.absoluteString)
            == ["http://localhost:3000"]
        )
        #expect(
            publishedByWorkspaceID[workspaceID]?.browserSessions.first?.title == "localhost"
        )

        session.load(url: updatedURL)
        await flushObservationUpdates()

        #expect(
            publishedByWorkspaceID[workspaceID]?.browserSessions.map(\.url.absoluteString)
            == ["https://example.com/docs"]
        )
        #expect(
            publishedByWorkspaceID[workspaceID]?.browserSessions.first?.title == "example.com"
        )

        bridge.detachBrowserSession(session, workspaceID: workspaceID)

        #expect(publishedByWorkspaceID[workspaceID]?.browserSessions.isEmpty == true)
    }
}

@MainActor
private func flushObservationUpdates() async {
    await Task.yield()
    await Task.yield()
}
