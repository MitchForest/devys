import Foundation
import Workspace

public struct WorkflowWorkspaceSnapshot: Codable, Equatable, Sendable {
    public var definitions: [WorkflowDefinition]
    public var runs: [WorkflowRun]

    public init(
        definitions: [WorkflowDefinition] = [],
        runs: [WorkflowRun] = []
    ) {
        self.definitions = definitions
        self.runs = runs
    }
}

public struct WorkflowDefinition: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var workers: [WorkflowWorker]
    public var nodes: [WorkflowNode]
    public var edges: [WorkflowEdge]
    public var artifactBindings: [WorkflowArtifactBinding]
    public var entryNodeID: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        workers: [WorkflowWorker],
        nodes: [WorkflowNode],
        edges: [WorkflowEdge],
        artifactBindings: [WorkflowArtifactBinding] = [],
        entryNodeID: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.workers = workers
        self.nodes = nodes
        self.edges = edges
        self.artifactBindings = artifactBindings
        self.entryNodeID = entryNodeID ?? nodes.first?.id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var planFilePath: String {
        get { artifactBinding(kind: .plan)?.path ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let bindingIndex = artifactBindings.firstIndex(where: { $0.kind == .plan }) {
                if trimmed.isEmpty {
                    artifactBindings.remove(at: bindingIndex)
                } else {
                    artifactBindings[bindingIndex].path = trimmed
                }
            } else if !trimmed.isEmpty {
                artifactBindings.append(
                    WorkflowArtifactBinding(
                        id: "plan",
                        kind: .plan,
                        path: trimmed
                    )
                )
            }
        }
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Workflow" : trimmed
    }

    public func artifactBinding(
        kind: WorkflowArtifactBindingKind
    ) -> WorkflowArtifactBinding? {
        artifactBindings.first { $0.kind == kind }
    }

    public func worker(
        id: String
    ) -> WorkflowWorker? {
        workers.first { $0.id == id }
    }

    public func node(
        id: String
    ) -> WorkflowNode? {
        nodes.first { $0.id == id }
    }

    public func outgoingEdges(
        from nodeID: String
    ) -> [WorkflowEdge] {
        edges.filter { $0.sourceNodeID == nodeID }
    }

    public func targetNode(
        for edgeID: String
    ) -> WorkflowNode? {
        guard let edge = edges.first(where: { $0.id == edgeID }) else { return nil }
        return node(id: edge.targetNodeID)
    }

    public var resolvedEntryNodeID: String? {
        if let entryNodeID, node(id: entryNodeID) != nil {
            return entryNodeID
        }
        return nodes.first?.id
    }

    public static func defaultDeliveryDefinition(
        id: String,
        now: Date
    ) -> Self {
        let implementer = WorkflowWorker.defaultImplementer()
        let reviewer = WorkflowWorker.defaultReviewer()

        let implementNode = WorkflowNode.agent(
            id: "implement",
            title: "Implement",
            workerID: implementer.id,
            frame: .init(x: -320, y: -40, width: 220, height: 120)
        )
        let reviewNode = WorkflowNode.agent(
            id: "review",
            title: "Review",
            workerID: reviewer.id,
            frame: .init(x: 0, y: -40, width: 220, height: 120)
        )
        let finishNode = WorkflowNode.finish(
            id: "finish",
            title: "Complete",
            frame: .init(x: 320, y: -40, width: 180, height: 100)
        )

        return WorkflowDefinition(
            id: id,
            name: "Delivery Loop",
            workers: [implementer, reviewer],
            nodes: [implementNode, reviewNode, finishNode],
            edges: [
                WorkflowEdge(
                    id: "implement-to-review",
                    sourceNodeID: implementNode.id,
                    targetNodeID: reviewNode.id
                ),
                WorkflowEdge(
                    id: "review-to-implement",
                    sourceNodeID: reviewNode.id,
                    targetNodeID: implementNode.id,
                    label: "Rework"
                ),
                WorkflowEdge(
                    id: "review-to-finish",
                    sourceNodeID: reviewNode.id,
                    targetNodeID: finishNode.id,
                    label: "Complete"
                )
            ],
            artifactBindings: [],
            entryNodeID: implementNode.id,
            createdAt: now,
            updatedAt: now
        )
    }
}

public struct WorkflowWorker: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var kind: WorkflowAgentKind
    public var launcher: LauncherTemplate
    public var executionMode: WorkflowExecutionMode
    public var promptFilePath: String
    public var prompt: String

    public init(
        id: String,
        displayName: String,
        kind: WorkflowAgentKind,
        launcher: LauncherTemplate,
        executionMode: WorkflowExecutionMode,
        promptFilePath: String,
        prompt: String
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.launcher = launcher
        self.executionMode = executionMode
        self.promptFilePath = promptFilePath
        self.prompt = prompt
    }

    public var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    public static func defaultImplementer() -> Self {
        WorkflowWorker(
            id: "implementer",
            displayName: "Implementer",
            kind: .claude,
            launcher: .claudeDefault,
            executionMode: .interactive,
            promptFilePath: "prompts/implement.md",
            prompt: WorkflowPromptDefaults.implement
        )
    }

    public static func defaultReviewer() -> Self {
        WorkflowWorker(
            id: "reviewer",
            displayName: "Reviewer",
            kind: .codex,
            launcher: .codexDefault,
            executionMode: .interactive,
            promptFilePath: "prompts/review.md",
            prompt: WorkflowPromptDefaults.review
        )
    }
}

