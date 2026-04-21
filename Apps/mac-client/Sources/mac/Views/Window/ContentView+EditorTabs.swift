// ContentView+EditorTabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import Split
import Workspace

@MainActor
extension ContentView {
    func workspaceTabContents(for workspaceID: Workspace.ID) -> [TabID: WorkspaceTabContent] {
        store.workspaceShells[workspaceID]?.tabContents ?? [:]
    }

    func canonicalEditorSessionURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    func setTabContent(_ content: WorkspaceTabContent, for tabId: TabID) {
        guard let workspaceID = content.workspaceID ?? selectedWorkspaceID else { return }
        let previousContent = workspaceTabContents(for: workspaceID)[tabId]
        store.send(.setWorkspaceTabContent(workspaceID: workspaceID, tabID: tabId, content: content))

        if let previousContent,
           previousContent != content {
            cleanupReplacedTabContent(
                previousContent,
                newContent: content,
                tabId: tabId
            )
        }

        if case .editor(_, let url) = content {
            ensureEditorSession(tabId: tabId, url: url)
        }
    }

    func updateEditorTabURL(tabId: TabID, newURL: URL) {
        guard let workspaceID = tabContents[tabId]?.workspaceID else { return }
        let content = WorkspaceTabContent.editor(workspaceID: workspaceID, url: newURL)
        store.send(.setWorkspaceTabContent(workspaceID: workspaceID, tabID: tabId, content: content))
        ensureEditorSession(tabId: tabId, url: newURL, reloadIfNeeded: false)
        let presentation = currentTabPresentation(for: content, tabId: tabId)
        tabPresentationById[tabId] = presentation
        controller.updateTab(
            tabId,
            title: presentation.title,
            icon: presentation.icon,
            isPreview: presentation.isPreview,
            isDirty: presentation.isDirty
        )
    }

    func editorSessionForContent(_ content: WorkspaceTabContent?, tabId: TabID) -> EditorSession? {
        guard case .editor = content else { return nil }
        return editorSessions[tabId]
    }

    func removeEditorSession(tabId: TabID, workspaceID: Workspace.ID?) {
        endEditorOpenTrace(tabId: tabId, outcome: "cancelled")
        guard let session = editorSessions.removeValue(forKey: tabId) else { return }
        if let workspaceID {
            hostedContentBridge.detachEditorSession(session, workspaceID: workspaceID)
        }
        editorSessionPool(for: workspaceID)?.release(url: session.url)
        editorSessionRegistry.unregister(tabId: tabId)
    }

    func removeTabContent(for tabId: TabID, content: WorkspaceTabContent) {
        guard let workspaceID = content.workspaceID ?? selectedWorkspaceID else { return }
        store.send(.removeWorkspaceTabContent(workspaceID: workspaceID, tabID: tabId))
    }

    func clearVisibleWorkspaceTabContents() {
        guard let selectedWorkspaceID else { return }
        store.send(.clearWorkspaceTabContents(selectedWorkspaceID))
    }

    func ensureEditorSession(
        tabId: TabID,
        url: URL,
        reloadIfNeeded: Bool = true
    ) {
        let workspaceID = tabContents[tabId]?.workspaceID ?? selectedWorkspaceID
        guard let editorSessionPool = editorSessionPool(for: workspaceID) else { return }
        let canonicalURL = canonicalEditorSessionURL(url)
        if let session = editorSessions[tabId] {
            if session.url != canonicalURL {
                rebindEditorSession(
                    tabId: tabId,
                    session: session,
                    to: canonicalURL,
                    workspaceID: workspaceID,
                    editorSessionPool: editorSessionPool,
                    reloadIfNeeded: reloadIfNeeded
                )
                return
            }

            refreshEditorSession(session, canonicalURL: canonicalURL, reloadIfNeeded: reloadIfNeeded)
            return
        }

        let session = editorSessionPool.acquire(url: canonicalURL)
        trackEditorSession(session, tabId: tabId, workspaceID: workspaceID)
        refreshEditorSession(session, canonicalURL: canonicalURL, reloadIfNeeded: reloadIfNeeded)
    }

    func cleanupReplacedTabContent(
        _ previousContent: WorkspaceTabContent,
        newContent: WorkspaceTabContent,
        tabId: TabID
    ) {
        switch (previousContent, newContent) {
        case (.editor, .editor):
            break
        default:
            cleanupSession(for: previousContent, tabId: tabId)
        }
    }

    private func rebindEditorSession(
        tabId: TabID,
        session: EditorSession,
        to canonicalURL: URL,
        workspaceID: Workspace.ID?,
        editorSessionPool: EditorSessionPool,
        reloadIfNeeded: Bool
    ) {
        if let sharedSession = editorSessionPool.session(for: canonicalURL),
           sharedSession !== session {
            untrackEditorSession(session, tabId: tabId, workspaceID: workspaceID)
            editorSessionPool.release(url: session.url)
            trackEditorSession(sharedSession, tabId: tabId, workspaceID: workspaceID)
            refreshEditorSession(sharedSession, canonicalURL: canonicalURL, reloadIfNeeded: reloadIfNeeded)
            return
        }

        if !reloadIfNeeded {
            editorSessionPool.move(session: session, from: session.url, to: canonicalURL)
            refreshEditorSession(session, canonicalURL: canonicalURL, reloadIfNeeded: false)
            editorSessionRegistry.register(tabId: tabId, session: session)
            return
        }

        editorSessionPool.release(url: session.url)
        untrackEditorSession(session, tabId: tabId, workspaceID: workspaceID)
        let reboundSession = editorSessionPool.acquire(url: canonicalURL)
        trackEditorSession(reboundSession, tabId: tabId, workspaceID: workspaceID)
    }

    private func refreshEditorSession(
        _ session: EditorSession,
        canonicalURL: URL,
        reloadIfNeeded: Bool
    ) {
        if reloadIfNeeded {
            session.open(canonicalURL)
        } else {
            session.updateURL(canonicalURL)
        }
    }

    private func trackEditorSession(
        _ session: EditorSession,
        tabId: TabID,
        workspaceID: Workspace.ID?
    ) {
        editorSessions[tabId] = session
        editorSessionRegistry.register(tabId: tabId, session: session)
        if let workspaceID {
            hostedContentBridge.attachEditorSession(session, workspaceID: workspaceID)
        }
    }

    private func untrackEditorSession(
        _ session: EditorSession,
        tabId: TabID,
        workspaceID: Workspace.ID?
    ) {
        editorSessionRegistry.unregister(tabId: tabId)
        if let workspaceID {
            hostedContentBridge.detachEditorSession(session, workspaceID: workspaceID)
        }
    }
}
