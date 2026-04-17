import ComposableArchitecture
import Foundation
import Workspace

extension WindowFeature {
    func createDefaultWorkflowDefinition(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID) else {
            return .none
        }

        let definition = WorkflowDefinition.defaultDeliveryDefinition(
            id: definitionID,
            now: now
        )
        .normalized(now: now)

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertDefinition(definition)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowDefinitionEffect(definition, rootURL: rootURL)
    }

    func updateWorkflowDefinition(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String,
        update: WorkflowDefinitionUpdate
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ) else {
            return .none
        }

        switch update {
        case .name(let name):
            definition.name = name
        case .planFilePath(let planFilePath):
            definition.planFilePath = planFilePath
        case .entryNodeID(let entryNodeID):
            definition.entryNodeID = entryNodeID
        }

        definition = definition.normalized(now: now)
        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertDefinition(definition)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowDefinitionEffect(definition, rootURL: rootURL)
    }

    func createWorkflowWorker(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String,
        workerID: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ) else {
            return .none
        }

        guard !definition.workers.contains(where: { $0.id == workerID }) else {
            return .none
        }

        var worker = WorkflowWorker.defaultImplementer()
        worker.id = workerID
        worker.displayName = "Worker \(definition.workers.count + 1)"
        worker.promptFilePath = "prompts/\(workerID).md"
        definition.workers.append(worker)
        definition = definition.normalized(now: now)

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertDefinition(definition)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowDefinitionEffect(definition, rootURL: rootURL)
    }

    func updateWorkflowWorker(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String,
        workerID: String,
        update: WorkflowWorkerUpdate
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ),
              let workerIndex = definition.workers.firstIndex(where: { $0.id == workerID }) else {
            return .none
        }

        switch update {
        case .displayName(let displayName):
            definition.workers[workerIndex].displayName = displayName
        case .kind(let kind):
            definition.workers[workerIndex].kind = kind
        case .model(let model):
            definition.workers[workerIndex].launcher.model = workflowTrimmedOptionalString(model)
        case .reasoningLevel(let reasoningLevel):
            definition.workers[workerIndex].launcher.reasoningLevel =
                workflowTrimmedOptionalString(reasoningLevel)
        case .dangerousPermissions(let dangerousPermissions):
            definition.workers[workerIndex].launcher.dangerousPermissions = dangerousPermissions
        case .executionMode(let executionMode):
            definition.workers[workerIndex].executionMode = executionMode
        case .extraArguments(let extraArguments):
            definition.workers[workerIndex].launcher.extraArguments = extraArguments
                .split(separator: " ")
                .map(String.init)
        case .prompt(let prompt):
            definition.workers[workerIndex].prompt = prompt
        }

        definition = definition.normalized(now: now)
        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertDefinition(definition)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowDefinitionEffect(definition, rootURL: rootURL)
    }

    func deleteWorkflowWorker(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String,
        workerID: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ) else {
            return .none
        }

        if definition.nodes.contains(where: { $0.kind == .agent && $0.workerID == workerID }) {
            state.updateWorkflowWorkspace(workspaceID) { workflowState in
                workflowState.lastErrorMessage = "Reassign agent nodes before deleting this worker."
            }
            return .none
        }

        definition.workers.removeAll { $0.id == workerID }
        definition = definition.normalized(now: now)

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertDefinition(definition)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowDefinitionEffect(definition, rootURL: rootURL)
    }

    func replaceWorkflowGraph(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String,
        nodes: [WorkflowNode],
        edges: [WorkflowEdge]
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID),
              var definition = state.workflowDefinition(
                workspaceID: workspaceID,
                definitionID: definitionID
              ) else {
            return .none
        }

        definition.nodes = nodes
        definition.edges = edges
        definition = definition.normalized(now: now)

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.upsertDefinition(definition)
            workflowState.lastErrorMessage = nil
        }
        return persistWorkflowDefinitionEffect(definition, rootURL: rootURL)
    }

    func deleteWorkflowDefinition(
        state: inout State,
        workspaceID: Workspace.ID,
        definitionID: String
    ) -> Effect<Action> {
        guard let rootURL = state.workflowRootURL(for: workspaceID) else {
            return .none
        }

        state.updateWorkflowWorkspace(workspaceID) { workflowState in
            workflowState.removeDefinition(id: definitionID)
        }
        return deleteWorkflowDefinitionEffect(
            definitionID: definitionID,
            rootURL: rootURL
        )
    }
}
