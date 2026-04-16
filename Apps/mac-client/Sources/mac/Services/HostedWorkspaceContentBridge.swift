import AppFeatures
import Foundation
import Observation
import Workspace

@MainActor
final class HostedWorkspaceContentBridge {
    typealias PublishHandler = @MainActor (Workspace.ID, HostedWorkspaceContentState) -> Void

    private struct EditorTracking {
        let workspaceID: Workspace.ID
        var referenceCount: Int
        var lastPublishedURL: URL?
    }

    private struct AgentTracking {
        let workspaceID: Workspace.ID
        var lastPublishedSessionID: AgentSessionID?
    }

    var publishHostedContent: PublishHandler?

    private var editorTrackingBySessionObjectID: [ObjectIdentifier: EditorTracking] = [:]
    private var editorSummariesByWorkspaceID: [Workspace.ID: [URL: HostedEditorDocumentSummary]] = [:]

    private var agentTrackingByRuntimeObjectID: [ObjectIdentifier: AgentTracking] = [:]
    private var agentSummariesByWorkspaceID: [Workspace.ID: [AgentSessionID: HostedAgentSessionSummary]] = [:]

    private var lastPublishedContentByWorkspaceID: [Workspace.ID: HostedWorkspaceContentState] = [:]

    func setPublishHandler(_ handler: PublishHandler?) {
        publishHostedContent = handler
        for workspaceID in publishedWorkspaceIDs {
            publishWorkspaceContent(for: workspaceID, force: true)
        }
    }

    func attachEditorSession(_ session: EditorSession, workspaceID: Workspace.ID) {
        let sessionObjectID = ObjectIdentifier(session)
        if var tracking = editorTrackingBySessionObjectID[sessionObjectID] {
            guard tracking.workspaceID == workspaceID else {
                detachEditorSession(session, workspaceID: tracking.workspaceID)
                attachEditorSession(session, workspaceID: workspaceID)
                return
            }
            tracking.referenceCount += 1
            editorTrackingBySessionObjectID[sessionObjectID] = tracking
            publishEditorSummary(for: session, sessionObjectID: sessionObjectID)
            return
        }

        editorTrackingBySessionObjectID[sessionObjectID] = EditorTracking(
            workspaceID: workspaceID,
            referenceCount: 1,
            lastPublishedURL: nil
        )
        publishEditorSummary(for: session, sessionObjectID: sessionObjectID)
        observeEditorSummary(for: session, sessionObjectID: sessionObjectID)
    }

    func detachEditorSession(_ session: EditorSession, workspaceID: Workspace.ID) {
        let sessionObjectID = ObjectIdentifier(session)
        guard var tracking = editorTrackingBySessionObjectID[sessionObjectID],
              tracking.workspaceID == workspaceID else {
            return
        }

        tracking.referenceCount -= 1
        guard tracking.referenceCount <= 0 else {
            editorTrackingBySessionObjectID[sessionObjectID] = tracking
            return
        }

        editorTrackingBySessionObjectID.removeValue(forKey: sessionObjectID)
        if let lastPublishedURL = tracking.lastPublishedURL {
            removeEditorSummary(url: lastPublishedURL, workspaceID: workspaceID)
        }
    }

    func attachAgentSession(_ runtime: AgentSessionRuntime, workspaceID: Workspace.ID) {
        let runtimeObjectID = ObjectIdentifier(runtime)
        if let tracking = agentTrackingByRuntimeObjectID[runtimeObjectID],
           tracking.workspaceID == workspaceID {
            publishAgentSummary(for: runtime, runtimeObjectID: runtimeObjectID)
            return
        }

        agentTrackingByRuntimeObjectID[runtimeObjectID] = AgentTracking(
            workspaceID: workspaceID,
            lastPublishedSessionID: nil
        )
        publishAgentSummary(for: runtime, runtimeObjectID: runtimeObjectID)
        observeAgentSummary(for: runtime, runtimeObjectID: runtimeObjectID)
    }

    func detachAgentSession(_ runtime: AgentSessionRuntime, workspaceID: Workspace.ID) {
        let runtimeObjectID = ObjectIdentifier(runtime)
        guard let tracking = agentTrackingByRuntimeObjectID.removeValue(forKey: runtimeObjectID),
              tracking.workspaceID == workspaceID else {
            return
        }

        if let lastPublishedSessionID = tracking.lastPublishedSessionID {
            removeAgentSummary(sessionID: lastPublishedSessionID, workspaceID: workspaceID)
        }
    }

    func discardWorkspace(_ workspaceID: Workspace.ID) {
        editorTrackingBySessionObjectID = editorTrackingBySessionObjectID.filter {
            $0.value.workspaceID != workspaceID
        }
        agentTrackingByRuntimeObjectID = agentTrackingByRuntimeObjectID.filter {
            $0.value.workspaceID != workspaceID
        }
        editorSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        agentSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        lastPublishedContentByWorkspaceID.removeValue(forKey: workspaceID)
        publishHostedContent?(workspaceID, HostedWorkspaceContentState())
    }
}

@MainActor
private extension HostedWorkspaceContentBridge {
    var publishedWorkspaceIDs: Set<Workspace.ID> {
        Set(editorSummariesByWorkspaceID.keys)
            .union(agentSummariesByWorkspaceID.keys)
            .union(lastPublishedContentByWorkspaceID.keys)
    }

