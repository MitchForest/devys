import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func reduceWorkflowAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .startWorkflowObservation,
             .workflowWorkspaceLoadRequested,
             .workflowWorkspaceLoaded,
             .workflowWorkspaceLoadFailed:
            return reduceWorkflowWorkspaceAction(state: &state, action: action)

        case .createDefaultWorkflowDefinition,
             .updateWorkflowDefinition,
             .createWorkflowWorker,
             .updateWorkflowWorker,
             .deleteWorkflowWorker,
             .replaceWorkflowGraph,
             .deleteWorkflowDefinition:
            return reduceWorkflowDefinitionAction(state: &state, action: action)

        case .startWorkflowRun,
             .continueWorkflowRun,
             .restartWorkflowRun,
             .stopWorkflowRun,
             .chooseWorkflowRunEdge,
             .deleteWorkflowRun,
             .appendWorkflowFollowUpTicket:
            return reduceWorkflowRunMutationAction(state: &state, action: action)

        case .workflowPlanSnapshotLoaded,
             .workflowPlanSnapshotLoadFailed,
             .workflowNodeLaunchSucceeded,
             .workflowNodeLaunchFailed,
             .workflowFollowUpTicketAppended,
             .workflowFollowUpTicketAppendFailed:
            return reduceWorkflowRunProgressAction(state: &state, action: action)

        case .workflowExecutionUpdated(let update):
            return reduceWorkflowExecutionUpdate(state: &state, update: update)

        default:
            return .none
        }
    }
}

private extension WindowFeature {
    func reduceWorkflowWorkspaceAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case .startWorkflowObservation:
            let loadEffect = state.selectedWorkspaceID.flatMap { workspaceID in
                state.workflowRootURL(for: workspaceID).map { rootURL in
                    loadWorkflowWorkspaceEffect(workspaceID: workspaceID, rootURL: rootURL)
                }
            } ?? .none

            return .merge(
                observeWorkflowExecutionUpdatesEffect(),
                loadEffect,
                registerWorkflowRunsEffect(state.activeWorkflowRuns())
            )

