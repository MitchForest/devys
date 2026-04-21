// ContentView+TabClosing.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import AppFeatures
import UniformTypeIdentifiers
@preconcurrency import Split
import Workspace

@MainActor
final class DevysSplitCloseDelegate: DevysSplitDelegate {
    // Callbacks for original Bonsplit methods
    var onShouldCloseTab: ((Tab, PaneID) -> Bool)?
    var onDidCloseTab: ((TabID, PaneID) -> Void)?
    var onDidCreateTab: ((Tab, PaneID) -> Void)?
    var onDidSelectTab: ((Tab, PaneID) -> Void)?
    var onDidRequestGestureIntent: ((SplitGestureIntent) -> Bool)?
    var onDidFocusPane: ((PaneID) -> Void)?
    var onDidResizeSplit: ((UUID, Double) -> Void)?
    var onDidReceiveDrop: ((DropContent, PaneID, DropZone) -> TabID?)?
    var onShouldAcceptDrop: (([UTType], PaneID) -> Bool)?

    // MARK: - Original Bonsplit delegate methods (splitTabBar prefix)
    
    nonisolated func splitTabBar(
        _ _: DevysSplitController,
        shouldCloseTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool {
        MainActor.assumeIsolated {
            onShouldCloseTab?(tab, pane) ?? true
        }
    }

    nonisolated func splitTabBar(
        _ _: DevysSplitController,
        didCloseTab tabId: TabID,
        fromPane pane: PaneID
    ) {
        MainActor.assumeIsolated {
            onDidCloseTab?(tabId, pane)
        }
    }
    
    nonisolated func splitTabBar(
        _ _: DevysSplitController,
        didCreateTab tab: Tab,
        inPane pane: PaneID
    ) {
        MainActor.assumeIsolated {
            onDidCreateTab?(tab, pane)
        }
    }

    nonisolated func splitTabBar(
        _ _: DevysSplitController,
        didSelectTab tab: Tab,
        inPane pane: PaneID
    ) {
        MainActor.assumeIsolated {
            onDidSelectTab?(tab, pane)
        }
    }

    nonisolated func splitTabBar(
        _ _: DevysSplitController,
        didFocusPane pane: PaneID
    ) {
        MainActor.assumeIsolated {
            onDidFocusPane?(pane)
        }
    }
    
    nonisolated func splitView(
        _ _: DevysSplitController,
        didReceiveDrop content: DropContent,
        inPane pane: PaneID,
        zone: DropZone
    ) -> TabID? {
        MainActor.assumeIsolated {
            onDidReceiveDrop?(content, pane, zone)
        }
    }
    
    nonisolated func splitView(
        _ _: DevysSplitController,
        shouldAcceptDrop types: [UTType],
        inPane pane: PaneID
    ) -> Bool {
        MainActor.assumeIsolated {
            onShouldAcceptDrop?(types, pane) ?? true
        }
    }

    nonisolated func splitView(
        _ _: DevysSplitController,
        didResizeSplit splitID: UUID,
        position: Double
    ) {
        MainActor.assumeIsolated {
            onDidResizeSplit?(splitID, position)
        }
    }

    nonisolated func splitView(
        _ _: DevysSplitController,
        didRequest intent: SplitGestureIntent
    ) -> Bool {
        MainActor.assumeIsolated {
            onDidRequestGestureIntent?(intent) ?? false
        }
    }
}

@MainActor
extension ContentView {
    func configureSplitDelegate() {
        splitDelegate.onShouldCloseTab = { tab, paneId in
            handleTabCloseRequest(tab: tab, paneId: paneId)
        }
        splitDelegate.onDidCloseTab = { tabId, paneId in
            handleTabDidClose(tabId, paneId: paneId)
        }
        splitDelegate.onDidCreateTab = { _, _ in
            syncTabMetadataFromSessions()
        }
        splitDelegate.onDidReceiveDrop = { content, paneId, zone in
            handleExternalDrop(content: content, inPane: paneId, zone: zone)
        }
        splitDelegate.onShouldAcceptDrop = { types, _ in
            types.contains(.fileURL)
                || types.contains(.devysGitDiff)
        }
        configureSplitObservationCallbacks()
        controller.delegate = splitDelegate

        // Set initial colors from theme
        controller.updateColors(Self.makeSplitColors(from: theme))
    }

