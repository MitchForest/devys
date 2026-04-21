import AppFeatures
import Browser
import Editor
import Git
import GhosttyTerminal
import Split
import SwiftUI
import Workspace

@MainActor
struct ContentViewWorkspaceSurface: View {
    let selectedRepositoryRootURL: URL?
    let selectedRepositoryDisplayName: String?
    let controller: DevysSplitController
    let tabContents: [TabID: WorkspaceTabContent]
    let gitStoreForContent: (WorkspaceTabContent?) -> GitStore?
    let terminalSessionForContent: (WorkspaceTabContent?) -> GhosttyTerminalSession?
    let terminalControllerForContent: (WorkspaceTabContent?) -> HostedLocalTerminalController?
    let terminalAppearance: GhosttyTerminalAppearance
    let onTerminalPerformanceCheckpoint: (UUID, TerminalOpenPerformanceTracker.Checkpoint) -> Void
    let browserSessionForContent: (WorkspaceTabContent?) -> BrowserSession?
    let onOpenTerminalURL: (Workspace.ID, PaneID, URL) -> Void
    let chatSessionForContent: (WorkspaceTabContent?) -> ChatSessionRuntime?
    let workflowDefinitionForContent: (WorkspaceTabContent?) -> WorkflowDefinition?
    let workflowRunForContent: (WorkspaceTabContent?) -> WorkflowRun?
    let workflowLastErrorForContent: (WorkspaceTabContent?) -> String?
    let workflowDiffAvailableForContent: (WorkspaceTabContent?) -> Bool
    let reviewRunForContent: (WorkspaceTabContent?) -> ReviewRun?
    let reviewIssuesForContent: (WorkspaceTabContent?) -> [ReviewIssue]
    let onOpenReviewIssueFile: (Workspace.ID, ReviewIssue) -> Void
    let onOpenReviewArtifact: (Workspace.ID, String) -> Void
    let onRerunReview: (Workspace.ID, UUID) -> Void
    let onDismissReviewIssue: (Workspace.ID, UUID, UUID) -> Void
    let onSetReviewRunFollowUpHarness: (Workspace.ID, UUID, BuiltInLauncherKind) -> Void
    let onFixReviewIssue: (Workspace.ID, UUID, UUID, BuiltInLauncherKind) -> Void
    let agentComposerSpeechService: any AgentComposerSpeechService
    let onOpenAgentInlineTerminal: (Workspace.ID, UUID) -> Void
    let onOpenAgentFollowTarget: (Workspace.ID, AgentFollowTarget, Bool) -> Void
    let onOpenAgentDiffArtifact: (Workspace.ID, AgentDiffContent, Bool) -> Void
    let editorSessionForContent: (WorkspaceTabContent?, TabID) -> EditorSession?
    let onUpdateWorkflowDefinition: (Workspace.ID, String, WindowFeature.WorkflowDefinitionUpdate) -> Void
    let onCreateWorkflowWorker: (Workspace.ID, String) -> Void
    let onUpdateWorkflowWorker: (Workspace.ID, String, String, WindowFeature.WorkflowWorkerUpdate) -> Void
    let onDeleteWorkflowWorker: (Workspace.ID, String, String) -> Void
    let onReplaceWorkflowGraph: (Workspace.ID, String, [WorkflowNode], [WorkflowEdge]) -> Void
    let onStartWorkflowRun: (Workspace.ID, String) -> Void
    let onContinueWorkflowRun: (Workspace.ID, UUID) -> Void
    let onRestartWorkflowRun: (Workspace.ID, UUID) -> Void
    let onStopWorkflowRun: (Workspace.ID, UUID) -> Void
    let onDeleteWorkflowRun: (Workspace.ID, UUID) -> Void
    let onChooseWorkflowRunEdge: (Workspace.ID, UUID, String) -> Void
    let onAppendWorkflowFollowUpTicket: (Workspace.ID, UUID, String, String) -> Void
    let onDeleteWorkflowDefinition: (Workspace.ID, String) -> Void
    let onOpenWorkflowFile: (Workspace.ID, String) -> Void
    let onOpenWorkflowTerminal: (Workspace.ID, UUID) -> Void
    let onOpenWorkflowDiff: (Workspace.ID, UUID) -> Void
    let onFocusPane: (PaneID) -> Void
    let onOpenTerminalInPane: (PaneID) -> Void
    let onOpenBrowserInPane: (PaneID) -> Void
    let showsBrowserInEmptyPane: Bool
    let isClaudeLauncherConfiguredForSelectedWorkspace: Bool
    let isCodexLauncherConfiguredForSelectedWorkspace: Bool
    let onOpenClaudeInPane: (PaneID) -> Void
    let onOpenCodexInPane: (PaneID) -> Void
    let onOpenAgentInPane: (PaneID) -> Void
    let showsAgentInEmptyPane: Bool
    let onOpenFileInPane: (PaneID) -> Void
    let showsOpenFileInEmptyPane: Bool
    let onAttentionAcknowledged: (WorkspaceTabContent?) -> Void
    let onPresentationChange: () -> Void
    let onEditorURLChange: (TabID, URL) -> Void
    let onEditorPresentationChange: (TabID, EditorOpenPerformanceSnapshot?) -> Void

