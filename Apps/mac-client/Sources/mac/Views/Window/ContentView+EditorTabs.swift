// ContentView+EditorTabs.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Split

@MainActor
extension ContentView {
    func updateEditorTabURL(tabId: TabID, newURL: URL) {
        tabContents[tabId] = .editor(url: newURL)
        if let session = editorSessions[tabId] {
            session.updateURL(newURL)
        }
        let (title, icon) = tabMetadata(for: .editor(url: newURL), tabId: tabId)
        controller.updateTab(tabId, title: title, icon: icon)
    }
}
