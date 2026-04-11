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
            agentSessionForContent: agentSessionForContent,
            agentComposerSpeechService: container.agentComposerSpeechService,
            onOpenAgentInlineTerminal: { workspaceID, terminalID in
                openInPermanentTab(content: .terminal(workspaceID: workspaceID, id: terminalID))
            },
            onOpenAgentFollowTarget: { workspaceID, target, prefersPreview in
                openAgentLocationTarget(
                    workspaceID: workspaceID,
                    target: target,
                    prefersPreview: prefersPreview
                )
            },
            onOpenAgentDiffArtifact: { workspaceID, diff, prefersPreview in
                _ = openAgentDiffArtifact(
                    workspaceID: workspaceID,
                    diff: diff,
                    prefersPreview: prefersPreview
                )
            },
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

    func agentSessionForContent(_ content: TabContent?) -> AgentSessionRuntime? {
        guard case .agentSession(let workspaceID, let sessionID) = content else { return nil }
        return runtimeRegistry
            .runtimeHandle(for: workspaceID)?
            .agentRuntimeRegistry
            .session(id: sessionID)
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
