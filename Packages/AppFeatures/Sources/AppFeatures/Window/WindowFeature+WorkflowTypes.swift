import Foundation
import Workspace

public extension WindowFeature {
    struct WorkflowWorkspaceState: Equatable, Sendable {
        public var definitions: [WorkflowDefinition]
        public var runs: [WorkflowRun]
        public var isLoading: Bool
        public var lastErrorMessage: String?

        public init(
            definitions: [WorkflowDefinition] = [],
            runs: [WorkflowRun] = [],
            isLoading: Bool = false,
            lastErrorMessage: String? = nil
        ) {
            self.definitions = definitions
            self.runs = runs
            self.isLoading = isLoading
            self.lastErrorMessage = lastErrorMessage
        }

        public func definition(id: String) -> WorkflowDefinition? {
            definitions.first { $0.id == id }
        }

        public func run(id: UUID) -> WorkflowRun? {
            runs.first { $0.id == id }
        }
    }

    enum WorkflowDefinitionUpdate: Equatable, Sendable {
        case name(String)
        case planFilePath(String)
        case entryNodeID(String?)
    }

    enum WorkflowWorkerUpdate: Equatable, Sendable {
        case displayName(String)
        case kind(WorkflowAgentKind)
        case model(String)
        case reasoningLevel(String)
        case dangerousPermissions(Bool)
        case executionMode(WorkflowExecutionMode)
        case extraArguments(String)
        case prompt(String)
    }

    enum WorkflowNodeUpdate: Equatable, Sendable {
        case title(String)
        case workerID(String?)
        case promptOverride(String)
        case frame(WorkflowNodeFrame)
    }

    enum WorkflowEdgeUpdate: Equatable, Sendable {
        case label(String)
        case sourceNodeID(String)
        case targetNodeID(String)
    }
}

extension WindowFeature.WorkflowWorkspaceState {
    mutating func upsertDefinition(_ definition: WorkflowDefinition) {
        if let index = definitions.firstIndex(where: { $0.id == definition.id }) {
            definitions[index] = definition
        } else {
            definitions.append(definition)
        }
        definitions.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    mutating func removeDefinition(id: String) {
        definitions.removeAll { $0.id == id }
    }

    mutating func upsertRun(_ run: WorkflowRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.append(run)
        }
        runs.sort { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    mutating func removeRun(id: UUID) {
        runs.removeAll { $0.id == id }
    }
}

extension WindowFeature.State {
    public func workflowWorkspaceState(
        for workspaceID: Workspace.ID
    ) -> WindowFeature.WorkflowWorkspaceState {
        workflowWorkspacesByID[workspaceID] ?? WindowFeature.WorkflowWorkspaceState()
    }

    public func workflowDefinition(
        workspaceID: Workspace.ID,
        definitionID: String
    ) -> WorkflowDefinition? {
        workflowWorkspacesByID[workspaceID]?.definition(id: definitionID)
    }

    public func workflowRun(
        workspaceID: Workspace.ID,
        runID: UUID
    ) -> WorkflowRun? {
        workflowWorkspacesByID[workspaceID]?.run(id: runID)
    }

    mutating func updateWorkflowWorkspace(
        _ workspaceID: Workspace.ID,
        _ update: (inout WindowFeature.WorkflowWorkspaceState) -> Void
    ) {
        var workflowState = workflowWorkspacesByID[workspaceID] ?? WindowFeature.WorkflowWorkspaceState()
        update(&workflowState)
        workflowWorkspacesByID[workspaceID] = workflowState
    }

    func workflowRootURL(for workspaceID: Workspace.ID) -> URL? {
        worktree(for: workspaceID)?.workingDirectory
    }

    func activeWorkflowRuns() -> [WorkflowRun] {
        workflowWorkspacesByID.values
            .flatMap(\.runs)
            .filter { $0.currentTerminalID != nil }
    }

    public func workflowTerminalBinding(
        for terminalID: UUID,
        in workspaceID: Workspace.ID
    ) -> WorkflowTerminalBinding? {
        guard let state = workflowWorkspacesByID[workspaceID] else { return nil }
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
}
