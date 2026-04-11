// ContentView+TabClosing.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import UniformTypeIdentifiers
@preconcurrency import Split
import Workspace

@MainActor
final class DevysSplitCloseDelegate: DevysSplitDelegate {
    // Callbacks for original Bonsplit methods
    var onShouldCloseTab: ((Tab, PaneID) -> Bool)?
    var onDidCloseTab: ((TabID, PaneID) -> Void)?
    var onDidCreateTab: ((Tab, PaneID) -> Void)?
    
    // Callbacks for new DevysSplit extensions
    var onWelcomeTabForPane: ((PaneID) -> Tab?)?
    var onIsWelcomeTab: ((TabID, PaneID) -> Bool)?
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
    
    // MARK: - New DevysSplit extension methods (splitView prefix)
    
    nonisolated func splitView(
        _ _: DevysSplitController,
        welcomeTabForPane pane: PaneID
    ) -> Tab? {
        MainActor.assumeIsolated {
            onWelcomeTabForPane?(pane)
        }
    }
    
    nonisolated func splitView(
        _ _: DevysSplitController,
        isWelcomeTab tabId: TabID,
        inPane pane: PaneID
    ) -> Bool {
        MainActor.assumeIsolated {
            onIsWelcomeTab?(tabId, pane) ?? false
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
}

@MainActor
extension ContentView {
    func configureSplitDelegate() {
        splitDelegate.onShouldCloseTab = { tab, paneId in
            handleTabCloseRequest(tab: tab, paneId: paneId)
        }
        splitDelegate.onDidCloseTab = { tabId, _ in
            handleTabDidClose(tabId)
        }
        splitDelegate.onDidCreateTab = { tab, _ in
            // Track welcome tabs when they're created by the controller
            // Check if this is a welcome tab by checking if we don't already have content for it
            if tabContents[tab.id] == nil && tab.title == "Welcome" {
                tabContents[tab.id] = .welcome
            }
        }
        splitDelegate.onWelcomeTabForPane = { _ in
            // Return welcome tab metadata
            Tab(title: "Welcome", icon: "hand.wave", isDirty: false)
        }
        splitDelegate.onIsWelcomeTab = { tabId, _ in
            // Check if this is a welcome tab by content type
            guard let content = tabContents[tabId] else { return false }
            return content == .welcome
        }
        splitDelegate.onDidReceiveDrop = { content, paneId, zone in
            handleExternalDrop(content: content, inPane: paneId, zone: zone)
        }
        splitDelegate.onShouldAcceptDrop = { types, _ in
            types.contains(.fileURL)
                || types.contains(.devysGitDiff)
        }
        controller.delegate = splitDelegate
        
        // Set initial colors from theme
        controller.updateColors(splitColorsFromTheme(themeManager.theme))
        
        // Populate content for existing welcome tabs created before delegate was set.
        // The initial welcome tab is created during controller initialization (before onAppear),
        // so onDidCreateTab callback never fires for it. We retroactively register it here.
        for tabId in controller.allTabIds {
            if tabContents[tabId] == nil,
               let tab = controller.tab(tabId),
               tab.title == "Welcome" {
                tabContents[tabId] = .welcome
            }
        }
    }
    
    /// Handle external content dropped onto a pane
    private func handleExternalDrop(content: DropContent, inPane paneId: PaneID, zone: DropZone) -> TabID? {
        // DevysSplit owns zone-specific placement (including edge split behavior).
        // The delegate only creates content in the provided pane and returns the tab.
        let targetPaneId = paneId

        switch content {
        case .files(let urls):
            return handleFileDrop(urls: urls, inPane: targetPaneId, zone: zone)
            
        case .custom(let utType, let data):
            if utType == .devysGitDiff {
                return handleGitDiffDrop(data: data, inPane: targetPaneId, zone: zone)
            }
            return nil
            
        case .tab:
            // Internal tab moves are handled by DevysSplit
            return nil
        }
    }
    
    /// Create an editor tab from a dropped file
    private func openEditorTabFromDrop(url: URL, inPane paneId: PaneID) -> TabID? {
        guard let workspaceID = workspaceCatalog.selectedWorkspaceID else { return nil }
        let content = TabContent.editor(workspaceID: workspaceID, url: url)
        
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

        if let agentTabID = selectedAgentTabID(inPane: paneId) {
            let attachments = urls.map(agentAttachment(from:))
            if case .agentSession(let workspaceID, let sessionID)? = tabContents[agentTabID],
               let session = runtimeRegistry
                .runtimeHandle(for: workspaceID)?
                .agentRuntimeRegistry
                .session(id: sessionID) {
                session.addAttachments(attachments)
            }
            return agentTabID
        }

        if case .edge = zone,
           let workspaceID = workspaceCatalog.selectedWorkspaceID {
            let attachments = urls.map(agentAttachment(from:))
            if let configuredHarness = appSettings.agent.defaultHarness,
               let kind = agentKind(forHarness: configuredHarness),
               let prepared = preparePendingAgentSessionLaunch(
                    workspaceID: workspaceID,
                    preferredPaneID: paneId,
                    initialAttachments: attachments,
                    preferredKind: kind
               ) {
                launchPreparedAgentSession(
                    kind,
                    workspaceID: workspaceID,
                    sessionID: prepared.runtime.sessionID
                )
                return prepared.tabID
            }

            if let prepared = preparePendingAgentSessionLaunch(
                workspaceID: workspaceID,
                preferredPaneID: paneId,
                initialAttachments: attachments,
                preferredKind: nil
            ) {
                agentLaunchRequest = AgentLaunchPresentationRequest(
                    workspaceID: workspaceID,
                    initialAttachments: [],
                    preferredPaneID: paneId,
                    pendingSessionID: prepared.runtime.sessionID,
                    pendingTabID: prepared.tabID
                )
                return prepared.tabID
            }
            return nil
        }

        return openEditorTabFromDrop(url: firstURL, inPane: paneId)
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
        guard let workspaceID = workspaceCatalog.selectedWorkspaceID else { return nil }

        if let agentTabID = selectedAgentTabID(inPane: paneId),
           case .agentSession(_, let sessionID)? = tabContents[agentTabID],
           let session = runtimeRegistry.runtimeHandle(for: workspaceID)?.agentRuntimeRegistry.session(id: sessionID) {
            session.addAttachment(.gitDiff(path: transfer.path, isStaged: transfer.isStaged))
            return agentTabID
        }

        if case .edge = zone {
            let attachment = AgentAttachment.gitDiff(path: transfer.path, isStaged: transfer.isStaged)
            if let configuredHarness = appSettings.agent.defaultHarness,
               let kind = agentKind(forHarness: configuredHarness),
               let prepared = preparePendingAgentSessionLaunch(
                    workspaceID: workspaceID,
                    preferredPaneID: paneId,
                    initialAttachments: [attachment],
                    preferredKind: kind
               ) {
                launchPreparedAgentSession(
                    kind,
                    workspaceID: workspaceID,
                    sessionID: prepared.runtime.sessionID
                )
                return prepared.tabID
            }

            if let prepared = preparePendingAgentSessionLaunch(
                workspaceID: workspaceID,
                preferredPaneID: paneId,
                initialAttachments: [attachment],
                preferredKind: nil
            ) {
                agentLaunchRequest = AgentLaunchPresentationRequest(
                    workspaceID: workspaceID,
                    initialAttachments: [],
                    preferredPaneID: paneId,
                    pendingSessionID: prepared.runtime.sessionID,
                    pendingTabID: prepared.tabID
                )
                return prepared.tabID
            }
            return nil
        }

        let content = TabContent.gitDiff(
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

    private func selectedAgentTabID(inPane paneId: PaneID) -> TabID? {
        guard let selectedTab = controller.selectedTab(inPane: paneId),
              case .agentSession = tabContents[selectedTab.id] else {
            return nil
        }
        return selectedTab.id
    }

    private func agentAttachment(from url: URL) -> AgentAttachment {
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

        guard let content = tabContents[tab.id] else { return true }
        guard case .editor = content,
              let session = editorSessions[tab.id],
              session.isDirty else {
            return true
        }

        let response = showSaveDialog(fileName: content.fallbackTitle)
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

    private func saveAndClose(tabId: TabID, paneId: PaneID, session: EditorSession) {
        Task { @MainActor in
            do {
                try await session.save()
                closeInFlight.remove(tabId)
                closeBypass.insert(tabId)
                _ = controller.closeTab(tabId, inPane: paneId)
            } catch {
                closeInFlight.remove(tabId)
                showErrorAlert(title: "Save Failed", message: error.localizedDescription)
            }
        }
    }

    private func handleTabDidClose(_ id: TabID) {
        guard let content = tabContents[id] else { return }
        let wasPreview = previewTabId == id
        removeTabState(id: id, content: content, wasPreview: wasPreview)
    }

    /// Removes all state associated with a tab ID
    private func removeTabState(id: TabID, content: TabContent, wasPreview: Bool) {
        tabContents.removeValue(forKey: id)

        if wasPreview {
            previewTabId = nil
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
