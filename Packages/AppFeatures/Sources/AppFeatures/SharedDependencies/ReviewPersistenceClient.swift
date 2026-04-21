import Dependencies
import Foundation
import Workspace

public struct ReviewPersistenceClient: Sendable {
    public typealias WorkspaceLoader =
        @MainActor @Sendable (Workspace.ID, URL) async throws -> ReviewWorkspaceSnapshot
    public typealias RunSaver =
        @MainActor @Sendable (ReviewRun, [ReviewIssue], URL) async throws -> Void

    public var loadWorkspace: WorkspaceLoader
    public var saveRun: RunSaver
    public var deleteRun: @MainActor @Sendable (UUID, URL) async throws -> Void

    public init(
        loadWorkspace: @escaping WorkspaceLoader,
        saveRun: @escaping RunSaver,
        deleteRun: @escaping @MainActor @Sendable (UUID, URL) async throws -> Void
    ) {
        self.loadWorkspace = loadWorkspace
        self.saveRun = saveRun
        self.deleteRun = deleteRun
    }
}

extension ReviewPersistenceClient: DependencyKey {
    public static let liveValue = Self(
        loadWorkspace: { _, _ in ReviewWorkspaceSnapshot() },
        saveRun: { _, _, _ in },
        deleteRun: { _, _ in }
    )
}

extension ReviewPersistenceClient: TestDependencyKey {
    public static let testValue = Self(
        loadWorkspace: { _, _ in ReviewWorkspaceSnapshot() },
        saveRun: { _, _, _ in },
        deleteRun: { _, _ in }
    )
}

public extension DependencyValues {
    var reviewPersistenceClient: ReviewPersistenceClient {
        get { self[ReviewPersistenceClient.self] }
        set { self[ReviewPersistenceClient.self] = newValue }
    }
}