        case .workflowWorkspaceLoadRequested(let workspaceID):
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.isLoading = true
                workflowState.lastErrorMessage = nil
            }
            guard let rootURL = state.workflowRootURL(for: workspaceID) else {
                return .none
            }
            return loadWorkflowWorkspaceEffect(workspaceID: workspaceID, rootURL: rootURL)

        case let .workflowWorkspaceLoaded(workspaceID, snapshot):
            let hydratedRuns = snapshot.runs.map { run in
                workflowHydratedRun(
                    run,
                    now: now,
                    interruptionEventID: uuid()
                )
            }

            state.workflowWorkspacesByID[workspaceID] = WorkflowWorkspaceState(
                definitions: snapshot.definitions.sorted(by: workflowDefinitionSort),
                runs: hydratedRuns.sorted(by: workflowRunSort),
                isLoading: false,
                lastErrorMessage: nil
            )
            return registerWorkflowRunsEffect(state.activeWorkflowRuns())

        case let .workflowWorkspaceLoadFailed(workspaceID, message):
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.isLoading = false
                workflowState.lastErrorMessage = message
            }
            return .none

        default:
            return .none
        }
    }

    func reduceWorkflowDefinitionAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        if let workerEffect = reduceWorkflowWorkerAction(state: &state, action: action) {
            return workerEffect
        }

        switch action {
        case let .createDefaultWorkflowDefinition(workspaceID, definitionID):
            return createDefaultWorkflowDefinition(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID
            )

        case let .updateWorkflowDefinition(workspaceID, definitionID, update):
            return updateWorkflowDefinition(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID,
                update: update
            )

        case let .replaceWorkflowGraph(workspaceID, definitionID, nodes, edges):
            return replaceWorkflowGraph(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID,
                nodes: nodes,
                edges: edges
            )

        case let .deleteWorkflowDefinition(workspaceID, definitionID):
            return deleteWorkflowDefinition(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID
            )

        default:
            return .none
        }
    }

    func reduceWorkflowWorkerAction(
        state: inout State,
        action: Action
    ) -> Effect<Action>? {
        switch action {
        case let .createWorkflowWorker(workspaceID, definitionID, workerID):
            return createWorkflowWorker(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID,
                workerID: workerID
            )

        case let .updateWorkflowWorker(workspaceID, definitionID, workerID, update):
            return updateWorkflowWorker(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID,
                workerID: workerID,
                update: update
            )

        case let .deleteWorkflowWorker(workspaceID, definitionID, workerID):
            return deleteWorkflowWorker(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID,
                workerID: workerID
            )

        default:
            return nil
        }
    }

    func reduceWorkflowRunMutationAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case let .startWorkflowRun(workspaceID, definitionID, runID):
            return startWorkflowRunEffect(
                state: &state,
                workspaceID: workspaceID,
                definitionID: definitionID,
                runID: runID
            )

        case let .continueWorkflowRun(workspaceID, runID):
            return continueWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID
            )

        case let .restartWorkflowRun(workspaceID, runID):
            return restartWorkflowRunEffect(
                state: &state,
                workspaceID: workspaceID,
                runID: runID
            )

        case let .stopWorkflowRun(workspaceID, runID):
            return stopWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID
            )

        case let .chooseWorkflowRunEdge(workspaceID, runID, edgeID):
            return chooseWorkflowRunEdge(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                edgeID: edgeID
            )

        case let .deleteWorkflowRun(workspaceID, runID):
            return deleteWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID
            )

        case let .appendWorkflowFollowUpTicket(workspaceID, runID, sectionTitle, text):
            return appendWorkflowFollowUpTicket(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                sectionTitle: sectionTitle,
                text: text
            )

        default:
            return .none
        }
    }

    func reduceWorkflowRunProgressAction(
        state: inout State,
        action: Action
    ) -> Effect<Action> {
        switch action {
        case let .workflowPlanSnapshotLoaded(workspaceID, runID, snapshot):
            return workflowPlanSnapshotLoaded(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                snapshot: snapshot
            )

        case let .workflowPlanSnapshotLoadFailed(workspaceID, runID, message):
            return failWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                message: message
            )

        case let .workflowNodeLaunchSucceeded(workspaceID, runID, result):
            return handleWorkflowNodeLaunchSucceeded(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                result: result
            )

        case let .workflowNodeLaunchFailed(workspaceID, runID, message):
            return failWorkflowRun(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                message: message
            )

        case let .workflowFollowUpTicketAppended(workspaceID, runID, snapshot, sectionTitle, text):
            return handleWorkflowFollowUpTicketAppended(
                state: &state,
                workspaceID: workspaceID,
                runID: runID,
                snapshot: snapshot,
                sectionTitle: sectionTitle,
                text: text
            )

        case let .workflowFollowUpTicketAppendFailed(workspaceID, _, message):
            return workflowFollowUpTicketAppendFailed(
                state: &state,
                workspaceID: workspaceID,
                message: message
            )

        default:
            return .none
        }
    }

    private func handleWorkflowNodeLaunchSucceeded(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        result: WorkflowNodeLaunchResult
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }

        run.currentTerminalID = result.terminalID
        if let activeAttemptID = run.activeAttemptID,
           let attemptIndex = run.attempts.firstIndex(where: { $0.id == activeAttemptID }) {
            run.attempts[attemptIndex].terminalID = result.terminalID
            run.attempts[attemptIndex].promptArtifactPath = result.promptArtifactPath
            run.attempts[attemptIndex].launchedCommand = result.launchedCommand
        }
        run.updatedAt = now
        let currentNodeName = run.currentNodeID.flatMap { nodeID in
            state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: run.definitionID
            )?.node(id: nodeID)?.displayTitle
        } ?? "Workflow node"
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                message: "\(currentNodeName) attached to terminal \(result.terminalID.uuidString)."
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
        }
        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            registerWorkflowRunsEffect(state.activeWorkflowRuns())
        )
    }

    private func handleWorkflowFollowUpTicketAppended(
        state: inout State,
        workspaceID: Workspace.ID,
        runID: UUID,
        snapshot: WorkflowPlanSnapshot,
        sectionTitle: String,
        text: String
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
                message: "Appended \(sectionTitle) ticket: \(text)."
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowRunEffect(run, rootURL: rootURL)
    }

    private func workflowFollowUpTicketAppendFailed(
        state: inout State,
        workspaceID: Workspace.ID,
        message: String
    ) -> Effect<Action> {
        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.lastErrorMessage = message
        }
        return .none
    }
}
