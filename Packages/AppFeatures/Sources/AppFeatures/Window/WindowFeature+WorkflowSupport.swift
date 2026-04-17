import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    enum WorkflowObservationID: Hashable {
        case execution
    }

    func reduceWorkflowExecutionUpdate(
        state: inout State,
        update: WorkflowExecutionUpdate
    ) -> Effect<Action> {
        switch update {
        case .terminalExited(let runID, let terminalID):
            return handleWorkflowTerminalExited(
                state: &state,
                runID: runID,
                terminalID: terminalID
            )

        case .terminalRestoreMissing(let runID, let terminalID):
            return handleWorkflowTerminalRestoreMissing(
                state: &state,
                runID: runID,
                terminalID: terminalID
            )
        }
    }

    func observeWorkflowExecutionUpdatesEffect() -> Effect<Action> {
        let workflowExecutionClient = self.workflowExecutionClient
        return .run { send in
            for await update in await workflowExecutionClient.updates() {
                await send(.workflowExecutionUpdated(update))
            }
        }
        .cancellable(id: WorkflowObservationID.execution, cancelInFlight: true)
    }

    func loadWorkflowWorkspaceEffect(
        workspaceID: Workspace.ID,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { send in
            do {
                let snapshot = try await workflowPersistenceClient.loadWorkspace(workspaceID, rootURL)
                await send(.workflowWorkspaceLoaded(workspaceID, snapshot))
            } catch {
                await send(.workflowWorkspaceLoadFailed(workspaceID, error.localizedDescription))
            }
        }
    }

    func persistWorkflowDefinitionEffect(
        _ definition: WorkflowDefinition,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { _ in
            try await workflowPersistenceClient.saveDefinition(definition, rootURL)
        }
    }

    func deleteWorkflowDefinitionEffect(
        definitionID: String,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { _ in
            try await workflowPersistenceClient.deleteDefinition(definitionID, rootURL)
        }
    }

    func persistWorkflowRunEffect(
        _ run: WorkflowRun,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { _ in
            try await workflowPersistenceClient.saveRun(run, rootURL)
        }
    }

    func deleteWorkflowRunEffect(
        runID: UUID,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { _ in
            try await workflowPersistenceClient.deleteRun(runID, rootURL)
        }
    }

    func loadPlanSnapshotEffect(
        workspaceID: Workspace.ID,
        runID: UUID,
        planFilePath: String,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { send in
            do {
                let snapshot = try await workflowPersistenceClient.loadPlanSnapshot(
                    planFilePath,
                    rootURL
                )
                await send(
                    .workflowPlanSnapshotLoaded(
                        workspaceID: workspaceID,
                        runID: runID,
                        snapshot: snapshot
                    )
                )
            } catch {
                await send(
                    .workflowPlanSnapshotLoadFailed(
                        workspaceID: workspaceID,
                        runID: runID,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    func appendWorkflowFollowUpTicketEffect(
        workspaceID: Workspace.ID,
        runID: UUID,
        request: WorkflowPlanAppendRequest,
        rootURL: URL
    ) -> Effect<Action> {
        let workflowPersistenceClient = self.workflowPersistenceClient
        return .run { send in
            do {
                let snapshot = try await workflowPersistenceClient.appendFollowUpTicket(
                    request,
                    rootURL
                )
                await send(
                    .workflowFollowUpTicketAppended(
                        workspaceID: workspaceID,
                        runID: runID,
                        snapshot: snapshot,
                        sectionTitle: request.sectionTitle,
                        text: request.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            } catch {
                await send(
                    .workflowFollowUpTicketAppendFailed(
                        workspaceID: workspaceID,
                        runID: runID,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    func startWorkflowNodeEffect(
        request: WorkflowNodeLaunchRequest
    ) -> Effect<Action> {
        let workflowExecutionClient = self.workflowExecutionClient
        return .run { send in
            do {
                let result = try await workflowExecutionClient.startNode(request)
                await send(
                    .workflowNodeLaunchSucceeded(
                        workspaceID: request.workspaceID,
                        runID: request.runID,
                        result: result
                    )
                )
            } catch {
                await send(
                    .workflowNodeLaunchFailed(
                        workspaceID: request.workspaceID,
                        runID: request.runID,
                        message: error.localizedDescription
                    )
                )
            }
        }
    }

    func stopWorkflowRunEffect(
        runID: UUID
    ) -> Effect<Action> {
        let workflowExecutionClient = self.workflowExecutionClient
        return .run { _ in
            await workflowExecutionClient.stopRun(runID)
        }
    }

    func registerWorkflowRunsEffect(
        _ runs: [WorkflowRun]
    ) -> Effect<Action> {
        let workflowExecutionClient = self.workflowExecutionClient
        return .run { _ in
            await workflowExecutionClient.registerRuns(runs)
        }
    }

    private func handleWorkflowTerminalExited(
        state: inout State,
        runID: UUID,
        terminalID: UUID
    ) -> Effect<Action> {
        guard let workspaceID = workflowWorkspaceID(for: runID, in: state),
              let rootURL = state.workflowRootURL(for: workspaceID),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID),
              let definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: run.definitionID
              ) else {
            return .none
        }
        guard run.currentTerminalID == terminalID else { return .none }

        let wasInterrupted = run.status == .interrupted
        let completedNodeID = run.currentNodeID

        finalizeWorkflowAttempt(&run, wasInterrupted: wasInterrupted, now: now)
        applyWorkflowTerminalExitOutcome(
            to: &run,
            wasInterrupted: wasInterrupted,
            completedNodeID: completedNodeID,
            definition: definition
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }

        let persistEffect = persistWorkflowRunEffect(run, rootURL: rootURL)
        let registerEffect = registerWorkflowRunsEffect(state.activeWorkflowRuns())

        guard !wasInterrupted else {
            return .merge(persistEffect, registerEffect)
        }

        guard let completedNodeID,
              definition.outgoingEdges(from: completedNodeID).count == 1 else {
            return .merge(persistEffect, registerEffect)
        }

        return .merge(
            persistEffect,
            registerEffect,
            .send(.continueWorkflowRun(workspaceID: workspaceID, runID: runID))
        )
    }

    private func handleWorkflowTerminalRestoreMissing(
        state: inout State,
        runID: UUID,
        terminalID: UUID
    ) -> Effect<Action> {
        guard let workspaceID = workflowWorkspaceID(for: runID, in: state),
              let rootURL = state.workflowRootURL(for: workspaceID),
              var run = state.workflowRun(workspaceID: workspaceID, runID: runID) else {
            return .none
        }
        guard run.currentTerminalID == terminalID else { return .none }

        run.status = .interrupted
        run.currentTerminalID = nil
        if let activeAttemptID = run.activeAttemptID,
           let attemptIndex = run.attempts.firstIndex(where: { $0.id == activeAttemptID }) {
            run.attempts[attemptIndex].terminalID = nil
            run.attempts[attemptIndex].endedAt = now
            run.attempts[attemptIndex].status = .interrupted
        }
        run.activeAttemptID = nil
        run.updatedAt = now
        run.events.append(
            WorkflowRunEvent(
                id: uuid(),
                timestamp: now,
                level: .warning,
                message: "Workflow terminal could not be restored after relaunch."
            )
        )

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertRun(run)
            workflowState.lastErrorMessage = nil
        }

        return .merge(
            persistWorkflowRunEffect(run, rootURL: rootURL),
            registerWorkflowRunsEffect(state.activeWorkflowRuns())
        )
    }

    private func finalizeWorkflowAttempt(
        _ run: inout WorkflowRun,
        wasInterrupted: Bool,
        now: Date
    ) {
        run.currentTerminalID = nil
        if let activeAttemptID = run.activeAttemptID,
           let attemptIndex = run.attempts.firstIndex(where: { $0.id == activeAttemptID }) {
            run.attempts[attemptIndex].terminalID = nil
            run.attempts[attemptIndex].endedAt = now
            run.attempts[attemptIndex].status = wasInterrupted ? .interrupted : .completed
        }
        run.activeAttemptID = nil
        run.updatedAt = now
    }

    private func applyWorkflowTerminalExitOutcome(
        to run: inout WorkflowRun,
        wasInterrupted: Bool,
        completedNodeID: String?,
        definition: WorkflowDefinition
    ) {
        guard !wasInterrupted else {
            run.events.append(
                WorkflowRunEvent(
                    id: uuid(),
                    timestamp: now,
                    level: .warning,
                    message: "Workflow node was interrupted before completion."
                )
            )
            return
        }

        guard let completedNodeID,
              let completedNode = definition.node(id: completedNodeID) else {
            return
        }

        let outgoingEdges = definition.outgoingEdges(from: completedNodeID)
        switch outgoingEdges.count {
        case 0:
            run.status = .completed
            run.completedAt = now
            run.events.append(
                WorkflowRunEvent(
                    id: uuid(),
                    timestamp: now,
                    message: "Completed \(completedNode.displayTitle). Workflow finished."
                )
            )
        case 1:
            let edge = outgoingEdges[0]
            run.status = .idle
            run.currentNodeID = edge.targetNodeID
            run.events.append(
                WorkflowRunEvent(
                    id: uuid(),
                    timestamp: now,
                    message: "Completed \(completedNode.displayTitle). Transitioning via \(edge.displayLabel)."
                )
            )
        default:
            run.status = .awaitingOperator
            run.events.append(
                WorkflowRunEvent(
                    id: uuid(),
                    timestamp: now,
                    message: "Completed \(completedNode.displayTitle). Choose the next edge."
                )
            )
        }
    }
}

func workflowWorkspaceID(
    for runID: UUID,
    in state: WindowFeature.State
) -> Workspace.ID? {
    state.workflowWorkspacesByID.first { _, workflowState in
        workflowState.runs.contains { $0.id == runID }
    }?.key
}

func workflowHydratedRun(
    _ run: WorkflowRun,
    now: Date,
    interruptionEventID: UUID
) -> WorkflowRun {
    guard run.status == .running, run.currentTerminalID == nil else { return run }

    var run = run
    run.status = .interrupted
    run.activeAttemptID = nil
    run.updatedAt = now
    run.events.append(
        WorkflowRunEvent(
            id: interruptionEventID,
            timestamp: now,
            level: .warning,
            message: "Workflow run was interrupted because no terminal session could be restored."
        )
    )
    return run
}

func workflowDefinitionSort(
    _ lhs: WorkflowDefinition,
    _ rhs: WorkflowDefinition
) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }
    return lhs.id < rhs.id
}

func workflowRunSort(
    _ lhs: WorkflowRun,
    _ rhs: WorkflowRun
) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }
    return lhs.id.uuidString < rhs.id.uuidString
}

func workflowPromptPreview(
    _ prompt: String
) -> String {
    let collapsed = prompt
        .replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")

    if collapsed.count <= 200 {
        return collapsed
    }

    let index = collapsed.index(collapsed.startIndex, offsetBy: 200)
    return "\(collapsed[..<index])..."
}

func workflowTrimmedOptionalString(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
