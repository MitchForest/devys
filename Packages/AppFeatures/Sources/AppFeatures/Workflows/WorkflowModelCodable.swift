import Foundation
import Workspace

private extension WorkflowDefinition {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case workers
        case nodes
        case edges
        case artifactBindings
        case entryNodeID
        case createdAt
        case updatedAt
        case planFilePath
        case roles
    }
}

public extension WorkflowDefinition {
    func normalized(now: Date) -> WorkflowDefinition {
        var definition = self

        let workers = WorkflowDefinition.normalizedWorkers(for: definition)
        let nodes = WorkflowDefinition.normalizedNodes(for: definition, workers: workers)
        let validNodeIDs = Set(nodes.map(\.id))

        definition.workers = workers
        definition.nodes = nodes
        definition.edges = definition.edges.filter { edge in
            validNodeIDs.contains(edge.sourceNodeID) && validNodeIDs.contains(edge.targetNodeID)
        }
        definition.entryNodeID = WorkflowDefinition.normalizedEntryNodeID(
            currentEntryNodeID: definition.entryNodeID,
            validNodeIDs: validNodeIDs,
            nodes: nodes
        )
        definition.updatedAt = now
        return definition
    }

    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.workers) || container.contains(.nodes) {
            self = try WorkflowDefinition.decodeCurrent(from: container)
            return
        }

        let legacy = try LegacyWorkflowDefinition(from: decoder)
        self = WorkflowDefinition.migrating(legacy)
    }

    func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(workers, forKey: .workers)
        try container.encode(nodes, forKey: .nodes)
        try container.encode(edges, forKey: .edges)
        try container.encode(artifactBindings, forKey: .artifactBindings)
        try container.encodeIfPresent(entryNodeID, forKey: .entryNodeID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private extension WorkflowDefinition {
    static func decodeCurrent(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> WorkflowDefinition {
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        return WorkflowDefinition(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            workers: try container.decode([WorkflowWorker].self, forKey: .workers),
            nodes: try container.decode([WorkflowNode].self, forKey: .nodes),
            edges: try container.decode([WorkflowEdge].self, forKey: .edges),
            artifactBindings: try container.decodeIfPresent(
                [WorkflowArtifactBinding].self,
                forKey: .artifactBindings
            ) ?? [],
            entryNodeID: try container.decodeIfPresent(String.self, forKey: .entryNodeID),
            createdAt: createdAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        )
    }

    static func migrating(
        _ legacy: LegacyWorkflowDefinition
    ) -> WorkflowDefinition {
        let graph = migratedGraph(from: legacy)
        var definition = WorkflowDefinition(
            id: legacy.id,
            name: legacy.name,
            workers: migratedWorkers(from: legacy),
            nodes: graph.nodes,
            edges: graph.edges,
            artifactBindings: [],
            entryNodeID: graph.nodes.first?.id,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
        definition.planFilePath = legacy.planFilePath
        return definition
    }

    static func normalizedWorkers(
        for definition: WorkflowDefinition
    ) -> [WorkflowWorker] {
        let hasAgentNodes = definition.nodes.contains { $0.kind == .agent }
        if definition.workers.isEmpty, hasAgentNodes {
            return [WorkflowWorker.defaultImplementer()]
        }
        return definition.workers
    }

    static func normalizedNodes(
        for definition: WorkflowDefinition,
        workers: [WorkflowWorker]
    ) -> [WorkflowNode] {
        let seedNodes = definition.nodes.isEmpty
            ? [
                WorkflowNode.finish(
                    id: "finish",
                    title: "Complete",
                    frame: .init(x: 0, y: 0, width: 180, height: 100)
                )
            ]
            : definition.nodes

        let validWorkerIDs = Set(workers.map(\.id))
        let fallbackWorkerID = workers.first?.id

        return seedNodes.map { node in
            var node = node
            switch node.kind {
            case .agent:
                if let workerID = node.workerID, validWorkerIDs.contains(workerID) {
                    return node
                }
                node.workerID = fallbackWorkerID
            case .finish:
                node.workerID = nil
                node.promptFilePath = nil
                node.promptOverride = nil
            }
            return node
        }
    }

    static func normalizedEntryNodeID(
        currentEntryNodeID: String?,
        validNodeIDs: Set<String>,
        nodes: [WorkflowNode]
    ) -> String? {
        if let currentEntryNodeID, validNodeIDs.contains(currentEntryNodeID) {
            return currentEntryNodeID
        }
        return nodes.first?.id
    }

    static func migratedWorkers(
        from legacy: LegacyWorkflowDefinition
    ) -> [WorkflowWorker] {
        legacy.roles.map { legacyRole in
            WorkflowWorker(
                id: legacyRole.id,
                displayName: legacyRole.displayName,
                kind: legacyRole.kind,
                launcher: legacyRole.launcher,
                executionMode: legacyRole.executionMode,
                promptFilePath: legacyRole.executePromptFilePath,
                prompt: legacyRole.executePrompt
            )
        }
    }

    static func migratedGraph(
        from legacy: LegacyWorkflowDefinition
    ) -> (nodes: [WorkflowNode], edges: [WorkflowEdge]) {
        guard let executorRole = legacy.roles.first else {
            return ([], [])
        }

        var nodes = [migratedExecutorNode(from: executorRole)]
        var edges: [WorkflowEdge] = []
        var previousNodeID = nodes[0].id

        if let reviewNode = migratedSelfReviewNode(from: executorRole) {
            nodes.append(reviewNode)
            edges.append(
                WorkflowEdge(
                    id: "executor-execute-to-review",
                    sourceNodeID: previousNodeID,
                    targetNodeID: reviewNode.id
                )
            )
            previousNodeID = reviewNode.id
        }

        if let reviewerRole = legacy.roles.dropFirst().first {
            let reviewerNode = migratedReviewerNode(from: reviewerRole)
            nodes.append(reviewerNode)
            edges.append(
                WorkflowEdge(
                    id: "review-loop",
                    sourceNodeID: previousNodeID,
                    targetNodeID: reviewerNode.id
                )
            )
            previousNodeID = reviewerNode.id
        }

        let finishNode = WorkflowNode.finish(
            id: "finish",
            title: "Complete",
            frame: .init(x: 640, y: -40, width: 180, height: 100)
        )
        nodes.append(finishNode)
        edges.append(
            WorkflowEdge(
                id: "legacy-finish",
                sourceNodeID: previousNodeID,
                targetNodeID: finishNode.id,
                label: "Complete"
            )
        )
        return (nodes, edges)
    }

    static func migratedExecutorNode(
        from legacyRole: LegacyWorkflowRole
    ) -> WorkflowNode {
        WorkflowNode.agent(
            id: "executorExecute",
            title: legacyRole.displayName,
            workerID: legacyRole.id,
            frame: .init(x: -320, y: -40, width: 220, height: 120)
        )
    }

    static func migratedSelfReviewNode(
        from legacyRole: LegacyWorkflowRole
    ) -> WorkflowNode? {
        guard let reviewPrompt = legacyNormalizedOptionalString(legacyRole.reviewPrompt) else {
            return nil
        }
        return WorkflowNode.agent(
            id: "executorSelfReview",
            title: "\(legacyRole.displayName) Review",
            workerID: legacyRole.id,
            promptFilePath: legacyRole.reviewPromptFilePath,
            promptOverride: reviewPrompt,
            frame: .init(x: 0, y: -40, width: 220, height: 120)
        )
    }

    static func migratedReviewerNode(
        from legacyRole: LegacyWorkflowRole
    ) -> WorkflowNode {
        WorkflowNode.agent(
            id: "reviewerAudit",
            title: legacyRole.displayName,
            workerID: legacyRole.id,
            frame: .init(x: 320, y: -40, width: 220, height: 120)
        )
    }
}

private extension WorkflowRun {
    enum CodingKeys: String, CodingKey {
        case id
        case definitionID
        case workspaceID
        case worktreePath
        case branchName
        case status
        case currentNodeID
        case activeAttemptID
        case currentTerminalID
        case latestPlanSnapshot
        case attempts
        case events
        case startedAt
        case updatedAt
        case completedAt
        case currentStep
        case lastCompletedStep
        case latestPromptArtifactPath
        case latestPromptPreview
    }
}

public extension WorkflowRun {
    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.attempts) || container.contains(.currentNodeID) {
            self = try WorkflowRun.decodeCurrent(from: container)
            return
        }

        let legacy = try LegacyWorkflowRun(from: decoder)
        self = WorkflowRun.migrating(legacy)
    }

    func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(definitionID, forKey: .definitionID)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(worktreePath, forKey: .worktreePath)
        try container.encode(branchName, forKey: .branchName)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(currentNodeID, forKey: .currentNodeID)
        try container.encodeIfPresent(activeAttemptID, forKey: .activeAttemptID)
        try container.encodeIfPresent(currentTerminalID, forKey: .currentTerminalID)
        try container.encodeIfPresent(latestPlanSnapshot, forKey: .latestPlanSnapshot)
        try container.encode(attempts, forKey: .attempts)
        try container.encode(events, forKey: .events)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }
}