    private func configureSplitObservationCallbacks() {
        splitDelegate.onDidSelectTab = { tab, _ in
            selectTab(tab.id)
        }
        splitDelegate.onDidRequestGestureIntent = { intent in
            handleSplitGestureIntent(intent)
        }
        splitDelegate.onDidFocusPane = { pane in
            guard let workspaceID = selectedWorkspaceID else { return }
            store.send(.setWorkspaceFocusedPaneID(workspaceID: workspaceID, paneID: pane))
        }
        splitDelegate.onDidResizeSplit = { splitID, position in
            guard let workspaceID = selectedWorkspaceID else { return }
            store.send(
                .setWorkspaceSplitDividerPosition(
                    workspaceID: workspaceID,
                    splitID: splitID,
                    position: position
                )
            )
        }
    }
    
    /// Handle external content dropped onto a pane
    private func handleExternalDrop(content: DropContent, inPane paneId: PaneID, zone: DropZone) -> TabID? {
        switch content {
        case .files(let urls):
            return handleFileDrop(urls: urls, inPane: paneId, zone: zone)
            
        case .custom(let utType, let data):
            if utType == .devysGitDiff {
                return handleGitDiffDrop(data: data, inPane: paneId, zone: zone)
            }
            return nil
            
        case .tab:
            // Internal tab moves are handled by DevysSplit
            return nil
        }
    }
    
    /// Create an editor tab from a dropped file
    private func openEditorTabFromDrop(url: URL, inPane paneId: PaneID) -> TabID? {
        guard let workspaceID = selectedWorkspaceID else { return nil }
        let content = WorkspaceTabContent.editor(workspaceID: workspaceID, url: url)
        
        // Check if already open
        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return existingTabId
        }
        
        return createTab(in: paneId, content: content)
    }

    private func handleFileDrop(
        urls: [URL],
        inPane paneId: PaneID,
        zone: DropZone
    ) -> TabID? {
        guard let firstURL = urls.first else { return nil }
        let attachments = urls.map(agentAttachment(from:))

        if let chatTabID = handleChatFileDrop(
            attachments: attachments,
            inPane: paneId,
            zone: zone
        ) {
            return chatTabID
        }

        if case let .edge(orientation, insertion) = zone,
           let workspaceID = selectedWorkspaceID {
            return handleEdgeFileDrop(
                attachments: attachments,
                sourcePaneID: paneId,
                workspaceID: workspaceID,
                orientation: orientation,
                insertion: insertion
            )
        }

        return openEditorTabFromDrop(url: firstURL, inPane: paneId)
    }

    private func handleChatFileDrop(
        attachments: [ChatAttachment],
        inPane paneID: PaneID,
        zone: DropZone
    ) -> TabID? {
        guard let chatTabID = selectedChatTabID(inPane: paneID) else {
            return nil
        }

        if case .chatSession(let workspaceID, let sessionID)? = tabContents[chatTabID],
           let session = runtimeRegistry.chatSession(id: sessionID, in: workspaceID) {
            session.addAttachments(attachments)
        }

        if case let .edge(orientation, insertion) = zone {
            splitSelectedTabIfNeeded(
                chatTabID,
                from: paneID,
                orientation: orientation,
                insertion: insertion
            )
        }

        return chatTabID
    }

    private func handleEdgeFileDrop(
        attachments: [ChatAttachment],
        sourcePaneID: PaneID,
        workspaceID: Workspace.ID,
        orientation: Split.SplitOrientation,
        insertion: SplitInsertionPosition
    ) -> TabID? {
        guard let targetPaneID = splitPane(
            sourcePaneID,
            orientation: orientation,
            insertion: insertion.windowInsertionPosition,
            workspaceID: workspaceID
        ) else {
            return nil
        }

        if let configuredHarness = appSettings.chat.defaultHarness,
           let kind = chatProviderKind(forHarness: configuredHarness),
           let prepared = preparePendingChatSessionLaunch(
                workspaceID: workspaceID,
                preferredPaneID: targetPaneID,
                initialAttachments: attachments,
                preferredKind: kind
           ) {
            launchPreparedChatSession(
                kind,
                workspaceID: workspaceID,
                sessionID: prepared.runtime.sessionID
            )
            return prepared.tabID
        }

        if let prepared = preparePendingChatSessionLaunch(
            workspaceID: workspaceID,
            preferredPaneID: targetPaneID,
            initialAttachments: attachments,
            preferredKind: nil
        ) {
            store.send(.setChatLaunchPresentation(ChatLaunchPresentation(
                workspaceID: workspaceID,
                initialAttachments: [],
                preferredPaneID: targetPaneID,
                pendingSessionID: prepared.runtime.sessionID,
                pendingTabID: prepared.tabID
            )))
            return prepared.tabID
        }

        store.send(.closeWorkspacePane(workspaceID: workspaceID, paneID: targetPaneID))
        renderWorkspaceLayout(for: workspaceID)
        return nil
    }
    