    var body: some View {
        DevysSplitView(
            controller: controller,
            content: { tab, paneID in
                let content = tabContents[tab.id]
                TabContentView(
                    tab: tab,
                    content: content,
                    gitStore: gitStoreForContent(content),
                    terminalSession: terminalSessionForContent(content),
                    terminalController: terminalControllerForContent(content),
                    terminalAppearance: terminalAppearance,
                    onTerminalPerformanceCheckpoint: onTerminalPerformanceCheckpoint,
                    browserSession: browserSessionForContent(content),
                    onOpenTerminalURL: { url in
                        guard case .terminal(let workspaceID, _) = content else { return }
                        onOpenTerminalURL(workspaceID, paneID, url)
                    },
                    chatSession: chatSessionForContent(content),
                    workflowDefinition: workflowDefinitionForContent(content),
                    workflowRun: workflowRunForContent(content),
                    workflowLastErrorMessage: workflowLastErrorForContent(content),
                    workflowDiffAvailable: workflowDiffAvailableForContent(content),
                    reviewRun: reviewRunForContent(content),
                    reviewIssues: reviewIssuesForContent(content),
                    onOpenReviewIssueFile: onOpenReviewIssueFile,
                    onOpenReviewArtifact: onOpenReviewArtifact,
                    onRerunReview: onRerunReview,
                    onDismissReviewIssue: onDismissReviewIssue,
                    onSetReviewRunFollowUpHarness: onSetReviewRunFollowUpHarness,
                    onFixReviewIssue: onFixReviewIssue,
                    agentComposerSpeechService: agentComposerSpeechService,
                    onOpenAgentInlineTerminal: onOpenAgentInlineTerminal,
                    onOpenAgentFollowTarget: onOpenAgentFollowTarget,
                    onOpenAgentDiffArtifact: onOpenAgentDiffArtifact,
                    editorSession: editorSessionForContent(content, tab.id),
                    onUpdateWorkflowDefinition: { workspaceID, definitionID, update in
                        onUpdateWorkflowDefinition(workspaceID, definitionID, update)
                    },
                    onCreateWorkflowWorker: { workspaceID, definitionID in
                        onCreateWorkflowWorker(workspaceID, definitionID)
                    },
                    onUpdateWorkflowWorker: { workspaceID, definitionID, workerID, update in
                        onUpdateWorkflowWorker(workspaceID, definitionID, workerID, update)
                    },
                    onDeleteWorkflowWorker: { workspaceID, definitionID, workerID in
                        onDeleteWorkflowWorker(workspaceID, definitionID, workerID)
                    },
                    onReplaceWorkflowGraph: { workspaceID, definitionID, nodes, edges in
                        onReplaceWorkflowGraph(workspaceID, definitionID, nodes, edges)
                    },
                    onStartWorkflowRun: { workspaceID, definitionID in
                        onStartWorkflowRun(workspaceID, definitionID)
                    },
                    onContinueWorkflowRun: { workspaceID, runID in
                        onContinueWorkflowRun(workspaceID, runID)
                    },
                    onRestartWorkflowRun: { workspaceID, runID in
                        onRestartWorkflowRun(workspaceID, runID)
                    },
                    onStopWorkflowRun: { workspaceID, runID in
                        onStopWorkflowRun(workspaceID, runID)
                    },
                    onDeleteWorkflowRun: { workspaceID, runID in
                        onDeleteWorkflowRun(workspaceID, runID)
                    },
                    onChooseWorkflowRunEdge: { workspaceID, runID, edgeID in
                        onChooseWorkflowRunEdge(workspaceID, runID, edgeID)
                    },
                    onAppendWorkflowFollowUpTicket: { workspaceID, runID, sectionTitle, text in
                        onAppendWorkflowFollowUpTicket(workspaceID, runID, sectionTitle, text)
                    },
                    onDeleteWorkflowDefinition: { workspaceID, definitionID in
                        onDeleteWorkflowDefinition(workspaceID, definitionID)
                    },
                    onOpenWorkflowFile: { workspaceID, path in
                        onOpenWorkflowFile(workspaceID, path)
                    },
                    onOpenWorkflowTerminal: { workspaceID, runID in
                        onOpenWorkflowTerminal(workspaceID, runID)
                    },
                    onOpenWorkflowDiff: { workspaceID, runID in
                        onOpenWorkflowDiff(workspaceID, runID)
                    },
                    selectedRepositoryRootURL: selectedRepositoryRootURL,
                    selectedRepositoryDisplayName: selectedRepositoryDisplayName,
                    onFocus: { onFocusPane(paneID) },
                    onAttentionAcknowledged: {
                        onAttentionAcknowledged(content)
                    },
                    onPresentationChange: onPresentationChange,
                    onEditorURLChange: { newURL in
                        onEditorURLChange(tab.id, newURL)
                    },
                    onEditorPresentationChange: { snapshot in
                        onEditorPresentationChange(tab.id, snapshot)
                    }
                )
                .id(content?.stableId ?? "empty")
            },
            emptyPane: { paneID in
                WorkspaceEmptyPaneView(
                    paneID: paneID,
                    onFocusPane: onFocusPane,
                    onOpenTerminal: onOpenTerminalInPane,
                    onOpenBrowser: onOpenBrowserInPane,
                    showsBrowser: showsBrowserInEmptyPane,
                    canLaunchClaude: isClaudeLauncherConfiguredForSelectedWorkspace,
                    canLaunchCodex: isCodexLauncherConfiguredForSelectedWorkspace,
                    onOpenClaude: onOpenClaudeInPane,
                    onOpenCodex: onOpenCodexInPane,
                    onOpenAgent: onOpenAgentInPane,
                    showsAgent: showsAgentInEmptyPane,
                    onOpenFile: onOpenFileInPane,
                    showsOpenFile: showsOpenFileInEmptyPane
                )
            }
        )
    }
}
