// ContentView+EditorTabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split

@MainActor
extension ContentView {
    func canonicalEditorSessionURL(_ url: URL) -> URL {
        url.standardizedFileURL
    }

    func setTabContent(_ content: TabContent, for tabId: TabID) {
        let previousContent = tabContents[tabId]
        tabContents[tabId] = content

        if let previousContent,
           previousContent != content {
            cleanupReplacedTabContent(
                previousContent,
                newContent: content,
                tabId: tabId
            )
        }

        if case .editor(let url) = content {
            ensureEditorSession(tabId: tabId, url: url)
        }
    }

    func updateEditorTabURL(tabId: TabID, newURL: URL) {
        tabContents[tabId] = .editor(url: newURL)
        ensureEditorSession(tabId: tabId, url: newURL, reloadIfNeeded: false)
        let (title, icon) = tabMetadata(for: .editor(url: newURL), tabId: tabId)
        controller.updateTab(tabId, title: title, icon: icon)
    }

    func editorSessionForContent(_ content: TabContent?, tabId: TabID) -> EditorSession? {
        guard case .editor = content else { return nil }
        return editorSessions[tabId]
    }

    func removeEditorSession(tabId: TabID) {
        guard let session = editorSessions.removeValue(forKey: tabId) else { return }
        editorSessionPool.release(url: session.url)
        EditorSessionRegistry.shared.unregister(tabId: tabId)
    }

    private func ensureEditorSession(
        tabId: TabID,
        url: URL,
        reloadIfNeeded: Bool = true
    ) {
        let canonicalURL = canonicalEditorSessionURL(url)
        if let session = editorSessions[tabId] {
            if session.url != canonicalURL {
                if let sharedSession = editorSessionPool.session(for: canonicalURL),
                   sharedSession !== session {
                    editorSessionPool.release(url: session.url)
                    editorSessions[tabId] = sharedSession
                    EditorSessionRegistry.shared.register(tabId: tabId, session: sharedSession)
                    if reloadIfNeeded {
                        sharedSession.open(canonicalURL)
                    } else {
                        sharedSession.updateURL(canonicalURL)
                    }
                    return
                }

                if !reloadIfNeeded {
                    editorSessionPool.move(session: session, from: session.url, to: canonicalURL)
                    session.updateURL(canonicalURL)
                    EditorSessionRegistry.shared.register(tabId: tabId, session: session)
                    return
                }

                editorSessionPool.release(url: session.url)
                EditorSessionRegistry.shared.unregister(tabId: tabId)
                let reboundSession = editorSessionPool.acquire(url: canonicalURL)
                editorSessions[tabId] = reboundSession
                EditorSessionRegistry.shared.register(tabId: tabId, session: reboundSession)
                return
            }

            if reloadIfNeeded {
                session.open(canonicalURL)
            } else {
                session.updateURL(canonicalURL)
            }
            return
        }

        let session = editorSessionPool.acquire(url: canonicalURL)
        editorSessions[tabId] = session
        EditorSessionRegistry.shared.register(tabId: tabId, session: session)
        if !reloadIfNeeded {
            session.updateURL(canonicalURL)
        }
    }

    private func cleanupReplacedTabContent(
        _ previousContent: TabContent,
        newContent: TabContent,
        tabId: TabID
    ) {
        switch (previousContent, newContent) {
        case (.editor, .editor):
            break
        default:
            cleanupSession(for: previousContent, tabId: tabId)
        }
    }
}
