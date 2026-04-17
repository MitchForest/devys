// ContentView+Tabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import AppKit
import Foundation
import Split
import Workspace

extension ContentView {
    private enum WorkspaceContentOpenDisposition {
        case existing
        case promotedPreview
        case reusedPreview
        case created
    }

    private struct BrowserPaneDestination {
        let paneID: PaneID
        let tabID: TabID
        let browserID: UUID
        let initialURL: URL
    }

    func selectTab(_ tabId: TabID) {
        guard let workspaceID = selectedWorkspaceID,
              let paneID = paneID(for: tabId, workspaceID: workspaceID) else {
            return
        }
        store.send(.selectWorkspaceTab(workspaceID: workspaceID, paneID: paneID, tabID: tabId))
        renderWorkspaceLayout(for: workspaceID)
        applyHostSelectionEffects(for: tabId)
    }
    
    func tabMetadata(for content: WorkspaceTabContent) -> (title: String, icon: String) {
        var title = content.fallbackTitle
        var icon = content.fallbackIcon
        switch content {
        case .terminal(let workspaceID, let id):
            if let session = workspaceTerminalRegistry.session(id: id, in: workspaceID) {
                title = session.tabTitle
                icon = session.tabIcon
            }
            if let binding = workflowTerminalBinding(terminalID: id, workspaceID: workspaceID) {
                title = binding.nodeTitle
                icon = binding.isActive ? "point.3.connected.trianglepath.dotted" : icon
            }
        case .browser(let workspaceID, let id, _):
            if let session = browserRegistry.session(id: id, in: workspaceID) {
                title = session.tabTitle
                icon = session.tabIcon
            }
        case .agentSession(let workspaceID, let sessionID):
            if let session = runtimeRegistry.agentSession(id: sessionID, in: workspaceID) {
                title = session.tabTitle
                icon = session.tabIcon
            }
        case .workflowDefinition(let workspaceID, let definitionID):
            if let definition = workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
            ) {
                title = definition.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? content.fallbackTitle
                    : definition.name
            }
        case .workflowRun(let workspaceID, let runID):
            if let run = workflowRun(workspaceID: workspaceID, runID: runID) {
                title = run.currentPhaseTitle
                    ?? workflowDefinition(
                        workspaceID: workspaceID,
                        definitionID: run.definitionID
                    )?.node(id: run.currentNodeID ?? "")?.displayTitle
                    ?? definitionTitleForRun(run, workspaceID: workspaceID)
                icon = run.status.isActive ? "play.circle.fill" : content.fallbackIcon
            }
        default:
            title = content.fallbackTitle
            icon = content.fallbackIcon
        }
        return (title, icon)
    }

    private func definitionTitleForRun(
        _ run: WorkflowRun,
        workspaceID: Workspace.ID
    ) -> String {
        workflowDefinition(
            workspaceID: workspaceID,
            definitionID: run.definitionID
        )?.name ?? "Workflow Run"
    }

    func tabActivityIndicator() -> TabActivityIndicator? {
        nil
    }

    func openInPreviewTab(content: WorkspaceTabContent) {
        let trace = performanceTrace(for: content, action: "tab-open-preview")
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }
        let result = openWorkspaceContent(
            content,
            mode: .preview
        )

        if case .editor(_, let url) = content,
           let tabId = result.tabID,
           result.disposition != .existing {
            beginEditorOpenTrace(
                tabId: tabId,
                url: url,
                workspaceID: content.workspaceID ?? "",
                openMode: "preview"
            )
        }
    }

    func openInPermanentTab(content: WorkspaceTabContent) {
        let trace = performanceTrace(for: content, action: "tab-open-permanent")
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }
        let result = openWorkspaceContent(
            content,
            mode: .permanent
        )

        if case .editor(_, let url) = content,
           let tabId = result.tabID,
           result.disposition == .created {
            beginEditorOpenTrace(
                tabId: tabId,
                url: url,
                workspaceID: content.workspaceID ?? "",
                openMode: "permanent"
            )
        }
    }

    @discardableResult
    func openBrowserURL(
        _ url: URL,
        workspaceID: Workspace.ID? = nil,
        preferredPaneID: PaneID? = nil
    ) -> TabID? {
        let workspaceID = workspaceID ?? selectedWorkspaceID
        guard let workspaceID,
              let paneID = targetPaneID(preferred: preferredPaneID, workspaceID: workspaceID) else {
            return nil
        }

        let browserID = UUID()
        _ = ensureBrowserSession(id: browserID, in: workspaceID, initialURL: url)
        let content = WorkspaceTabContent.browser(
            workspaceID: workspaceID,
            id: browserID,
            initialURL: url
        )
        let result = openWorkspaceContent(
            content,
            mode: .permanent,
            preferredPaneID: paneID
        )
        if result.tabID == nil {
            removeBrowserSession(id: browserID, in: workspaceID)
        }
        return result.tabID
    }

    func openBrowserURLFromTerminal(
        _ url: URL,
        workspaceID: Workspace.ID,
        sourcePaneID: PaneID
    ) {
        guard shouldOpenInEmbeddedBrowser(url) else {
            NSWorkspace.shared.open(url)
            return
        }

        if let destination = existingBrowserPaneDestination(
            workspaceID: workspaceID,
            excluding: sourcePaneID
        ) {
            let session = ensureBrowserSession(
                id: destination.browserID,
                in: workspaceID,
                initialURL: destination.initialURL
            )
            session.load(url: url)
            store.send(
                .selectWorkspaceTab(
                    workspaceID: workspaceID,
                    paneID: destination.paneID,
                    tabID: destination.tabID
                )
            )
            renderWorkspaceLayout(for: workspaceID)
            applyHostSelectionEffects(for: destination.tabID)
            return
        }

        guard let targetPaneID = splitPane(
            sourcePaneID,
            orientation: .horizontal,
            workspaceID: workspaceID
        ) else {
            return
        }

        _ = openBrowserURL(
            url,
            workspaceID: workspaceID,
            preferredPaneID: targetPaneID
        )
    }

    func findExistingTab(for content: WorkspaceTabContent) -> TabID? {
        tabContents.first { contentMatches($0.value, content) }?.key
    }

    func contentMatches(_ a: WorkspaceTabContent, _ b: WorkspaceTabContent) -> Bool {
        a.matchesSemanticIdentity(as: b)
    }

    private func performanceTrace(for content: WorkspaceTabContent, action: String) -> WorkspacePerformanceTrace {
        var context: [String: String] = [
            "content_kind": content.fallbackIcon
        ]
        if let workspaceID = content.workspaceID {
            context["workspace_id"] = workspaceID
        }
        if case .editor(_, let url) = content {
            context["file_extension"] = url.pathExtension
        }
        return WorkspacePerformanceRecorder.begin(action, context: context)
    }

    private func applyHostSelectionEffects(for tabId: TabID) {
        guard let content = tabContents[tabId] else { return }
        store.send(.setSelectedTabID(tabId))

        switch content {
        case .terminal(let workspaceID, let terminalId):
            markTerminalNotificationRead(terminalId)
            workspaceTerminalRegistry.session(id: terminalId, in: workspaceID)?.requestKeyboardFocus()
        case .workflowRun(let workspaceID, let runID):
            if let terminalID = workflowRun(
                workspaceID: workspaceID,
                runID: runID
            )?.currentTerminalID {
                workspaceTerminalRegistry.session(id: terminalID, in: workspaceID)?.requestKeyboardFocus()
            }
        case .agentSession:
            break
        case .editor:
            editorSessions[tabId]?.requestKeyboardFocus()
        case .gitDiff(_, let path, let isStaged):
            Task {
                await gitStore?.selectFile(path, isStaged: isStaged)
            }
        default:
            break
        }
    }

    private func openWorkspaceContent(
        _ content: WorkspaceTabContent,
        mode: WindowFeature.TabOpenMode,
        preferredPaneID: PaneID? = nil
    ) -> (tabID: TabID?, disposition: WorkspaceContentOpenDisposition) {
        guard let workspaceID = content.workspaceID ?? selectedWorkspaceID,
              let paneID = targetPaneID(preferred: preferredPaneID, workspaceID: workspaceID) else {
            return (nil, .created)
        }

        let previousTabContents = workspaceTabContents(for: workspaceID)
        let previousPreviewTabID = store.workspaceShells[workspaceID]?.layout?.paneLayout(for: paneID)?.previewTabID
        let previousPreviewContent = previousPreviewTabID.flatMap { previousTabContents[$0] }
        let disposition: WorkspaceContentOpenDisposition

        if previousTabContents.values.contains(where: { $0.matchesSemanticIdentity(as: content) }) {
            disposition = .existing
        } else if mode == .permanent,
                  previousPreviewContent?.matchesSemanticIdentity(as: content) == true {
            disposition = .promotedPreview
        } else if mode == .preview,
                  previousPreviewTabID != nil {
            disposition = .reusedPreview
        } else {
            disposition = .created
        }

        store.send(
            .openWorkspaceContent(
                workspaceID: workspaceID,
                paneID: paneID,
                content: content,
                mode: mode
            )
        )

        reconcileWorkspaceTabContentMutation(
            previousTabContents: previousTabContents,
            currentTabContents: workspaceTabContents(for: workspaceID)
        )
        renderWorkspaceLayout(for: workspaceID)

        let tabID = store.selectedTabID
        if let tabID {
            applyHostSelectionEffects(for: tabID)
        }

        return (tabID, disposition)
    }

    private func shouldOpenInEmbeddedBrowser(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https":
            true
        default:
            false
        }
    }

    private func existingBrowserPaneDestination(
        workspaceID: Workspace.ID,
        excluding sourcePaneID: PaneID
    ) -> BrowserPaneDestination? {
        guard let shell = store.workspaceShells[workspaceID],
              let layout = shell.layout else {
            return nil
        }

        let candidatePaneIDs = layout.allPaneIDs.filter { $0 != sourcePaneID }

        for paneID in candidatePaneIDs {
            guard let selectedTabID = layout.paneLayout(for: paneID)?.selectedTabID,
                  let destination = browserPaneDestination(
                    for: selectedTabID,
                    in: paneID,
                    tabContents: shell.tabContents
                  ) else {
                continue
            }
            return destination
        }

        for paneID in candidatePaneIDs {
            guard let paneLayout = layout.paneLayout(for: paneID) else { continue }
            for tabID in paneLayout.tabIDs {
                if let destination = browserPaneDestination(
                    for: tabID,
                    in: paneID,
                    tabContents: shell.tabContents
                ) {
                    return destination
                }
            }
        }

        return nil
    }

    private func browserPaneDestination(
        for tabID: TabID,
        in paneID: PaneID,
        tabContents: [TabID: WorkspaceTabContent]
    ) -> BrowserPaneDestination? {
        guard case .browser(_, let browserID, let initialURL)? = tabContents[tabID] else {
            return nil
        }

        return BrowserPaneDestination(
            paneID: paneID,
            tabID: tabID,
            browserID: browserID,
            initialURL: initialURL
        )
    }

    private func reconcileWorkspaceTabContentMutation(
        previousTabContents: [TabID: WorkspaceTabContent],
        currentTabContents: [TabID: WorkspaceTabContent]
    ) {
        let tabIDs = Set(previousTabContents.keys).union(currentTabContents.keys)

        for tabID in tabIDs {
            let previousContent = previousTabContents[tabID]
            let currentContent = currentTabContents[tabID]

            if let previousContent,
               let currentContent,
               previousContent != currentContent {
                cleanupReplacedTabContent(
                    previousContent,
                    newContent: currentContent,
                    tabId: tabID
                )
            }

            guard case .editor(_, let url)? = currentContent else { continue }
            ensureEditorSession(tabId: tabID, url: url)
        }

        for (_, currentContent) in currentTabContents {
            guard case .browser(let workspaceID, let id, let initialURL) = currentContent else {
                continue
            }
            _ = ensureBrowserSession(id: id, in: workspaceID, initialURL: initialURL)
        }
    }
}
