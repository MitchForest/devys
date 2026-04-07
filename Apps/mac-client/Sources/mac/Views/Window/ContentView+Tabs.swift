// ContentView+Tabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split
import Workspace

extension ContentView {
    func selectTab(_ tabId: TabID) {
        controller.selectTab(tabId)
        selectedTabId = tabId
        if let content = tabContents[tabId] {
            switch content {
            case .terminal(let workspaceID, let terminalId):
                markTerminalNotificationRead(terminalId)
                workspaceTerminalRegistry.session(id: terminalId, in: workspaceID)?.requestKeyboardFocus()
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
    }
    
    func tabMetadata(for content: TabContent, tabId: TabID? = nil) -> (title: String, icon: String) {
        var title = content.fallbackTitle
        var icon = content.fallbackIcon
        switch content {
        case .terminal(let workspaceID, let id):
            if let session = workspaceTerminalRegistry.session(id: id, in: workspaceID) {
                title = session.tabTitle
                icon = session.tabIcon
            }
        default:
            title = content.fallbackTitle
            icon = content.fallbackIcon
        }
        let isPreview = tabId != nil && tabId == previewTabId
        if isPreview {
            title = previewTitle(title)
        }
        if case .editor = content,
           let tabId,
           let session = editorSessions[tabId],
           session.isDirty {
            title += " ●"
        }
        return (title, icon)
    }

    func tabActivityIndicator() -> TabActivityIndicator? {
        nil
    }

    func openInPreviewTab(content: TabContent) {
        if case .editor(let workspaceID, let url) = content {
            openEditorInPreviewTab(content: content, workspaceID: workspaceID, url: url)
            return
        }

        let trace = performanceTrace(for: content, action: "tab-open-preview")
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }

        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return
        }

        if let existingPreviewId = previewTabId {
            setTabContent(content, for: existingPreviewId)
            let presentation = currentTabPresentation(for: content, tabId: existingPreviewId)
            tabPresentationById[existingPreviewId] = presentation
            controller.updateTab(
                existingPreviewId,
                title: presentation.title,
                icon: presentation.icon,
                activityIndicator: presentation.activityIndicator
            )
            selectTab(existingPreviewId)
        } else {
            let (title, icon) = tabMetadata(for: content)
            let activityIndicator = tabActivityIndicator()
            if let tabId = controller.createTab(
                title: previewTitle(title),
                icon: icon,
                activityIndicator: activityIndicator,
                inPane: paneId
            ) {
                setTabContent(content, for: tabId)
                previewTabId = tabId
                tabPresentationById[tabId] = currentTabPresentation(for: content, tabId: tabId)
                selectTab(tabId)
            }
        }
    }

    func openInPermanentTab(content: TabContent) {
        if case .editor(let workspaceID, let url) = content {
            openEditorInPermanentTab(content: content, workspaceID: workspaceID, url: url)
            return
        }

        let trace = performanceTrace(for: content, action: "tab-open-permanent")
        defer {
            WorkspacePerformanceRecorder.end(trace)
        }
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }

        if let previewId = previewTabId,
           let previewContent = tabContents[previewId],
           contentMatches(previewContent, content) {
            let presentation = currentTabPresentation(for: content, tabId: previewId)
            tabPresentationById[previewId] = presentation
            controller.updateTab(
                previewId,
                title: presentation.title,
                activityIndicator: presentation.activityIndicator
            )
            previewTabId = nil
            selectTab(previewId)
            return
        }

        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return
        }

        createTab(in: paneId, content: content)
    }

    func previewTitle(_ title: String) -> String {
        "_\(title)_"
    }

    func findExistingTab(for content: TabContent) -> TabID? {
        tabContents.first { contentMatches($0.value, content) }?.key
    }

    func contentMatches(_ a: TabContent, _ b: TabContent) -> Bool {
        switch (a, b) {
        case (.editor(let workspaceA, let urlA), .editor(let workspaceB, let urlB)):
            return workspaceA == workspaceB && urlA == urlB
        case (
            .gitDiff(let workspaceA, let pathA, let stagedA),
            .gitDiff(let workspaceB, let pathB, let stagedB)
        ):
            return workspaceA == workspaceB && pathA == pathB && stagedA == stagedB
        case (.terminal(let workspaceA, let idA), .terminal(let workspaceB, let idB)):
            return workspaceA == workspaceB && idA == idB
        case (.settings, .settings):
            return true
        default:
            return false
        }
    }

    private func openEditorInPreviewTab(
        content: TabContent,
        workspaceID: Workspace.ID,
        url: URL
    ) {
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }

        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return
        }

        if let existingPreviewId = previewTabId {
            beginEditorOpenTrace(
                tabId: existingPreviewId,
                url: url,
                workspaceID: workspaceID,
                openMode: "preview"
            )
            setTabContent(content, for: existingPreviewId)
            let presentation = currentTabPresentation(for: content, tabId: existingPreviewId)
            tabPresentationById[existingPreviewId] = presentation
            controller.updateTab(
                existingPreviewId,
                title: presentation.title,
                icon: presentation.icon,
                activityIndicator: presentation.activityIndicator
            )
            selectTab(existingPreviewId)
            return
        }

        let (title, icon) = tabMetadata(for: content)
        let activityIndicator = tabActivityIndicator()
        guard let tabId = controller.createTab(
            title: previewTitle(title),
            icon: icon,
            activityIndicator: activityIndicator,
            inPane: paneId
        ) else {
            return
        }

        beginEditorOpenTrace(
            tabId: tabId,
            url: url,
            workspaceID: workspaceID,
            openMode: "preview"
        )
        setTabContent(content, for: tabId)
        previewTabId = tabId
        tabPresentationById[tabId] = currentTabPresentation(for: content, tabId: tabId)
        selectTab(tabId)
    }

    private func openEditorInPermanentTab(
        content: TabContent,
        workspaceID: Workspace.ID,
        url: URL
    ) {
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }

        if let previewId = previewTabId,
           let previewContent = tabContents[previewId],
           contentMatches(previewContent, content) {
            let presentation = currentTabPresentation(for: content, tabId: previewId)
            tabPresentationById[previewId] = presentation
            controller.updateTab(
                previewId,
                title: presentation.title,
                activityIndicator: presentation.activityIndicator
            )
            previewTabId = nil
            selectTab(previewId)
            return
        }

        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return
        }

        let title = tabMetadata(for: content).title
        let icon = tabMetadata(for: content).icon
        let activityIndicator = tabActivityIndicator()
        guard let tabId = controller.createTab(
            title: title,
            icon: icon,
            activityIndicator: activityIndicator,
            inPane: paneId
        ) else {
            return
        }

        beginEditorOpenTrace(
            tabId: tabId,
            url: url,
            workspaceID: workspaceID,
            openMode: "permanent"
        )
        setTabContent(content, for: tabId)
        tabPresentationById[tabId] = currentTabPresentation(for: content, tabId: tabId)
        selectTab(tabId)
    }

    private func performanceTrace(for content: TabContent, action: String) -> WorkspacePerformanceTrace {
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
}
