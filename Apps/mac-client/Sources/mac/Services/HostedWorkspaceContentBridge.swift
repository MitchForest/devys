import AppFeatures
import Browser
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

    private struct ChatTracking {
        let workspaceID: Workspace.ID
        var lastPublishedSessionID: ChatSessionID?
    }

    private struct BrowserTracking {
        let workspaceID: Workspace.ID
        var lastPublishedSessionID: UUID?
    }

    var publishHostedContent: PublishHandler?

    private var editorTrackingBySessionObjectID: [ObjectIdentifier: EditorTracking] = [:]
    private var editorSummariesByWorkspaceID: [Workspace.ID: [URL: HostedEditorDocumentSummary]] = [:]

    private var chatTrackingByRuntimeObjectID: [ObjectIdentifier: ChatTracking] = [:]
    private var chatSummariesByWorkspaceID: [Workspace.ID: [ChatSessionID: HostedChatSessionSummary]] = [:]

    private var browserTrackingBySessionObjectID: [ObjectIdentifier: BrowserTracking] = [:]
    private var browserSummariesByWorkspaceID: [Workspace.ID: [UUID: HostedBrowserSessionSummary]] = [:]

    private var lastPublishedContentByWorkspaceID: [Workspace.ID: HostedWorkspaceContentState] = [:]
    private var pendingPublishWorkspaceIDs: Set<Workspace.ID> = []
    private var forcedPublishWorkspaceIDs: Set<Workspace.ID> = []
    private var isPublishFlushScheduled = false

    func setPublishHandler(_ handler: PublishHandler?) {
        publishHostedContent = handler
        for workspaceID in publishedWorkspaceIDs {
            scheduleWorkspaceContentPublish(for: workspaceID, force: true)
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

    func attachChatSession(_ runtime: ChatSessionRuntime, workspaceID: Workspace.ID) {
        let runtimeObjectID = ObjectIdentifier(runtime)
        if let tracking = chatTrackingByRuntimeObjectID[runtimeObjectID],
           tracking.workspaceID == workspaceID {
            publishChatSummary(for: runtime, runtimeObjectID: runtimeObjectID)
            return
        }

        chatTrackingByRuntimeObjectID[runtimeObjectID] = ChatTracking(
            workspaceID: workspaceID,
            lastPublishedSessionID: nil
        )
        publishChatSummary(for: runtime, runtimeObjectID: runtimeObjectID)
        observeChatSummary(for: runtime, runtimeObjectID: runtimeObjectID)
    }

    func attachBrowserSession(_ session: BrowserSession, workspaceID: Workspace.ID) {
        let sessionObjectID = ObjectIdentifier(session)
        if let tracking = browserTrackingBySessionObjectID[sessionObjectID],
           tracking.workspaceID == workspaceID {
            publishBrowserSummary(for: session, sessionObjectID: sessionObjectID)
            return
        }

        browserTrackingBySessionObjectID[sessionObjectID] = BrowserTracking(
            workspaceID: workspaceID,
            lastPublishedSessionID: nil
        )
        publishBrowserSummary(for: session, sessionObjectID: sessionObjectID)
        observeBrowserSummary(for: session, sessionObjectID: sessionObjectID)
    }

    func detachChatSession(_ runtime: ChatSessionRuntime, workspaceID: Workspace.ID) {
        let runtimeObjectID = ObjectIdentifier(runtime)
        guard let tracking = chatTrackingByRuntimeObjectID.removeValue(forKey: runtimeObjectID),
              tracking.workspaceID == workspaceID else {
            return
        }

        if let lastPublishedSessionID = tracking.lastPublishedSessionID {
            removeChatSummary(sessionID: lastPublishedSessionID, workspaceID: workspaceID)
        }
    }

    func detachBrowserSession(_ session: BrowserSession, workspaceID: Workspace.ID) {
        let sessionObjectID = ObjectIdentifier(session)
        guard let tracking = browserTrackingBySessionObjectID.removeValue(forKey: sessionObjectID),
              tracking.workspaceID == workspaceID else {
            return
        }

        if let lastPublishedSessionID = tracking.lastPublishedSessionID {
            removeBrowserSummary(sessionID: lastPublishedSessionID, workspaceID: workspaceID)
        }
    }

    func discardWorkspace(_ workspaceID: Workspace.ID) {
        editorTrackingBySessionObjectID = editorTrackingBySessionObjectID.filter {
            $0.value.workspaceID != workspaceID
        }
        chatTrackingByRuntimeObjectID = chatTrackingByRuntimeObjectID.filter {
            $0.value.workspaceID != workspaceID
        }
        browserTrackingBySessionObjectID = browserTrackingBySessionObjectID.filter {
            $0.value.workspaceID != workspaceID
        }
        editorSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        chatSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        browserSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        lastPublishedContentByWorkspaceID.removeValue(forKey: workspaceID)
        scheduleWorkspaceContentPublish(for: workspaceID, force: true)
    }
}

@MainActor
private extension HostedWorkspaceContentBridge {
    var publishedWorkspaceIDs: Set<Workspace.ID> {
        Set(editorSummariesByWorkspaceID.keys)
            .union(chatSummariesByWorkspaceID.keys)
            .union(browserSummariesByWorkspaceID.keys)
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

    func observeChatSummary(
        for runtime: ChatSessionRuntime,
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
                      self.chatTrackingByRuntimeObjectID[runtimeObjectID] != nil else {
                    return
                }
                self.publishChatSummary(for: runtime, runtimeObjectID: runtimeObjectID)
                self.observeChatSummary(for: runtime, runtimeObjectID: runtimeObjectID)
            }
        }
    }

    func observeBrowserSummary(
        for session: BrowserSession,
        sessionObjectID: ObjectIdentifier
    ) {
        withObservationTracking {
            _ = session.url
            _ = session.tabTitle
        } onChange: { [weak self, weak session] in
            Task { @MainActor in
                guard let self,
                      let session,
                      self.browserTrackingBySessionObjectID[sessionObjectID] != nil else {
                    return
                }
                self.publishBrowserSummary(for: session, sessionObjectID: sessionObjectID)
                self.observeBrowserSummary(for: session, sessionObjectID: sessionObjectID)
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
        scheduleWorkspaceContentPublish(for: tracking.workspaceID)
    }

    func publishChatSummary(
        for runtime: ChatSessionRuntime,
        runtimeObjectID: ObjectIdentifier
    ) {
        guard var tracking = chatTrackingByRuntimeObjectID[runtimeObjectID] else { return }

        let summary = HostedChatSessionSummary(
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
            removeChatSummary(
                sessionID: lastPublishedSessionID,
                workspaceID: tracking.workspaceID,
                publish: false
            )
        }

        chatSummariesByWorkspaceID[tracking.workspaceID, default: [:]][summary.sessionID] = summary
        tracking.lastPublishedSessionID = summary.sessionID
        chatTrackingByRuntimeObjectID[runtimeObjectID] = tracking
        scheduleWorkspaceContentPublish(for: tracking.workspaceID)
    }

    func publishBrowserSummary(
        for session: BrowserSession,
        sessionObjectID: ObjectIdentifier
    ) {
        guard var tracking = browserTrackingBySessionObjectID[sessionObjectID] else { return }

        let summary = HostedBrowserSessionSummary(
            sessionID: session.id,
            url: session.url,
            title: session.tabTitle,
            icon: session.tabIcon
        )
        if let lastPublishedSessionID = tracking.lastPublishedSessionID,
           lastPublishedSessionID != summary.sessionID {
            removeBrowserSummary(
                sessionID: lastPublishedSessionID,
                workspaceID: tracking.workspaceID,
                publish: false
            )
        }

        browserSummariesByWorkspaceID[tracking.workspaceID, default: [:]][summary.sessionID] = summary
        tracking.lastPublishedSessionID = summary.sessionID
        browserTrackingBySessionObjectID[sessionObjectID] = tracking
        scheduleWorkspaceContentPublish(for: tracking.workspaceID)
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
            scheduleWorkspaceContentPublish(for: workspaceID)
        }
    }

    func removeChatSummary(
        sessionID: ChatSessionID,
        workspaceID: Workspace.ID,
        publish: Bool = true
    ) {
        chatSummariesByWorkspaceID[workspaceID]?.removeValue(forKey: sessionID)
        if chatSummariesByWorkspaceID[workspaceID]?.isEmpty == true {
            chatSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        }
        if publish {
            scheduleWorkspaceContentPublish(for: workspaceID)
        }
    }

    func removeBrowserSummary(
        sessionID: UUID,
        workspaceID: Workspace.ID,
        publish: Bool = true
    ) {
        browserSummariesByWorkspaceID[workspaceID]?.removeValue(forKey: sessionID)
        if browserSummariesByWorkspaceID[workspaceID]?.isEmpty == true {
            browserSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        }
        if publish {
            scheduleWorkspaceContentPublish(for: workspaceID)
        }
    }

    func scheduleWorkspaceContentPublish(
        for workspaceID: Workspace.ID,
        force: Bool = false
    ) {
        pendingPublishWorkspaceIDs.insert(workspaceID)
        if force {
            forcedPublishWorkspaceIDs.insert(workspaceID)
        }
        guard !isPublishFlushScheduled else { return }
        isPublishFlushScheduled = true

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.flushPendingWorkspaceContentPublishes()
        }
    }

    func flushPendingWorkspaceContentPublishes() {
        isPublishFlushScheduled = false
        let workspaceIDs = pendingPublishWorkspaceIDs
        let forcedWorkspaceIDs = forcedPublishWorkspaceIDs
        pendingPublishWorkspaceIDs.removeAll()
        forcedPublishWorkspaceIDs.removeAll()

        for workspaceID in workspaceIDs {
            publishWorkspaceContentImmediately(
                for: workspaceID,
                force: forcedWorkspaceIDs.contains(workspaceID)
            )
        }
    }

    func publishWorkspaceContentImmediately(
        for workspaceID: Workspace.ID,
        force: Bool = false
    ) {
        let editorDocuments = editorSummariesByWorkspaceID[workspaceID]
            .map { Array($0.values) } ?? []
        let chatSessions = chatSummariesByWorkspaceID[workspaceID]
            .map { Array($0.values) } ?? []
        let browserSessions = browserSummariesByWorkspaceID[workspaceID]
            .map { Array($0.values) } ?? []
        let nextContent = HostedWorkspaceContentState(
            editorDocuments: editorDocuments.sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            },
            browserSessions: browserSessions.sorted { lhs, rhs in
                let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
                if titleComparison == .orderedSame {
                    return lhs.url.absoluteString.localizedStandardCompare(rhs.url.absoluteString)
                        == .orderedAscending
                }
                return titleComparison == .orderedAscending
            },
            chatSessions: chatSessions.sorted { lhs, rhs in
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
        guard let publishHostedContent else { return }
        publishHostedContent(workspaceID, nextContent)
    }
}