    // Handle a git diff dropped from the sidebar.
    // swiftlint:disable:next function_body_length
    private func handleGitDiffDrop(
        data: Data,
        inPane paneId: PaneID,
        zone: DropZone
    ) -> TabID? {
        // Decode the GitDiffTransfer from the data
        guard let transfer = try? JSONDecoder().decode(GitDiffTransfer.self, from: data) else {
            return nil
        }
        guard let workspaceID = selectedWorkspaceID else { return nil }

        if case let .edge(orientation, insertion) = zone,
           let chatTabID = selectedChatTabID(inPane: paneId),
           case .chatSession(_, let sessionID)? = tabContents[chatTabID],
           let session = runtimeRegistry.chatSession(id: sessionID, in: workspaceID) {
            session.addAttachment(.gitDiff(path: transfer.path, isStaged: transfer.isStaged))
            splitSelectedTabIfNeeded(
                chatTabID,
                from: paneId,
                orientation: orientation,
                insertion: insertion
            )
            return chatTabID
        }

        if let chatTabID = selectedChatTabID(inPane: paneId),
           case .chatSession(_, let sessionID)? = tabContents[chatTabID],
           let session = runtimeRegistry.chatSession(id: sessionID, in: workspaceID) {
            session.addAttachment(.gitDiff(path: transfer.path, isStaged: transfer.isStaged))
            return chatTabID
        }

        if case let .edge(orientation, insertion) = zone {
            let attachment = ChatAttachment.gitDiff(path: transfer.path, isStaged: transfer.isStaged)
            guard let targetPaneID = splitPane(
                paneId,
                orientation: orientation,
                insertion: insertion.windowInsertionPosition,
                workspaceID: workspaceID
            ) else {
                return nil
            }
            if let configuredHarness = appSettings.chat.defaultHarness,
               let kind = chatProviderKind(forHarness: configuredHarness),
               let prepared = preparePendingChatSessionLaunch(
                    workspaceID: workspaceID,
                    preferredPaneID: targetPaneID,
                    initialAttachments: [attachment],
                    preferredKind: kind
               ) {
                launchPreparedChatSession(
                    kind,
                    workspaceID: workspaceID,
                    sessionID: prepared.runtime.sessionID
                )
                return prepared.tabID
            }

            if let prepared = preparePendingChatSessionLaunch(
                workspaceID: workspaceID,
                preferredPaneID: targetPaneID,
                initialAttachments: [attachment],
                preferredKind: nil
            ) {
                store.send(.setChatLaunchPresentation(ChatLaunchPresentation(
                    workspaceID: workspaceID,
                    initialAttachments: [],
                    preferredPaneID: targetPaneID,
                    pendingSessionID: prepared.runtime.sessionID,
                    pendingTabID: prepared.tabID
                )))
                return prepared.tabID
            }
            store.send(.closeWorkspacePane(workspaceID: workspaceID, paneID: targetPaneID))
            renderWorkspaceLayout(for: workspaceID)
            return nil
        }

        let content = WorkspaceTabContent.gitDiff(
            workspaceID: workspaceID,
            path: transfer.path,
            isStaged: transfer.isStaged
        )
        
        // Check if already open
        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return existingTabId
        }
        
