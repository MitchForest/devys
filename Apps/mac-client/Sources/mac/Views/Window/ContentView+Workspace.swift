// ContentView+Workspace.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Browser
import Git
import SwiftUI
import Split
import GhosttyTerminal
import Workspace

@MainActor
extension ContentView {
    var workspace: some View {
        ContentViewWorkspaceSurface(
            selectedRepositoryRootURL: selectedRepositoryRootURL,
            selectedRepositoryDisplayName: selectedRepository?.displayName,
            controller: controller,
            tabContents: tabContents,
            gitStoreForContent: gitStoreForContent,
            terminalSessionForContent: terminalSessionForContent,
            terminalControllerForContent: terminalControllerForContent,
            terminalAppearance: themeManager.ghosttyAppearance(systemColorScheme: systemColorScheme),
            onTerminalPerformanceCheckpoint: { sessionID, checkpoint in
                recordTerminalOpenCheckpoint(sessionID: sessionID, checkpoint)
            },
            browserSessionForContent: browserSessionForContent,
            onOpenTerminalURL: { workspaceID, paneID, url in
                openBrowserURLFromTerminal(
                    url,
                    workspaceID: workspaceID,
                    sourcePaneID: paneID
                )
            },
            chatSessionForContent: chatSessionForContent,
            workflowDefinitionForContent: workflowDefinitionForContent,
            workflowRunForContent: workflowRunForContent,
            workflowLastErrorForContent: workflowLastErrorForContent,
            workflowDiffAvailableForContent: workflowDiffAvailableForContent,
            reviewRunForContent: reviewRunForContent,
            reviewIssuesForContent: reviewIssuesForContent,
            onOpenReviewIssueFile: { workspaceID, issue in
                openReviewIssueFile(workspaceID: workspaceID, issue: issue)
            },
            onOpenReviewArtifact: { workspaceID, path in
                openReviewArtifact(workspaceID: workspaceID, path: path)
            },
            onRerunReview: { workspaceID, runID in
                rerunReview(workspaceID: workspaceID, runID: runID)
            },
            onDismissReviewIssue: { workspaceID, runID, issueID in
                store.send(
                    .dismissReviewIssue(
                        workspaceID: workspaceID,
                        runID: runID,
                        issueID: issueID
                    )
                )
            },
            onSetReviewRunFollowUpHarness: { workspaceID, runID, harness in
                store.send(
                    .setReviewRunFollowUpHarness(
                        workspaceID: workspaceID,
                        runID: runID,
                        harness: harness
                    )
                )
            },
            onFixReviewIssue: { workspaceID, runID, issueID, harness in
                store.send(
                    .investigateReviewIssue(
                        workspaceID: workspaceID,
                        runID: runID,
                        issueID: issueID,
                        harness: harness
                    )
                )
            },
            agentComposerSpeechService: container.agentComposerSpeechService,
            onOpenAgentInlineTerminal: { workspaceID, terminalID in
                openInPermanentTab(content: .terminal(workspaceID: workspaceID, id: terminalID))
            },
            onOpenAgentFollowTarget: { workspaceID, target, prefersPreview in
                openChatLocationTarget(
                    workspaceID: workspaceID,
                    target: target,
                    prefersPreview: prefersPreview
                )
            },
            onOpenAgentDiffArtifact: { workspaceID, diff, prefersPreview in
                _ = openChatDiffArtifact(
                    workspaceID: workspaceID,
                    diff: diff,
                    prefersPreview: prefersPreview
                )
            },
            editorSessionForContent: { content, tabID in
                editorSessionForContent(content, tabId: tabID)
            },
            onUpdateWorkflowDefinition: { workspaceID, definitionID, update in
                updateWorkflowDefinition(
                    workspaceID: workspaceID,
                    definitionID: definitionID,
                    update: update
                )
            },
            onCreateWorkflowWorker: { workspaceID, definitionID in
                createWorkflowWorker(
                    workspaceID: workspaceID,
                    definitionID: definitionID
                )
            },
            onUpdateWorkflowWorker: { workspaceID, definitionID, workerID, update in
                updateWorkflowWorker(
                    workspaceID: workspaceID,
                    definitionID: definitionID,
                    workerID: workerID,
                    update: update
                )
            },
            onDeleteWorkflowWorker: { workspaceID, definitionID, workerID in
                deleteWorkflowWorker(
                    workspaceID: workspaceID,
                    definitionID: definitionID,
                    workerID: workerID
                )
            },
            onReplaceWorkflowGraph: { workspaceID, definitionID, nodes, edges in
                replaceWorkflowGraph(
                    workspaceID: workspaceID,
                    definitionID: definitionID,
                    nodes: nodes,
                    edges: edges
                )
            },
            onStartWorkflowRun: { workspaceID, definitionID in
                startWorkflowRun(workspaceID: workspaceID, definitionID: definitionID)
            },
            onContinueWorkflowRun: { workspaceID, runID in
                continueWorkflowRun(workspaceID: workspaceID, runID: runID)
            },
            onRestartWorkflowRun: { workspaceID, runID in
                restartWorkflowRun(workspaceID: workspaceID, runID: runID)
            },
            onStopWorkflowRun: { workspaceID, runID in
                stopWorkflowRun(workspaceID: workspaceID, runID: runID)
            },
            onDeleteWorkflowRun: { workspaceID, runID in
                deleteWorkflowRun(workspaceID: workspaceID, runID: runID)
            },
            onChooseWorkflowRunEdge: { workspaceID, runID, edgeID in
                chooseWorkflowRunEdge(
                    workspaceID: workspaceID,
                    runID: runID,
                    edgeID: edgeID
                )
            },
            onAppendWorkflowFollowUpTicket: { workspaceID, runID, sectionTitle, text in
                appendWorkflowFollowUpTicket(
                    workspaceID: workspaceID,
                    runID: runID,
                    sectionTitle: sectionTitle,
                    text: text
                )
            },
            onDeleteWorkflowDefinition: { workspaceID, definitionID in
                deleteWorkflowDefinition(workspaceID: workspaceID, definitionID: definitionID)
            },
            onOpenWorkflowFile: { workspaceID, path in
                openWorkflowFile(workspaceID: workspaceID, path: path)
            },
            onOpenWorkflowTerminal: { workspaceID, runID in
                openWorkflowTerminal(workspaceID: workspaceID, runID: runID)
            },
            onOpenWorkflowDiff: { workspaceID, runID in
                openWorkflowDiff(workspaceID: workspaceID, runID: runID)
            },
            onFocusPane: { paneID in
                focusPane(paneID)
            },
            onOpenTerminalInPane: { paneID in
                openShellForSelectedWorkspace(preferredPaneID: paneID)
            },
            onOpenBrowserInPane: { paneID in
                openDefaultBrowserForSelectedWorkspace(preferredPaneID: paneID)
            },
            showsBrowserInEmptyPane: !isRemoteWorkspaceSelected,
            isClaudeLauncherConfiguredForSelectedWorkspace: isLauncherConfiguredForSelectedWorkspace(
                kind: .claude
            ),
            isCodexLauncherConfiguredForSelectedWorkspace: isLauncherConfiguredForSelectedWorkspace(
                kind: .codex
            ),
            onOpenClaudeInPane: { paneID in
                launchClaudeForSelectedWorkspace(preferredPaneID: paneID)
            },
            onOpenCodexInPane: { paneID in
                launchCodexForSelectedWorkspace(preferredPaneID: paneID)
            },
            onOpenAgentInPane: { paneID in
                openDefaultOrPromptChatForSelectedWorkspace(preferredPaneID: paneID)
            },
            showsAgentInEmptyPane: !isRemoteWorkspaceSelected,
            onOpenFileInPane: { paneID in
                openFilePickerForSelectedWorkspace(in: paneID)
            },
            showsOpenFileInEmptyPane: !isRemoteWorkspaceSelected,
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

    func terminalSessionForContent(_ content: WorkspaceTabContent?) -> GhosttyTerminalSession? {
        guard case .terminal(let workspaceID, let id) = content else { return nil }
        return workspaceTerminalRegistry.session(id: id, in: workspaceID)
    }

    func terminalControllerForContent(
        _ content: WorkspaceTabContent?
    ) -> HostedLocalTerminalController? {
        guard case .terminal(let workspaceID, let id) = content else { return nil }
        return ensureHostedTerminalController(sessionID: id, workspaceID: workspaceID)
    }

    func browserSessionForContent(_ content: WorkspaceTabContent?) -> BrowserSession? {
        guard case .browser(let workspaceID, let id, let initialURL) = content else { return nil }
        return ensureBrowserSession(id: id, in: workspaceID, initialURL: initialURL)
    }

    func gitStoreForContent(_ content: WorkspaceTabContent?) -> GitStore? {
        guard let workspaceID = content?.workspaceID else { return nil }
        return runtimeRegistry.gitStore(for: workspaceID)
    }

    func chatSessionForContent(_ content: WorkspaceTabContent?) -> ChatSessionRuntime? {
        guard case .chatSession(let workspaceID, let sessionID) = content else { return nil }
        return runtimeRegistry.chatSession(id: sessionID, in: workspaceID)
    }

    func createTerminalSession(
        in workspaceID: Workspace.ID,
        workingDirectory: URL? = nil,
        requestedCommand: String? = nil,
        stagedCommand: String? = nil,
        tabIcon: String = "terminal",
        startupPhase: GhosttyTerminalStartupPhase = .startingShell,
        preferredViewportSize: HostedTerminalViewportSize? = nil,
        id: UUID = UUID()
    ) -> GhosttyTerminalSession {
        workspaceOperationalController.createTerminalSession(
            in: workspaceID,
            workingDirectory: workingDirectory,
            requestedCommand: requestedCommand,
            stagedCommand: stagedCommand,
            tabIcon: tabIcon,
            startupPhase: startupPhase,
            preferredViewportSize: preferredViewportSize,
            id: id
        )
    }

    func ensureBrowserSessions(for workspaceID: Workspace.ID) {
        for content in workspaceTabContents(for: workspaceID).values {
            guard case .browser(let contentWorkspaceID, let id, let initialURL) = content else {
                continue
            }
            _ = ensureBrowserSession(id: id, in: contentWorkspaceID, initialURL: initialURL)
        }
    }

    @discardableResult
    func ensureBrowserSession(
        id: UUID,
        in workspaceID: Workspace.ID,
        initialURL: URL
    ) -> BrowserSession {
        if let existing = browserRegistry.session(id: id, in: workspaceID) {
            return existing
        }

        let session = browserRegistry.createSession(
            in: workspaceID,
            url: initialURL,
            id: id
        )
        hostedContentBridge.attachBrowserSession(session, workspaceID: workspaceID)
        return session
    }

    func removeBrowserSession(id: UUID, in workspaceID: Workspace.ID) {
        if let session = browserRegistry.session(id: id, in: workspaceID) {
            session.beginRemoval()
            hostedContentBridge.detachBrowserSession(session, workspaceID: workspaceID)
        }
        browserRegistry.removeSession(id: id, in: workspaceID)
    }

    func removeAllBrowserSessions(in workspaceID: Workspace.ID) {
        for session in browserRegistry.sessions(for: workspaceID).values {
            session.beginRemoval()
            hostedContentBridge.detachBrowserSession(session, workspaceID: workspaceID)
        }
        browserRegistry.removeAllSessions(in: workspaceID)
    }

    func openDefaultBrowserForSelectedWorkspace(preferredPaneID: PaneID? = nil) {
        guard let workspaceID = selectedWorkspaceID,
              let url = URL(string: "http://localhost:3000") else {
            return
        }
        openBrowserURL(
            url,
            workspaceID: workspaceID,
            preferredPaneID: preferredPaneID
        )
    }
}