public enum WorkflowAgentKind: String, Codable, CaseIterable, Equatable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude:
            "Claude Code"
        case .codex:
            "Codex"
        }
    }
}

public enum WorkflowExecutionMode: String, Codable, CaseIterable, Equatable, Sendable {
    case interactive
    case headless
}

public struct WorkflowNode: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var canvasID: UUID
    public var title: String
    public var kind: WorkflowNodeKind
    public var workerID: String?
    public var promptFilePath: String?
    public var promptOverride: String?
    public var frame: WorkflowNodeFrame
    public var completionSignal: WorkflowCompletionSignal

    public init(
        id: String,
        canvasID: UUID = UUID(),
        title: String,
        kind: WorkflowNodeKind,
        workerID: String? = nil,
        promptFilePath: String? = nil,
        promptOverride: String? = nil,
        frame: WorkflowNodeFrame = .defaultAgent,
        completionSignal: WorkflowCompletionSignal = .processExit
    ) {
        self.id = id
        self.canvasID = canvasID
        self.title = title
        self.kind = kind
        self.workerID = workerID
        self.promptFilePath = promptFilePath
        self.promptOverride = promptOverride
        self.frame = frame
        self.completionSignal = completionSignal
    }

    public var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    public static func agent(
        id: String = UUID().uuidString.lowercased(),
        title: String = "Agent",
        workerID: String,
        promptFilePath: String? = nil,
        promptOverride: String? = nil,
        frame: WorkflowNodeFrame = .defaultAgent
    ) -> Self {
        WorkflowNode(
            id: id,
            title: title,
            kind: .agent,
            workerID: workerID,
            promptFilePath: promptFilePath,
            promptOverride: promptOverride,
            frame: frame,
            completionSignal: .processExit
        )
    }

    public static func finish(
        id: String = UUID().uuidString.lowercased(),
        title: String = "Complete",
        frame: WorkflowNodeFrame = .defaultFinish
    ) -> Self {
        WorkflowNode(
            id: id,
            title: title,
            kind: .finish,
            frame: frame,
            completionSignal: .processExit
        )
    }
}

public enum WorkflowNodeKind: String, Codable, CaseIterable, Equatable, Sendable {
    case agent
    case finish

    public var displayName: String {
        switch self {
        case .agent:
            "Agent"
        case .finish:
            "Finish"
        }
    }
}

public enum WorkflowCompletionSignal: String, Codable, CaseIterable, Equatable, Sendable {
    case processExit
}

public struct WorkflowNodeFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let defaultAgent = WorkflowNodeFrame(
        x: 0,
        y: 0,
        width: 220,
        height: 120
    )

    public static let defaultFinish = WorkflowNodeFrame(
        x: 0,
        y: 0,
        width: 180,
        height: 100
    )
}

public struct WorkflowEdge: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var canvasID: UUID
    public var sourceNodeID: String
    public var targetNodeID: String
    public var label: String?

    public init(
        id: String = UUID().uuidString.lowercased(),
        canvasID: UUID = UUID(),
        sourceNodeID: String,
        targetNodeID: String,
        label: String? = nil
    ) {
        self.id = id
        self.canvasID = canvasID
        self.sourceNodeID = sourceNodeID
        self.targetNodeID = targetNodeID
        self.label = label
    }

    public var displayLabel: String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Next" : trimmed
    }
}

private extension WorkflowEdge {
    enum CodingKeys: String, CodingKey {
        case id
        case canvasID
        case sourceNodeID
        case targetNodeID
        case label
    }
}

public extension WorkflowEdge {
    init(
        from decoder: Decoder
    ) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.canvasID = try container.decodeIfPresent(UUID.self, forKey: .canvasID)
            ?? UUID(uuidString: id)
            ?? UUID()
        self.sourceNodeID = try container.decode(String.self, forKey: .sourceNodeID)
        self.targetNodeID = try container.decode(String.self, forKey: .targetNodeID)
        self.label = try container.decodeIfPresent(String.self, forKey: .label)
    }

    func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(canvasID, forKey: .canvasID)
        try container.encode(sourceNodeID, forKey: .sourceNodeID)
        try container.encode(targetNodeID, forKey: .targetNodeID)
        try container.encodeIfPresent(label, forKey: .label)
    }
}

public struct WorkflowArtifactBinding: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: WorkflowArtifactBindingKind
    public var path: String

    public init(
        id: String = UUID().uuidString.lowercased(),
        kind: WorkflowArtifactBindingKind,
        path: String
    ) {
        self.id = id
        self.kind = kind
        self.path = path
    }
}

public enum WorkflowArtifactBindingKind: String, Codable, CaseIterable, Equatable, Sendable {
    case plan
}

enum WorkflowPromptDefaults {
    static let implement = """
    You are the implementation worker for the active workflow node.

    Work only on the current task and the bound artifacts.
    If a markdown plan file is bound to this workflow:
    - update completed tickets directly in that file
    - append newly discovered follow-up work only inside explicit workflow-owned follow-up sections

    When your pass is done, stop.
    """

    static let review = """
    You are the review worker for the active workflow node.

    Audit the work completed so far against the bound plan and artifacts.
    If you discover more work:
    - append concrete follow-up tickets inside explicit workflow-owned follow-up sections
    - fix issues directly when appropriate for this node

    When your pass is done, stop.
    """
}
