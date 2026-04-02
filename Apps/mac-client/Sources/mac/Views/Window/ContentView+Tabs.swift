// ContentView+Tabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Split

extension ContentView {
    func selectTab(_ tabId: TabID) {
        controller.selectTab(tabId)
        selectedTabId = tabId
        if let content = tabContents[tabId],
           case .terminal(let terminalId) = content {
            markTerminalNotificationRead(terminalId)
            terminalSessions[terminalId]?.requestKeyboardFocus()
        }
    }
    
    func tabMetadata(for content: TabContent, tabId: TabID? = nil) -> (title: String, icon: String) {
        var title = content.fallbackTitle
        var icon = content.fallbackIcon
        switch content {
        case .terminal(let id):
            if let session = terminalSessions[id] {
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
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }

        if let existingTabId = findExistingTab(for: content) {
            selectTab(existingTabId)
            return
        }

        if let existingPreviewId = previewTabId {
            tabContents[existingPreviewId] = content
            let (title, icon) = tabMetadata(for: content)
            let activityIndicator = tabActivityIndicator()
            controller.updateTab(
                existingPreviewId,
                title: previewTitle(title),
                icon: icon,
                activityIndicator: activityIndicator
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
                tabContents[tabId] = content
                previewTabId = tabId
                selectTab(tabId)
            }
        }
    }

    func openInPermanentTab(content: TabContent) {
        let targetPane = controller.focusedPaneId ?? controller.allPaneIds.first
        guard let paneId = targetPane else { return }

        if let previewId = previewTabId,
           let previewContent = tabContents[previewId],
           contentMatches(previewContent, content) {
            let (title, _) = tabMetadata(for: content)
            let activityIndicator = tabActivityIndicator()
            controller.updateTab(previewId, title: title, activityIndicator: activityIndicator)
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
        case (.editor(let urlA), .editor(let urlB)):
            return urlA == urlB
        case (.gitDiff(let pathA, let stagedA), .gitDiff(let pathB, let stagedB)):
            return pathA == pathB && stagedA == stagedB
        case (.terminal(let idA), .terminal(let idB)):
            return idA == idB
        case (.settings, .settings):
            return true
        default:
            return false
        }
    }
}
