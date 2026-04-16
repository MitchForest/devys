import Dependencies
import Foundation

public struct WorkspaceAttentionIngressClient: Sendable {
    public var updates: @MainActor @Sendable () -> AsyncStream<WorkspaceAttentionIngressPayload>

    public init(
        updates: @escaping @MainActor @Sendable () -> AsyncStream<WorkspaceAttentionIngressPayload>
    ) {
        self.updates = updates
    }
}

extension WorkspaceAttentionIngressClient: DependencyKey {
    public static let liveValue = Self {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

extension WorkspaceAttentionIngressClient: TestDependencyKey {
    public static let testValue = Self {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

public extension DependencyValues {
    var workspaceAttentionIngressClient: WorkspaceAttentionIngressClient {
        get { self[WorkspaceAttentionIngressClient.self] }
        set { self[WorkspaceAttentionIngressClient.self] = newValue }
    }
}
