import Dependencies
import Foundation
import Workspace

public struct WorkflowPersistenceClient: Sendable {
    public typealias PlanSnapshotLoader =
        @MainActor @Sendable (String, URL) async throws -> WorkflowPlanSnapshot
    public typealias PlanFollowUpAppender =
        @MainActor @Sendable (WorkflowPlanAppendRequest, URL) async throws -> WorkflowPlanSnapshot

    public var loadWorkspace: @MainActor @Sendable (Workspace.ID, URL) async throws -> WorkflowWorkspaceSnapshot
    public var saveDefinition: @MainActor @Sendable (WorkflowDefinition, URL) async throws -> Void
    public var deleteDefinition: @MainActor @Sendable (String, URL) async throws -> Void
    public var saveRun: @MainActor @Sendable (WorkflowRun, URL) async throws -> Void
    public var deleteRun: @MainActor @Sendable (UUID, URL) async throws -> Void
    public var loadPlanSnapshot: PlanSnapshotLoader
    public var appendFollowUpTicket: PlanFollowUpAppender

    public init(
        loadWorkspace: @escaping @MainActor @Sendable (Workspace.ID, URL) async throws -> WorkflowWorkspaceSnapshot,
        saveDefinition: @escaping @MainActor @Sendable (WorkflowDefinition, URL) async throws -> Void,
        deleteDefinition: @escaping @MainActor @Sendable (String, URL) async throws -> Void,
        saveRun: @escaping @MainActor @Sendable (WorkflowRun, URL) async throws -> Void,
        deleteRun: @escaping @MainActor @Sendable (UUID, URL) async throws -> Void,
        loadPlanSnapshot: @escaping PlanSnapshotLoader,
        appendFollowUpTicket: @escaping PlanFollowUpAppender
    ) {
        self.loadWorkspace = loadWorkspace
        self.saveDefinition = saveDefinition
        self.deleteDefinition = deleteDefinition
        self.saveRun = saveRun
        self.deleteRun = deleteRun
        self.loadPlanSnapshot = loadPlanSnapshot
        self.appendFollowUpTicket = appendFollowUpTicket
    }
}

extension WorkflowPersistenceClient: DependencyKey {
    public static let liveValue = Self(
        loadWorkspace: { _, _ in WorkflowWorkspaceSnapshot() },
        saveDefinition: { _, _ in },
        deleteDefinition: { _, _ in },
        saveRun: { _, _ in },
        deleteRun: { _, _ in },
        loadPlanSnapshot: { path, _ in
            WorkflowPlanSnapshot(planFilePath: path, phases: [])
        },
        appendFollowUpTicket: { request, _ in
            WorkflowPlanSnapshot(planFilePath: request.planFilePath, phases: [])
        }
    )
}

extension WorkflowPersistenceClient: TestDependencyKey {
    public static let testValue = Self(
        loadWorkspace: { _, _ in WorkflowWorkspaceSnapshot() },
        saveDefinition: { _, _ in },
        deleteDefinition: { _, _ in },
        saveRun: { _, _ in },
        deleteRun: { _, _ in },
        loadPlanSnapshot: { path, _ in
            WorkflowPlanSnapshot(planFilePath: path, phases: [])
        },
        appendFollowUpTicket: { request, _ in
            WorkflowPlanSnapshot(planFilePath: request.planFilePath, phases: [])
        }
    )
}

public extension DependencyValues {
    var workflowPersistenceClient: WorkflowPersistenceClient {
        get { self[WorkflowPersistenceClient.self] }
        set { self[WorkflowPersistenceClient.self] = newValue }
    }
}
