import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func startWorkflowRunEffect(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String,
        runID: UUID
    ) -> Effect<Action> {
        if let existingRun = state.workflowWorkspaceState(for: workspaceID).runs.first(where: {
            $0.status.isActive
        }) {
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.lastErrorMessage = "Workflow run already active for this workspace."
                workflowState.upsertRun(existingRun)
            }
            return .none
        }

        guard let worktree = state.worktree(for: workspaceID),
              let definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ),
              let rootURL = state.workflowRootURL(for: workspaceID) else {
            return .none
        }

        var run = WorkflowRun(
            id: runID,
            definitionID: definition.id,
            workspaceID: workspaceID,
            worktreePath: worktree.workingDirectory.path,
            branchName: worktree.name,
            currentNodeID: definition.resolvedEntryNodeID,
            startedAt: now,
            updatedAt: now
        )
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Workflow run created."
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }

        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            workflowDefinitionPlanLoadEffect(
                workspaceID: workspaceID,
                runID: runID,
                definition: definition,
                rootURL: rootURL
            )
        )
    }

    func continueWorkflowRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              let definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: state.workflowRun(workspaceID: workspaceID, runID: runID)?.definitionID ?? ""
              ),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        if let resumeEffect = continueAwaitingOperatorRun(
            state: &state,
            workspaceID: workspaceID,
            runID: runID,
            definition: definition,
            run: &run,
            rootURL: rootURL
        ) {
            return resumeEffect
        }

        guard run.currentTerminalID == nil else { return .none }

        if let planFilePath = workflowTrimmedOptionalString(definition.planFilePath),
           run.latestPlanSnapshot == nil {
            return loadPlanSnapshotEffect(
                workspaceID: workspaceID,
                runID: runID,
                planFilePath: planFilePath,
                rootURL: rootURL
            )
        }

        return launchWorkflowCurrentNode(
            state: &state,
            workspaceID: workspaceID,
            runID: runID,
            definition: definition
        )
    }

    func restartWorkflowRunEffect(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              let definitionID = state.workflowRun(
                workspaceID: workspaceID,
                runID: runID
              )?.definitionID,
              let definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        run.status = .idle
        run.currentNodeID = definition.resolvedEntryNodeID
        run.activeAttemptID = nil
        run.currentTerminalID = nil
        run.latestPlanSnapshot = nil
        run.attempts = []
        run.completedAt = nil
        run.startedAt = now
        run.updatedAt = now
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Workflow run restarted."
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }
        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            workflowDefinitionPlanLoadEffect(
                workspaceID: workspaceID,
                runID: runID,
                definition: definition,
                rootURL: rootURL
            )
        )
    }

    func stopWorkflowRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }
        guard run.status.isActive else { return .none }

        run.status = .interrupted
        run.updatedAt = now
        if run.currentTerminalID == nil,
           let activeAttemptID = run.activeAttemptID,
           let attemptIndex = run.attempts.firstIndex(where: { $0.id == activeAttemptID }) {
            run.attempts[attemptIndex].status = .interrupted
            run.attempts[attemptIndex].endedAt = now
            run.activeAttemptID = nil
        }
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                level: .warning,
                message: "Workflow run interrupted."
            )
        )
        let shouldStopExecution = run.currentTerminalID != nil

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
        }
        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            registerWorkflowRunsEffect(state.activeWorkflowRuns()),
            shouldStopExecution ? stopWorkflowRunEffect(runID: runID) : .none
        )
    }

    func chooseWorkflowRunEdge(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        edgeID: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              let definitionID = state.workflowRun(
                workspaceID: workspaceID,
                runID: runID
              )?.definitionID,
              let definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID),
              run.status == .awaitingOperator,
              let sourceNodeID = run.currentNodeID,
              let edge = definition.outgoingEdges(from: sourceNodeID).first(where: { $0.id == edgeID }) else {
            return .none
        }

        run.currentNodeID = edge.targetNodeID
        run.status = .idle
        run.updatedAt = now
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "Selected \(edge.displayLabel)."
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

    func deleteWorkflowRun(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              state.workflowRun(workspaceID: workspaceID, runID: runID) != nil else {
            return .none
        }

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.removeRun(id: runID)
            workflowState.lastErrorMessage = nil
        }
        return .merge(
            deleteWorkflowRunEffect(runID: runID, rootURL: rootURL),
            registerWorkflowRunsEffect(state.activeWorkflowRuns())
        )
    }

    func appendWorkflowFollowUpTicket(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        sectionTitle: String,
        text: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              let run = state.workflowRun(workspaceID: workspaceID, runID: runID),
              let snapshot = run.latestPlanSnapshot,
              let phaseIndex = snapshot.currentPhaseIndex else {
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.lastErrorMessage = "Workflow phase is unavailable."
            }
            return .none
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSectionTitle = sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.lastErrorMessage = "Workflow follow-up text is empty."
            }
            return .none
        }
        guard !trimmedSectionTitle.isEmpty else {
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.lastErrorMessage = "Workflow section title is empty."
            }
            return .none
        }

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.lastErrorMessage = nil
        }

        return appendWorkflowFollowUpTicketEffect(
            workspaceID: workspaceID,
            runID: runID,
            request: WorkflowPlanAppendRequest(
                planFilePath: snapshot.planFilePath,
                phaseIndex: phaseIndex,
                sectionTitle: trimmedSectionTitle,
                text: trimmedText
            ),
            rootURL: rootURL
        )
    }

}