private extension WorkflowRun {
    static func decodeCurrent(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> WorkflowRun {
        let startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        return WorkflowRun(
            id: try container.decode(UUID.self, forKey: .id),
            definitionID: try container.decode(String.self, forKey: .definitionID),
            workspaceID: try container.decode(Workspace.ID.self, forKey: .workspaceID),
            worktreePath: try container.decode(String.self, forKey: .worktreePath),
            branchName: try container.decode(String.self, forKey: .branchName),
            status: try container.decode(WorkflowRunStatus.self, forKey: .status),
            currentNodeID: try container.decodeIfPresent(String.self, forKey: .currentNodeID),
            activeAttemptID: try container.decodeIfPresent(UUID.self, forKey: .activeAttemptID),
            currentTerminalID: try container.decodeIfPresent(UUID.self, forKey: .currentTerminalID),
            latestPlanSnapshot: try container.decodeIfPresent(
                WorkflowPlanSnapshot.self,
                forKey: .latestPlanSnapshot
            ),
            attempts: try container.decodeIfPresent([WorkflowRunAttempt].self, forKey: .attempts) ?? [],
            events: try container.decodeIfPresent([WorkflowRunEvent].self, forKey: .events) ?? [],
            startedAt: startedAt,
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? startedAt,
            completedAt: try container.decodeIfPresent(Date.self, forKey: .completedAt)
        )
    }

    static func migrating(
        _ legacy: LegacyWorkflowRun
    ) -> WorkflowRun {
        let migratedAttempt = migratedAttempt(from: legacy)
        let attempts = migratedAttempt.map { [$0] } ?? []
        let activeAttemptID = migratedAttempt?.status == .running ? migratedAttempt?.id : nil

        return WorkflowRun(
            id: legacy.id,
            definitionID: legacy.definitionID,
            workspaceID: legacy.workspaceID,
            worktreePath: legacy.worktreePath,
            branchName: legacy.branchName,
            status: legacy.status,
            currentNodeID: legacy.currentStep?.rawValue ?? legacy.lastCompletedStep?.rawValue,
            activeAttemptID: activeAttemptID,
            currentTerminalID: legacy.currentTerminalID,
            latestPlanSnapshot: legacy.latestPlanSnapshot,
            attempts: attempts,
            events: legacy.events,
            startedAt: legacy.startedAt,
            updatedAt: legacy.updatedAt,
            completedAt: legacy.completedAt
        )
    }

    static func migratedAttempt(
        from legacy: LegacyWorkflowRun
    ) -> WorkflowRunAttempt? {
        guard legacy.currentStep != nil
            || legacy.lastCompletedStep != nil
            || legacy.currentTerminalID != nil
            || legacy.latestPromptArtifactPath != nil
            || legacy.latestPromptPreview != nil else {
            return nil
        }

        let attemptStatus = migratedAttemptStatus(from: legacy.status)
        return WorkflowRunAttempt(
            id: UUID(),
            nodeID: legacy.currentStep?.rawValue
                ?? legacy.lastCompletedStep?.rawValue
                ?? "legacy-node",
            workerID: nil,
            status: attemptStatus,
            terminalID: legacy.currentTerminalID,
            promptArtifactPath: legacy.latestPromptArtifactPath,
            promptPreview: legacy.latestPromptPreview,
            launchedCommand: nil,
            startedAt: legacy.startedAt,
            endedAt: attemptStatus == .running ? nil : legacy.updatedAt
        )
    }

    static func migratedAttemptStatus(
        from status: WorkflowRunStatus
    ) -> WorkflowRunAttemptStatus {
        switch status {
        case .failed(let message):
            .failed(message)
        case .interrupted:
            .interrupted
        case .running, .awaitingOperator:
            .running
        case .idle, .completed:
            .completed
        }
    }
}

private struct LegacyWorkflowDefinition: Decodable {
    var id: String
    var name: String
    var planFilePath: String
    var roles: [LegacyWorkflowRole]
    var createdAt: Date
    var updatedAt: Date
}

private struct LegacyWorkflowRole: Decodable {
    var id: String
    var displayName: String
    var kind: WorkflowAgentKind
    var launcher: LauncherTemplate
    var executionMode: WorkflowExecutionMode
    var executePromptFilePath: String
    var executePrompt: String
    var reviewPromptFilePath: String?
    var reviewPrompt: String?
}

private struct LegacyWorkflowRun: Decodable {
    var id: UUID
    var definitionID: String
    var workspaceID: Workspace.ID
    var worktreePath: String
    var branchName: String
    var status: WorkflowRunStatus
    var currentStep: LegacyWorkflowRunStep?
    var lastCompletedStep: LegacyWorkflowRunStep?
    var currentTerminalID: UUID?
    var latestPromptArtifactPath: String?
    var latestPromptPreview: String?
    var latestPlanSnapshot: WorkflowPlanSnapshot?
    var events: [WorkflowRunEvent]
    var startedAt: Date
    var updatedAt: Date
    var completedAt: Date?
}

private enum LegacyWorkflowRunStep: String, Codable {
    case executorExecute
    case executorSelfReview
    case reviewerAudit
}

private func legacyNormalizedOptionalString(
    _ value: String?
) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
