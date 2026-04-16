import ACPClientKit
import AppFeatures
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

    @Test("Bridge republishes agent summaries when session identity and presentation change")
    @MainActor
    func republishesAgentSummariesForAgentRuntimeChanges() async {
        let workspaceID = Workspace.ID("/tmp/devys-hosted-agent")
        let descriptor = ACPAgentDescriptor.descriptor(for: .codex)
        let runtime = AgentSessionRuntime(
            workspaceID: workspaceID,
            sessionID: AgentSessionID(rawValue: "pending-agent"),
            descriptor: descriptor
        )
        let bridge = HostedWorkspaceContentBridge()
        var publishedByWorkspaceID: [Workspace.ID: HostedWorkspaceContentState] = [:]
        bridge.setPublishHandler { workspaceID, content in
            publishedByWorkspaceID[workspaceID] = content
        }

        bridge.attachAgentSession(runtime, workspaceID: workspaceID)

        #expect(
            publishedByWorkspaceID[workspaceID]?.agentSessions.map { $0.sessionID.rawValue } == ["pending-agent"]
        )

        runtime.prepareForRestore(title: "Codex Restore", subtitle: "Restoring")
        await flushObservationUpdates()

        #expect(publishedByWorkspaceID[workspaceID]?.agentSessions.first?.subtitle == "Restoring")
        #expect(publishedByWorkspaceID[workspaceID]?.agentSessions.first?.isBusy == true)

        let restoredSessionID = AgentSessionID(rawValue: "session-123")
        runtime.updateSessionIdentity(sessionID: restoredSessionID, descriptor: descriptor)
        await flushObservationUpdates()

        #expect(
            publishedByWorkspaceID[workspaceID]?.agentSessions.map { $0.sessionID.rawValue } == ["session-123"]
        )

        bridge.detachAgentSession(runtime, workspaceID: workspaceID)

        #expect(publishedByWorkspaceID[workspaceID]?.agentSessions.isEmpty == true)
    }
}

@MainActor
private func flushObservationUpdates() async {
    await Task.yield()
    await Task.yield()
}
