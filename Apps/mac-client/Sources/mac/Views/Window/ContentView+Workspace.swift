// ContentView+Workspace.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Split
import GhosttyTerminal

@MainActor
extension ContentView {
    var workspace: some View {
        DevysSplitView(
            controller: controller,
            content: { tab, paneId in
                let content = tabContents[tab.id]
                let terminalSession = terminalSessionForContent(content)
                let editorSession = editorSessionForContent(content, tabId: tab.id)
                TabContentView(
                    tab: tab,
                    content: content,
                    gitStore: gitStore,
                    terminalSession: terminalSession,
                    editorSession: editorSession,
                    onFocus: { controller.focusPane(paneId) },
                    onEditorURLChange: { newURL in
                        updateEditorTabURL(tabId: tab.id, newURL: newURL)
                    }
                )
                .id(content?.stableId ?? "empty")
            },
            emptyPane: { _ in
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        )
    }

    func terminalSessionForContent(_ content: TabContent?) -> GhosttyTerminalSession? {
        guard case .terminal(let id) = content else { return nil }
        return terminalSessions[id]
    }

    func createTerminalSession(
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil
    ) -> GhosttyTerminalSession {
        let session = GhosttyTerminalSession(
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand
        )
        terminalSessions[session.id] = session
        return session
    }
}
