// ContentView+Workspace.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Split
import GhosttyTerminal
import Workspace

@MainActor
extension ContentView {
    var workspace: some View {
        ContentViewWorkspaceSurface(
            workspaceCatalog: workspaceCatalog,
            runtimeRegistry: runtimeRegistry,
            controller: controller,
            tabContents: tabContents,
            terminalSessionForContent: terminalSessionForContent,
            editorSessionForContent: { content, tabID in
                editorSessionForContent(content, tabId: tabID)
            },
            onFocusPane: { paneID in
                controller.focusPane(paneID)
            },
            onAttentionAcknowledged: { content in
                if case .some(.terminal(_, let terminalID)) = content {
                    markTerminalNotificationRead(terminalID)
                }
            },
            onPresentationChange: {
                syncTabMetadataFromSessions()
            },
            onEditorURLChange: { tabID, newURL in
                updateEditorTabURL(tabId: tabID, newURL: newURL)
            },
            onEditorPresentationChange: { tabID, snapshot in
                recordEditorOpenPresentation(tabId: tabID, snapshot: snapshot)
            }
        )
    }

    func terminalSessionForContent(_ content: TabContent?) -> GhosttyTerminalSession? {
        guard case .terminal(let workspaceID, let id) = content else { return nil }
        return workspaceTerminalRegistry.session(id: id, in: workspaceID)
    }

    func createTerminalSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        attachCommand: String? = nil,
        id: UUID = UUID()
    ) -> GhosttyTerminalSession {
        workspaceTerminalRegistry.createSession(
            in: workspaceID,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            attachCommand: attachCommand,
            id: id
        )
    }
}
