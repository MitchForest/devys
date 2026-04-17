import Dependencies
import Foundation

public struct WorkflowExecutionClient: Sendable {
    public var updates: @MainActor @Sendable () async -> AsyncStream<WorkflowExecutionUpdate>
    public var registerRuns: @MainActor @Sendable ([WorkflowRun]) async -> Void
    public var startNode: @MainActor @Sendable (WorkflowNodeLaunchRequest) async throws -> WorkflowNodeLaunchResult
    public var stopRun: @MainActor @Sendable (UUID) async -> Void

    public init(
        updates: @escaping @MainActor @Sendable () async -> AsyncStream<WorkflowExecutionUpdate>,
        registerRuns: @escaping @MainActor @Sendable ([WorkflowRun]) async -> Void,
        startNode: @escaping @MainActor @Sendable (WorkflowNodeLaunchRequest) async throws -> WorkflowNodeLaunchResult,
        stopRun: @escaping @MainActor @Sendable (UUID) async -> Void
    ) {
        self.updates = updates
        self.registerRuns = registerRuns
        self.startNode = startNode
        self.stopRun = stopRun
    }
}

extension WorkflowExecutionClient: DependencyKey {
    public static let liveValue = Self(
        updates: { AsyncStream { _ in } },
        registerRuns: { _ in },
        startNode: { request in
            WorkflowNodeLaunchResult(
                terminalID: UUID(),
                launchedCommand: request.prompt,
                promptArtifactPath: ""
            )
        },
        stopRun: { _ in }
    )
}

extension WorkflowExecutionClient: TestDependencyKey {
    public static let testValue = Self(
        updates: {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        registerRuns: { _ in },
        startNode: { request in
            WorkflowNodeLaunchResult(
                terminalID: UUID(),
                launchedCommand: request.prompt,
                promptArtifactPath: ""
            )
        },
        stopRun: { _ in }
    )
}

public extension DependencyValues {
    var workflowExecutionClient: WorkflowExecutionClient {
        get { self[WorkflowExecutionClient.self] }
        set { self[WorkflowExecutionClient.self] = newValue }
    }
}
