import AppFeatures
import Foundation
import Git
import Split
import SwiftUI
import Workspace

@MainActor
extension ContentView {
    func applyWorkflowAutoLayoutModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: workflowRunTerminalDigest) { _, _ in
                openPendingWorkflowRunTerminals()
            }
    }

    func workflowTerminalBinding(
        terminalID: UUID,
        workspaceID: Workspace.ID
    ) -> WorkflowTerminalBinding? {
        guard let state = store.workflowWorkspacesByID[workspaceID] else { return nil }
        for run in state.runs {
            guard let attempt = run.attempts.first(where: { $0.terminalID == terminalID }) else {
                continue
            }
            let definition = state.definition(id: run.definitionID)
            let nodeTitle = definition?.node(id: attempt.nodeID)?.displayTitle
                ?? attempt.nodeID
            let definitionName = definition?.displayName ?? "Workflow"
            let isActive = run.status.isActive && run.currentTerminalID == terminalID
            return WorkflowTerminalBinding(
                workspaceID: workspaceID,
                runID: run.id,
                nodeID: attempt.nodeID,
                attemptID: attempt.id,
                nodeTitle: nodeTitle,
                definitionName: definitionName,
                isActive: isActive
            )
        }
        return nil
    }

    var workflowRunTerminalDigest: String {
        guard let workspaceID = selectedWorkspaceID,
              let state = store.workflowWorkspacesByID[workspaceID] else {
            return ""
        }
        return state.runs
            .compactMap { run -> String? in
                guard let terminalID = run.currentTerminalID else { return nil }
                return "\(run.id.uuidString):\(terminalID.uuidString)"
            }
            .sorted()
            .joined(separator: ",")
    }

    func workflowWorkspaceState(
        for workspaceID: Workspace.ID
    ) -> WindowFeature.WorkflowWorkspaceState {
        store.workflowWorkspacesByID[workspaceID] ?? WindowFeature.WorkflowWorkspaceState()
    }

    func workflowDefinition(
        workspaceID: Workspace.ID,
        definitionID: String
    ) -> WorkflowDefinition? {
        store.workflowWorkspacesByID[workspaceID]?.definition(id: definitionID)
    }

    func workflowRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> WorkflowRun? {
        store.workflowWorkspacesByID[workspaceID]?.run(id: runID)
    }

    func workflowDefinitionForContent(
        _ content: WorkspaceTabContent?
    ) -> WorkflowDefinition? {
        switch content {
        case .workflowDefinition(let workspaceID, let definitionID):
            return workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
            )
        case .workflowRun(let workspaceID, let runID):
            guard let run = workflowRun(workspaceID: workspaceID, runID: runID) else {
                return nil
            }
            return workflowDefinition(
                workspaceID: workspaceID,
                definitionID: run.definitionID
            )
        default:
            return nil
        }
    }

    func workflowRunForContent(
        _ content: WorkspaceTabContent?
    ) -> WorkflowRun? {
        guard case .workflowRun(let workspaceID, let runID) = content else {
            return nil
        }
        return workflowRun(workspaceID: workspaceID, runID: runID)
    }

    func workflowLastErrorForContent(
        _ content: WorkspaceTabContent?
    ) -> String? {
        guard let workspaceID = content?.workspaceID else { return nil }
        return workflowWorkspaceState(for: workspaceID).lastErrorMessage
    }

    func workflowDiffTarget(
        workspaceID: Workspace.ID
    ) -> GitFileChange? {
        runtimeRegistry.gitStore(for: workspaceID)?.allChanges.first
    }

    func workflowDiffAvailableForContent(
        _ content: WorkspaceTabContent?
    ) -> Bool {
        guard let workspaceID = content?.workspaceID else { return false }
        return workflowDiffTarget(workspaceID: workspaceID) != nil
    }

    func createWorkflowDefinition(
        in workspaceID: Workspace.ID
    ) {
        let definitionID = "workflow-\(UUID().uuidString.lowercased())"
        store.send(
            .createDefaultWorkflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
            )
        )
        openInPermanentTab(
            content: .workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
            )
        )
    }

    func openWorkflowDefinition(
        workspaceID: Workspace.ID,
        definitionID: String
    ) {
        openInPermanentTab(
            content: .workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
            )
        )
    }

    func startWorkflowRun(
        workspaceID: Workspace.ID,
        definitionID: String
    ) {
        if let existingRun = workflowWorkspaceState(for: workspaceID).runs.first(where: {
            $0.status.isActive
        }) {
            openInPermanentTab(
                content: .workflowRun(
                    workspaceID: workspaceID,
                    runID: existingRun.id
                )
            )
            return
        }

        let runID = UUID()
        store.send(
            .startWorkflowRun(
                workspaceID: workspaceID,
                definitionID: definitionID,
                runID: runID
            )
        )

        prepareWorkflowRunLayout(workspaceID: workspaceID, runID: runID)

        openInPermanentTab(
            content: .workflowRun(
                workspaceID: workspaceID,
                runID: runID
            )
        )
    }

    /// Splits the current pane horizontally so the workflow tab appears on the
    /// left and the agent terminal appears on the right when it spawns.
    private func prepareWorkflowRunLayout(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        guard let layout = store.workspaceShells[workspaceID]?.layout else {
            return
        }
        guard layout.allPaneIDs.count == 1 else {
            // Respect existing multi-pane layouts; leave terminals to open in the focused pane.
            return
        }
        guard let leftPaneID = layout.allPaneIDs.first else {
            return
        }
        guard let rightPaneID = splitPane(
            leftPaneID,
            orientation: .horizontal,
            workspaceID: workspaceID
        ) else {
            return
        }
        workflowRunTerminalPaneMap[runID] = rightPaneID
        focusPane(leftPaneID, workspaceID: workspaceID)
    }

    /// Opens newly-spawned workflow terminals into the pane reserved during the
    /// run's split, and clears that reservation once opened.
    func openPendingWorkflowRunTerminals() {
        guard let workspaceID = selectedWorkspaceID,
              let state = store.workflowWorkspacesByID[workspaceID] else {
            return
        }

        for run in state.runs {
            guard let terminalID = run.currentTerminalID,
                  !openedWorkflowTerminalIDs.contains(terminalID) else {
                continue
            }
            openedWorkflowTerminalIDs.insert(terminalID)

            let preferredPaneID = workflowRunTerminalPaneMap[run.id]
            let content = WorkspaceTabContent.terminal(workspaceID: workspaceID, id: terminalID)
            if let preferredPaneID,
               store.workspaceShells[workspaceID]?.layout?.paneLayout(for: preferredPaneID) != nil {
                openWorkspaceContentInPane(
                    content: content,
                    paneID: preferredPaneID
                )
                workflowRunTerminalPaneMap.removeValue(forKey: run.id)
            } else {
                openInPermanentTab(content: content)
            }
        }
    }

    private func openWorkspaceContentInPane(
        content: WorkspaceTabContent,
        paneID: PaneID
    ) {
        guard let workspaceID = content.workspaceID ?? selectedWorkspaceID else { return }
        store.send(
            .openWorkspaceContent(
                workspaceID: workspaceID,
                paneID: paneID,
                content: content,
                mode: .permanent
            )
        )
        renderWorkspaceLayout(for: workspaceID)
    }

    func continueWorkflowRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        store.send(.continueWorkflowRun(workspaceID: workspaceID, runID: runID))
    }

    func restartWorkflowRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        store.send(.restartWorkflowRun(workspaceID: workspaceID, runID: runID))
    }

    func stopWorkflowRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        store.send(.stopWorkflowRun(workspaceID: workspaceID, runID: runID))
    }

    func deleteWorkflowRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        guard let run = workflowRun(workspaceID: workspaceID, runID: runID) else {
            return
        }

        guard !run.status.isActive else {
            store.send(.deleteWorkflowRun(workspaceID: workspaceID, runID: runID))
            return
        }

        let targetContent = WorkspaceTabContent.workflowRun(workspaceID: workspaceID, runID: runID)
        let matchingTabIDs = workspaceTabContents(for: workspaceID).compactMap { tabID, content in
            contentMatches(content, targetContent) ? tabID : nil
        }

        for tabID in matchingTabIDs {
            if let paneID = paneID(for: tabID, workspaceID: workspaceID) {
                closeTab(tabID, in: paneID, workspaceID: workspaceID)
            }
        }

        store.send(.deleteWorkflowRun(workspaceID: workspaceID, runID: runID))
    }

    func chooseWorkflowRunEdge(
        workspaceID: Workspace.ID,
        runID: UUID,
        edgeID: String
    ) {
        store.send(.chooseWorkflowRunEdge(workspaceID: workspaceID, runID: runID, edgeID: edgeID))
    }

    func updateWorkflowDefinition(
        workspaceID: Workspace.ID,
        definitionID: String,
        update: WindowFeature.WorkflowDefinitionUpdate
    ) {
        store.send(
            .updateWorkflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID,
                update: update
            )
        )
    }

    func createWorkflowWorker(
        workspaceID: Workspace.ID,
        definitionID: String
    ) {
        let workerID = "worker-\(UUID().uuidString.lowercased())"
        store.send(
            .createWorkflowWorker(
                workspaceID: workspaceID,
                definitionID: definitionID,
                workerID: workerID
            )
        )
    }

    func updateWorkflowWorker(
        workspaceID: Workspace.ID,
        definitionID: String,
        workerID: String,
        update: WindowFeature.WorkflowWorkerUpdate
    ) {
        store.send(
            .updateWorkflowWorker(
                workspaceID: workspaceID,
                definitionID: definitionID,
                workerID: workerID,
                update: update
            )
        )
    }

    func deleteWorkflowWorker(
        workspaceID: Workspace.ID,
        definitionID: String,
        workerID: String
    ) {
        store.send(
            .deleteWorkflowWorker(
                workspaceID: workspaceID,
                definitionID: definitionID,
                workerID: workerID
            )
        )
    }

    func replaceWorkflowGraph(
        workspaceID: Workspace.ID,
        definitionID: String,
        nodes: [WorkflowNode],
        edges: [WorkflowEdge]
    ) {
        store.send(
            .replaceWorkflowGraph(
                workspaceID: workspaceID,
                definitionID: definitionID,
                nodes: nodes,
                edges: edges
            )
        )
    }

    func appendWorkflowFollowUpTicket(
        workspaceID: Workspace.ID,
        runID: UUID,
        sectionTitle: String,
        text: String
    ) {
        store.send(
            .appendWorkflowFollowUpTicket(
                workspaceID: workspaceID,
                runID: runID,
                sectionTitle: sectionTitle,
                text: text
            )
        )
    }

    func deleteWorkflowDefinition(
        workspaceID: Workspace.ID,
        definitionID: String
    ) {
        store.send(.deleteWorkflowDefinition(workspaceID: workspaceID, definitionID: definitionID))
    }

    func openWorkflowFile(
        workspaceID: Workspace.ID,
        path: String
    ) {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              let worktree = windowWorkspaceContext(for: workspaceID)?.worktree else {
            return
        }

        let url: URL
        if trimmedPath.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmedPath)
        } else {
            url = worktree.workingDirectory
                .appendingPathComponent(trimmedPath, isDirectory: false)
        }

        openInPermanentTab(content: .editor(workspaceID: workspaceID, url: url.standardizedFileURL))
    }

    func openWorkflowTerminal(
        workspaceID: Workspace.ID,
        runID: UUID
    ) {
        guard let terminalID = workflowRun(workspaceID: workspaceID, runID: runID)?.currentTerminalID else {
            return
        }
        openInPermanentTab(content: .terminal(workspaceID: workspaceID, id: terminalID))
    }

    func openWorkflowDiff(
        workspaceID: Workspace.ID,
        runID _: UUID
    ) {
        guard let target = workflowDiffTarget(workspaceID: workspaceID) else {
            return
        }
        openInPermanentTab(
            content: .gitDiff(
                workspaceID: workspaceID,
                path: target.path,
                isStaged: target.isStaged
            )
        )
    }
}