    func observeEditorSummary(
        for session: EditorSession,
        sessionObjectID: ObjectIdentifier
    ) {
        withObservationTracking {
            _ = session.url
            _ = session.isDirty
            _ = session.isLoading
        } onChange: { [weak self, weak session] in
            Task { @MainActor in
                guard let self,
                      let session,
                      self.editorTrackingBySessionObjectID[sessionObjectID] != nil else {
                    return
                }
                self.publishEditorSummary(for: session, sessionObjectID: sessionObjectID)
                self.observeEditorSummary(for: session, sessionObjectID: sessionObjectID)
            }
        }
    }

    func observeAgentSummary(
        for runtime: AgentSessionRuntime,
        runtimeObjectID: ObjectIdentifier
    ) {
        withObservationTracking {
            _ = runtime.sessionID
            _ = runtime.tabTitle
            _ = runtime.tabIcon
            _ = runtime.tabSubtitle
            _ = runtime.tabIsBusy
            _ = runtime.createdAt
            _ = runtime.lastActivityAt
        } onChange: { [weak self, weak runtime] in
            Task { @MainActor in
                guard let self,
                      let runtime,
                      self.agentTrackingByRuntimeObjectID[runtimeObjectID] != nil else {
                    return
                }
                self.publishAgentSummary(for: runtime, runtimeObjectID: runtimeObjectID)
                self.observeAgentSummary(for: runtime, runtimeObjectID: runtimeObjectID)
            }
        }
    }

    func publishEditorSummary(
        for session: EditorSession,
        sessionObjectID: ObjectIdentifier
    ) {
        guard var tracking = editorTrackingBySessionObjectID[sessionObjectID] else { return }

        let summary = HostedEditorDocumentSummary(
            url: session.url,
            title: session.url.lastPathComponent,
            isDirty: session.isDirty,
            isLoading: session.isLoading
        )
        if let lastPublishedURL = tracking.lastPublishedURL,
           lastPublishedURL != summary.url {
            removeEditorSummary(url: lastPublishedURL, workspaceID: tracking.workspaceID, publish: false)
        }

        editorSummariesByWorkspaceID[tracking.workspaceID, default: [:]][summary.url] = summary
        tracking.lastPublishedURL = summary.url
        editorTrackingBySessionObjectID[sessionObjectID] = tracking
        publishWorkspaceContent(for: tracking.workspaceID)
    }

    func publishAgentSummary(
        for runtime: AgentSessionRuntime,
        runtimeObjectID: ObjectIdentifier
    ) {
        guard var tracking = agentTrackingByRuntimeObjectID[runtimeObjectID] else { return }

        let summary = HostedAgentSessionSummary(
            sessionID: runtime.sessionID,
            kind: runtime.descriptor.kind,
            title: runtime.tabTitle,
            icon: runtime.tabIcon,
            subtitle: runtime.tabSubtitle,
            isBusy: runtime.tabIsBusy,
            isRestorable: runtime.launchState == .connected,
            createdAt: runtime.createdAt,
            lastActivityAt: runtime.lastActivityAt
        )
        if let lastPublishedSessionID = tracking.lastPublishedSessionID,
           lastPublishedSessionID != summary.sessionID {
            removeAgentSummary(
                sessionID: lastPublishedSessionID,
                workspaceID: tracking.workspaceID,
                publish: false
            )
        }

        agentSummariesByWorkspaceID[tracking.workspaceID, default: [:]][summary.sessionID] = summary
        tracking.lastPublishedSessionID = summary.sessionID
        agentTrackingByRuntimeObjectID[runtimeObjectID] = tracking
        publishWorkspaceContent(for: tracking.workspaceID)
    }

    func removeEditorSummary(
        url: URL,
        workspaceID: Workspace.ID,
        publish: Bool = true
    ) {
        editorSummariesByWorkspaceID[workspaceID]?.removeValue(forKey: url.standardizedFileURL)
        if editorSummariesByWorkspaceID[workspaceID]?.isEmpty == true {
            editorSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        }
        if publish {
            publishWorkspaceContent(for: workspaceID)
        }
    }

    func removeAgentSummary(
        sessionID: AgentSessionID,
        workspaceID: Workspace.ID,
        publish: Bool = true
    ) {
        agentSummariesByWorkspaceID[workspaceID]?.removeValue(forKey: sessionID)
        if agentSummariesByWorkspaceID[workspaceID]?.isEmpty == true {
            agentSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        }
        if publish {
            publishWorkspaceContent(for: workspaceID)
        }
    }

    func publishWorkspaceContent(
        for workspaceID: Workspace.ID,
        force: Bool = false
    ) {
        let editorDocuments = editorSummariesByWorkspaceID[workspaceID]
            .map { Array($0.values) } ?? []
        let agentSessions = agentSummariesByWorkspaceID[workspaceID]
            .map { Array($0.values) } ?? []
        let nextContent = HostedWorkspaceContentState(
            editorDocuments: editorDocuments.sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            },
            agentSessions: agentSessions.sorted { lhs, rhs in
                if lhs.lastActivityAt == rhs.lastActivityAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
        )

        if !force, lastPublishedContentByWorkspaceID[workspaceID] == nextContent {
            return
        }

        lastPublishedContentByWorkspaceID[workspaceID] = nextContent
        publishHostedContent?(workspaceID, nextContent)
    }
}
