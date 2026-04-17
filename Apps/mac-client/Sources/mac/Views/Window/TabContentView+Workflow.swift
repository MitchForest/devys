import AppFeatures
import Foundation
import SwiftUI
import Workspace

extension TabContentView {
    struct WorkflowTabCallbacks {
        let definition: WorkflowTabDefinitionCallbacks
        let run: WorkflowTabRunCallbacks
    }

    struct WorkflowTabDefinitionCallbacks {
        let onUpdate: (WindowFeature.WorkflowDefinitionUpdate) -> Void
        let onCreateWorker: () -> Void
        let onUpdateWorker: (String, WindowFeature.WorkflowWorkerUpdate) -> Void
        let onDeleteWorker: (String) -> Void
        let onReplaceGraph: ([WorkflowNode], [WorkflowEdge]) -> Void
        let onDelete: () -> Void
        let onStartRun: () -> Void
        let onOpenPlan: () -> Void
    }

    struct WorkflowTabRunCallbacks {
        let onContinue: () -> Void
        let onRestart: () -> Void
        let onStop: () -> Void
        let onDelete: () -> Void
        let onChooseEdge: (String) -> Void
        let onAppendFollowUpTicket: (String, String) -> Void
        let onOpenPromptArtifact: () -> Void
        let onOpenTerminal: () -> Void
        let onOpenDiff: () -> Void
    }

    @ViewBuilder
    func workflowTab(
        workspaceID: Workspace.ID,
        definitionID: String,
        runID: UUID?,
        initialMode: WorkflowTabView.DisplayMode
    ) -> some View {
        let callbacks = makeWorkflowCallbacks(
            workspaceID: workspaceID,
            definitionID: definitionID,
            runID: runID
        )
        WorkflowTabView(
            definition: workflowDefinition,
            run: workflowRun,
            lastErrorMessage: workflowLastErrorMessage,
            canOpenDiff: workflowDiffAvailable,
            initialMode: initialMode,
            onUpdateDefinition: callbacks.definition.onUpdate,
            onCreateWorker: callbacks.definition.onCreateWorker,
            onUpdateWorker: callbacks.definition.onUpdateWorker,
            onDeleteWorker: callbacks.definition.onDeleteWorker,
            onReplaceGraph: callbacks.definition.onReplaceGraph,
            onDeleteDefinition: callbacks.definition.onDelete,
            onStartRun: callbacks.definition.onStartRun,
            onContinueRun: callbacks.run.onContinue,
            onRestartRun: callbacks.run.onRestart,
            onStopRun: callbacks.run.onStop,
            onDeleteRun: callbacks.run.onDelete,
            onChooseEdge: callbacks.run.onChooseEdge,
            onAppendFollowUpTicket: callbacks.run.onAppendFollowUpTicket,
            onOpenPromptArtifact: callbacks.run.onOpenPromptArtifact,
            onOpenTerminal: callbacks.run.onOpenTerminal,
            onOpenDiff: callbacks.run.onOpenDiff,
            onOpenPlan: callbacks.definition.onOpenPlan
        )
    }

    func makeWorkflowCallbacks(
        workspaceID: Workspace.ID,
        definitionID: String,
        runID: UUID?
    ) -> WorkflowTabCallbacks {
        WorkflowTabCallbacks(
            definition: makeWorkflowDefinitionCallbacks(
                workspaceID: workspaceID,
                definitionID: definitionID
            ),
            run: makeWorkflowRunCallbacks(
                workspaceID: workspaceID,
                runID: runID
            )
        )
    }

    func makeWorkflowDefinitionCallbacks(
        workspaceID: Workspace.ID,
        definitionID: String
    ) -> WorkflowTabDefinitionCallbacks {
        WorkflowTabDefinitionCallbacks(
            onUpdate: { update in
                onUpdateWorkflowDefinition(workspaceID, definitionID, update)
            },
            onCreateWorker: {
                onCreateWorkflowWorker(workspaceID, definitionID)
            },
            onUpdateWorker: { workerID, update in
                onUpdateWorkflowWorker(workspaceID, definitionID, workerID, update)
            },
            onDeleteWorker: { workerID in
                onDeleteWorkflowWorker(workspaceID, definitionID, workerID)
            },
            onReplaceGraph: { nodes, edges in
                onReplaceWorkflowGraph(workspaceID, definitionID, nodes, edges)
            },
            onDelete: {
                onDeleteWorkflowDefinition(workspaceID, definitionID)
            },
            onStartRun: {
                onStartWorkflowRun(workspaceID, definitionID)
            },
            onOpenPlan: {
                guard let planFilePath = workflowDefinition?.planFilePath else { return }
                onOpenWorkflowFile(workspaceID, planFilePath)
            }
        )
    }

    func makeWorkflowRunCallbacks(
        workspaceID: Workspace.ID,
        runID: UUID?
    ) -> WorkflowTabRunCallbacks {
        WorkflowTabRunCallbacks(
            onContinue: {
                guard let runID else { return }
                onContinueWorkflowRun(workspaceID, runID)
            },
            onRestart: {
                guard let runID else { return }
                onRestartWorkflowRun(workspaceID, runID)
            },
            onStop: {
                guard let runID else { return }
                onStopWorkflowRun(workspaceID, runID)
            },
            onDelete: {
                guard let runID else { return }
                onDeleteWorkflowRun(workspaceID, runID)
            },
            onChooseEdge: { edgeID in
                guard let runID else { return }
                onChooseWorkflowRunEdge(workspaceID, runID, edgeID)
            },
            onAppendFollowUpTicket: { sectionTitle, text in
                guard let runID else { return }
                onAppendWorkflowFollowUpTicket(workspaceID, runID, sectionTitle, text)
            },
            onOpenPromptArtifact: {
                guard let promptArtifactPath = workflowRun?.latestPromptArtifactPath else { return }
                onOpenWorkflowFile(workspaceID, promptArtifactPath)
            },
            onOpenTerminal: {
                guard let runID else { return }
                onOpenWorkflowTerminal(workspaceID, runID)
            },
            onOpenDiff: {
                guard let runID else { return }
                onOpenWorkflowDiff(workspaceID, runID)
            }
        )
    }
}
