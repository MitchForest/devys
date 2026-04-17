import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func workflowPlanSnapshotLoaded(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        snapshot: WorkflowPlanSnapshot
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        run.latestPlanSnapshot = snapshot
        run.updatedAt = now
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Loaded bound plan snapshot."
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }

        let shouldContinue = run.currentTerminalID == nil
            && run.activeAttemptID == nil
            && run.status != .awaitingOperator
            && run.status != .completed

        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            shouldContinue
                ? .send(.continueWorkflowRun(workspaceID: workspaceID, runID: runID))
                : .none
        )
    }

    func failWorkflowRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        message: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        run.status = .failed(message)
        run.currentTerminalID = nil
        if let activeAttemptID = run.activeAttemptID,
           let attemptIndex = run.attempts.firstIndex(where: { $0.id == activeAttemptID }) {
            run.attempts[attemptIndex].terminalID = nil
            run.attempts[attemptIndex].endedAt = now
            run.attempts[attemptIndex].status = .failed(message)
        }
        run.activeAttemptID = nil
        run.updatedAt = now
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                level: .error,
                message: message
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = message
        }
        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            registerWorkflowRunsEffect(state.activeWorkflowRuns())
        )
    }

    func launchWorkflowCurrentNode(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        definition: WorkflowDefinition
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              let worktree = state.worktree(for: workspaceID),
              let run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        guard let nodeID = run.currentNodeID,
              let node = definition.node(id: nodeID) else {
            return failWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                message: "Workflow node could not be resolved."
            )
        }

        if node.kind == .finish {
            return completeWorkflowFinishNode(
                state: &state,
                workspaceID: workspaceID,
                run: run,
                node: node,
                rootURL: rootURL
            )
        }

        guard let workerID = node.workerID,
              let worker = definition.worker(id: workerID) else {
            return failWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                message: "Workflow worker could not be resolved for \(node.displayTitle)."
            )
        }

        let launch = prepareWorkflowNodeLaunch(
            run: run,
            workspaceID: workspaceID,
            workingDirectoryURL: worktree.workingDirectory,
            definition: definition,
            node: node,
            worker: worker
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(launch.run)
            workflowState.lastErrorMessage = nil
        }

        return .merge(
            persistWorkflowRunEffect(launch.run, rootURL: rootURL),
            startWorkflowNodeEffect(request: launch.request)
        )
    }

    func workflowDefinitionPlanLoadEffect(
        workspaceID: Workspace.ID,
        runID: UUID,
        definition: WorkflowDefinition,
        rootURL: URL
    ) -> Effect<Action> {
        if let planFilePath = workflowTrimmedOptionalString(definition.planFilePath) {
            return loadPlanSnapshotEffect(
                workspaceID: workspaceID,
                runID: runID,
                planFilePath: planFilePath,
                rootURL: rootURL
            )
        }
        return .send(.continueWorkflowRun(workspaceID: workspaceID, runID: runID))
    }

    func continueAwaitingOperatorRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        definition: WorkflowDefinition,
        run: inout WorkflowRun,
        rootURL: URL
    ) -> Effect<Action>? {
        guard run.status == .awaitingOperator else {
            return nil
        }

        let availableEdges = definition.outgoingEdges(from: run.currentNodeID ?? "")
        guard availableEdges.count == 1 else {
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.lastErrorMessage = "Choose the next edge before continuing this run."
            }
            return .none
        }

        let edge = availableEdges[0]
        run.currentNodeID = edge.targetNodeID
        run.status = .idle
        run.updatedAt = now
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Continuing workflow via \(edge.displayLabel)."
            )
        )
        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }
        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            .send(.continueWorkflowRun(workspaceID: workspaceID, runID: runID))
        )
    }

    func completeWorkflowFinishNode(
        state: inout State,
        workspaceID: Workspace.ID,
        run: WorkflowRun,
        node: WorkflowNode,
        rootURL: URL
    ) -> Effect<Action> {
        var completedRun = run
        completedRun.status = .completed
        completedRun.completedAt = now
        completedRun.updatedAt = now
        completedRun.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Reached \(node.displayTitle). Workflow finished."
            )
        )
        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(completedRun)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowRunEffect(completedRun, rootURL: rootURL)
    }

    func prepareWorkflowNodeLaunch(
        run: WorkflowRun,
        workspaceID: Workspace.ID,
        workingDirectoryURL: URL,
        definition: WorkflowDefinition,
        node: WorkflowNode,
        worker: WorkflowWorker
    ) -> (run: WorkflowRun, request: WorkflowNodeLaunchRequest) {
        let prompt = WorkflowPromptRenderer.renderPrompt(
            definition: definition,
            node: node,
            worker: worker,
            snapshot: run.latestPlanSnapshot
        )
        let attemptID = uuid()
        let attempt = WorkflowRunAttempt(
            id: attemptID,
            nodeID: node.id,
            workerID: worker.id,
            status: .running,
            terminalID: nil,
            promptArtifactPath: nil,
            promptPreview: workflowPromptPreview(prompt),
            launchedCommand: nil,
            startedAt: now,
            endedAt: nil
        )

        var updatedRun = run
        updatedRun.status = .running
        updatedRun.activeAttemptID = attemptID
        updatedRun.currentTerminalID = nil
        updatedRun.updatedAt = now
        updatedRun.attempts.append(attempt)
        updatedRun.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Launching \(node.displayTitle) with \(worker.resolvedDisplayName)."
            )
        )

        let request = WorkflowNodeLaunchRequest(
            runID: run.id,
            attemptID: attemptID,
            workspaceID: workspaceID,
            workingDirectoryURL: workingDirectoryURL,
            node: node,
            worker: worker,
            prompt: prompt
        )
        return (updatedRun, request)
    }
}
