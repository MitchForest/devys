// ContentView+Tabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
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
        case .agentSession(let workspaceID, let sessionID):
            if let session = runtimeRegistry.agentSession(id: sessionID, in: workspaceID) {
                title = session.tabTitle
                icon = session.tabIcon
            }
        default:
            title = content.fallbackTitle
            icon = content.fallbackIcon
        }
        return (title, icon)
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
            workspaceID: workspaceID,
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

    private func reconcileWorkspaceTabContentMutation(
        workspaceID: Workspace.ID,
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
    }
}