        return createTab(in: paneId, content: content)
    }

    private func selectedChatTabID(inPane paneId: PaneID) -> TabID? {
        guard let selectedTabID = paneLayout(for: paneId)?.selectedTabID,
              case .chatSession = tabContents[selectedTabID] else {
            return nil
        }
        return selectedTabID
    }

    private func splitSelectedTabIfNeeded(
        _ tabID: TabID,
        from paneID: PaneID,
        orientation: Split.SplitOrientation,
        insertion: SplitInsertionPosition
    ) {
        guard let sourceIndex = paneLayout(for: paneID)?.tabIDs.firstIndex(of: tabID) else {
            return
        }
        _ = splitTab(
            tabID,
            from: paneID,
            sourceIndex: sourceIndex,
            into: paneID,
            orientation: orientation,
            insertion: insertion.windowInsertionPosition
        )
    }

    private func agentAttachment(from url: URL) -> ChatAttachment {
        let type = UTType(filenameExtension: url.pathExtension)
        if let type, type.conforms(to: .image) {
            return .image(url: url)
        }
        return .file(url: url)
    }

    private func handleTabCloseRequest(tab: Tab, paneId: PaneID) -> Bool {
        if closeBypass.contains(tab.id) {
            closeBypass.remove(tab.id)
            return true
        }
        
        if closeInFlight.contains(tab.id) {
            return false
        }

        guard let content = tabContents[tab.id],
              let request = workspaceTabCloseRequest(
                tabID: tab.id,
                paneID: paneId,
                content: content
              ) else {
            return true
        }

        switch request.strategy {
        case .closeImmediately:
            return true

        case .confirmDirtyEditor(let fileName):
            guard let session = editorSessions[tab.id] else { return false }
            let response = showSaveDialog(fileName: fileName)
            switch response {
            case .alertFirstButtonReturn:
                closeInFlight.insert(tab.id)
                saveAndClose(tabId: tab.id, paneId: paneId, session: session)
                return false
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
    }

    private func workspaceTabCloseRequest(
        tabID: TabID,
        paneID: PaneID,
        content: WorkspaceTabContent
    ) -> WindowFeature.WorkspaceTabCloseRequest? {
        let context = WindowFeature.WorkspaceTabCloseContext(
            tabID: tabID,
            paneID: paneID,
            content: content,
            isDirtyEditor: editorSessions[tabID]?.isDirty == true
        )
        store.send(.requestWorkspaceTabClose(context))
        let request = store.workspaceTabCloseRequest
        store.send(.setWorkspaceTabCloseRequest(nil))
        return request
    }

    private func saveAndClose(tabId: TabID, paneId: PaneID, session: EditorSession) {
        Task { @MainActor in
            do {
                try await session.save()
                closeInFlight.remove(tabId)
                closeBypass.insert(tabId)
                closeTab(tabId, in: paneId)
            } catch {
                closeInFlight.remove(tabId)
                showErrorAlert(title: "Save Failed", message: error.localizedDescription)
            }
        }
    }

    private func handleTabDidClose(_ id: TabID, paneId: PaneID) {
        guard let closedTab = workspaceTabRecord(for: id) else { return }
        let workspaceID = closedTab.workspaceID
        let content = closedTab.content
        let wasPreview = paneID(for: id, workspaceID: workspaceID)
            .flatMap { paneID in
                store.workspaceShells[workspaceID]?.layout?.paneLayout(for: paneID)?.previewTabID
            } == id
        store.send(.closeWorkspaceTab(workspaceID: workspaceID, paneID: paneId, tabID: id))
        removeTabState(id: id, content: content, wasPreview: wasPreview)
        renderWorkspaceLayout(for: workspaceID)
    }

    private func workspaceTabRecord(
        for tabID: TabID
    ) -> (workspaceID: Workspace.ID, content: WorkspaceTabContent)? {
        for (workspaceID, shell) in store.workspaceShells {
            if let content = shell.tabContents[tabID] {
                return (workspaceID, content)
            }
        }
        return nil
    }

    /// Removes all state associated with a tab ID
    private func removeTabState(id: TabID, content: WorkspaceTabContent, wasPreview: Bool) {
        tabPresentationById.removeValue(forKey: id)
        removeTabContent(for: id, content: content)

        if wasPreview {
            clearPreviewTabID(id, workspaceID: content.workspaceID)
        }

        cleanupSession(for: content, tabId: id)
    }

    /// Shows save/don't save/cancel dialog
    private func showSaveDialog(fileName: String) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to \"\(fileName)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }
    
    /// Shows an error alert
    private func showErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
