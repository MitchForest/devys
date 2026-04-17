import Foundation
import Workspace

public struct WorkflowRun: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var definitionID: String
    public var workspaceID: Workspace.ID
    public var worktreePath: String
    public var branchName: String
    public var status: WorkflowRunStatus
    public var currentNodeID: String?
    public var activeAttemptID: UUID?
    public var currentTerminalID: UUID?
    public var latestPlanSnapshot: WorkflowPlanSnapshot?
    public var attempts: [WorkflowRunAttempt]
    public var events: [WorkflowRunEvent]
    public var startedAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: UUID,
        definitionID: String,
        workspaceID: Workspace.ID,
        worktreePath: String,
        branchName: String,
        status: WorkflowRunStatus = .idle,
        currentNodeID: String? = nil,
        activeAttemptID: UUID? = nil,
        currentTerminalID: UUID? = nil,
        latestPlanSnapshot: WorkflowPlanSnapshot? = nil,
        attempts: [WorkflowRunAttempt] = [],
        events: [WorkflowRunEvent] = [],
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.definitionID = definitionID
        self.workspaceID = workspaceID
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.status = status
        self.currentNodeID = currentNodeID
        self.activeAttemptID = activeAttemptID
        self.currentTerminalID = currentTerminalID
        self.latestPlanSnapshot = latestPlanSnapshot
        self.attempts = attempts
        self.events = events
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    public var activeAttempt: WorkflowRunAttempt? {
        if let activeAttemptID {
            return attempts.first { $0.id == activeAttemptID }
        }
        return attempts.first { $0.status == .running }
    }

    public var latestAttempt: WorkflowRunAttempt? {
        attempts.last
    }

    public var latestPromptArtifactPath: String? {
        activeAttempt?.promptArtifactPath ?? latestAttempt?.promptArtifactPath
    }

    public var latestPromptPreview: String? {
        activeAttempt?.promptPreview ?? latestAttempt?.promptPreview
    }

    public var currentPhaseTitle: String? {
        latestPlanSnapshot?.currentPhase?.title
    }

    public var displayStatus: String {
        switch status {
        case .idle:
            "Idle"
        case .running:
            "Running"
        case .awaitingOperator:
            "Awaiting Choice"
        case .interrupted:
            "Interrupted"
        case .failed(let message):
            message.isEmpty ? "Failed" : message
        case .completed:
            "Completed"
        }
    }
}

public enum WorkflowRunStatus: Codable, Equatable, Sendable {
    case idle
    case running
    case awaitingOperator
    case interrupted
    case failed(String)
    case completed

    public var isActive: Bool {
        switch self {
        case .running, .awaitingOperator, .interrupted:
            true
        case .idle, .failed, .completed:
            false
        }
    }
}

public struct WorkflowRunAttempt: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var nodeID: String
    public var workerID: String?
    public var status: WorkflowRunAttemptStatus
    public var terminalID: UUID?
    public var promptArtifactPath: String?
    public var promptPreview: String?
    public var launchedCommand: String?
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: UUID = UUID(),
        nodeID: String,
        workerID: String? = nil,
        status: WorkflowRunAttemptStatus = .running,
        terminalID: UUID? = nil,
        promptArtifactPath: String? = nil,
        promptPreview: String? = nil,
        launchedCommand: String? = nil,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.workerID = workerID
        self.status = status
        self.terminalID = terminalID
        self.promptArtifactPath = promptArtifactPath
        self.promptPreview = promptPreview
        self.launchedCommand = launchedCommand
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum WorkflowRunAttemptStatus: Codable, Equatable, Sendable {
    case running
    case completed
    case interrupted
    case failed(String)
}

public struct WorkflowRunEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var level: WorkflowRunEventLevel
    public var message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: WorkflowRunEventLevel = .info,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
    }
}

public enum WorkflowRunEventLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case info
    case warning
    case error
}

public struct WorkflowPlanSnapshot: Codable, Equatable, Sendable {
    public var planFilePath: String
    public var phases: [WorkflowPlanPhase]

    public init(
        planFilePath: String,
        phases: [WorkflowPlanPhase]
    ) {
        self.planFilePath = planFilePath
        self.phases = phases
    }

    public var currentPhaseIndex: Int? {
        phases.firstIndex { !$0.openTickets.isEmpty }
    }

    public var currentPhase: WorkflowPlanPhase? {
        guard let currentPhaseIndex else { return nil }
        return phases[safe: currentPhaseIndex]
    }

    public var hasOpenTickets: Bool {
        phases.contains { !$0.openTickets.isEmpty }
    }
}

public struct WorkflowPlanPhase: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var headingLine: Int
    public var tickets: [WorkflowPlanTicket]

    public init(
        id: String,
        title: String,
        headingLine: Int,
        tickets: [WorkflowPlanTicket]
    ) {
        self.id = id
        self.title = title
        self.headingLine = headingLine
        self.tickets = tickets
    }

    public var openTickets: [WorkflowPlanTicket] {
        tickets.filter { !$0.isCompleted }
    }
}

public struct WorkflowPlanTicket: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var isCompleted: Bool
    public var line: Int
    public var section: WorkflowPlanSection

    public init(
        id: String,
        text: String,
        isCompleted: Bool,
        line: Int,
        section: WorkflowPlanSection
    ) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        self.line = line
        self.section = section
    }
}

public enum WorkflowPlanSection: Codable, Equatable, Sendable {
    case phaseBody
    case followUps
    case named(String)

    public var displayName: String {
        switch self {
        case .phaseBody:
            "Phase"
        case .followUps:
            "Follow-Ups"
        case .named(let value):
            value
        }
    }
}

public struct WorkflowPlanAppendRequest: Equatable, Sendable {
    public var planFilePath: String
    public var phaseIndex: Int
    public var sectionTitle: String
    public var text: String

    public init(
        planFilePath: String,
        phaseIndex: Int,
        sectionTitle: String = "Follow-Ups",
        text: String
    ) {
        self.planFilePath = planFilePath
        self.phaseIndex = phaseIndex
        self.sectionTitle = sectionTitle
        self.text = text
    }
}

public struct WorkflowNodeLaunchRequest: Equatable, Sendable {
    public var runID: UUID
    public var attemptID: UUID
    public var workspaceID: Workspace.ID
    public var workingDirectoryURL: URL
    public var node: WorkflowNode
    public var worker: WorkflowWorker
    public var prompt: String

    public init(
        runID: UUID,
        attemptID: UUID,
        workspaceID: Workspace.ID,
        workingDirectoryURL: URL,
        node: WorkflowNode,
        worker: WorkflowWorker,
        prompt: String
    ) {
        self.runID = runID
        self.attemptID = attemptID
        self.workspaceID = workspaceID
        self.workingDirectoryURL = workingDirectoryURL
        self.node = node
        self.worker = worker
        self.prompt = prompt
    }
}

public struct WorkflowNodeLaunchResult: Equatable, Sendable {
    public var terminalID: UUID
    public var launchedCommand: String
    public var promptArtifactPath: String

    public init(
        terminalID: UUID,
        launchedCommand: String,
        promptArtifactPath: String
    ) {
        self.terminalID = terminalID
        self.launchedCommand = launchedCommand
        self.promptArtifactPath = promptArtifactPath
    }
}

public enum WorkflowExecutionUpdate: Equatable, Sendable {
    case terminalExited(runID: UUID, terminalID: UUID)
    case terminalRestoreMissing(runID: UUID, terminalID: UUID)
}
