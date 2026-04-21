import Dependencies
import Foundation
import Workspace

public struct ReviewTriggerRequest: Codable, Equatable, Sendable {
    public var workspaceID: Workspace.ID?
    public var repositoryRootURL: URL
    public var target: ReviewTarget
    public var trigger: ReviewTrigger

    public init(
        workspaceID: Workspace.ID? = nil,
        repositoryRootURL: URL,
        target: ReviewTarget,
        trigger: ReviewTrigger
    ) {
        self.workspaceID = workspaceID
        self.repositoryRootURL = repositoryRootURL
        self.target = target
        self.trigger = trigger
    }
}

public struct ReviewTriggerIngressClient: Sendable {
    public var updates: @MainActor @Sendable () -> AsyncStream<ReviewTriggerRequest>

    public init(
        updates: @escaping @MainActor @Sendable () -> AsyncStream<ReviewTriggerRequest>
    ) {
        self.updates = updates
    }
}

extension ReviewTriggerIngressClient: DependencyKey {
    public static let liveValue = Self {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

extension ReviewTriggerIngressClient: TestDependencyKey {
    public static let testValue = Self {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

public extension DependencyValues {
    var reviewTriggerIngressClient: ReviewTriggerIngressClient {
        get { self[ReviewTriggerIngressClient.self] }
        set { self[ReviewTriggerIngressClient.self] = newValue }
    }
}
