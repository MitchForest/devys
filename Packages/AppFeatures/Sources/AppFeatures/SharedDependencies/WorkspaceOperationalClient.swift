import Dependencies
import Foundation
import Workspace

public enum WorkspaceOperationalSyncMode: String, Equatable, Sendable {
    case structure
    case metadata
    case ports
    case all
}

public struct WorkspaceOperationalClient: Sendable {
    public var updates: @MainActor @Sendable () -> AsyncStream<WorkspaceOperationalSnapshot>
    public var sync: @MainActor @Sendable (
        WorkspaceOperationalCatalogContext,
        WorkspaceOperationalSyncMode
    ) -> Void
    public var markTerminalRead: @MainActor @Sendable (Workspace.ID?, UUID) -> Void
    public var requestMetadataRefresh: @MainActor @Sendable ([Workspace.ID], Repository.ID?) -> Void
    public var clearWorkspace: @MainActor @Sendable (Workspace.ID) -> Void

    public init(
        updates: @escaping @MainActor @Sendable () -> AsyncStream<WorkspaceOperationalSnapshot>,
        sync: @escaping @MainActor @Sendable (
            WorkspaceOperationalCatalogContext,
            WorkspaceOperationalSyncMode
        ) -> Void,
        markTerminalRead: @escaping @MainActor @Sendable (Workspace.ID?, UUID) -> Void,
        requestMetadataRefresh: @escaping @MainActor @Sendable ([Workspace.ID], Repository.ID?) -> Void,
        clearWorkspace: @escaping @MainActor @Sendable (Workspace.ID) -> Void
    ) {
        self.updates = updates
        self.sync = sync
        self.markTerminalRead = markTerminalRead
        self.requestMetadataRefresh = requestMetadataRefresh
        self.clearWorkspace = clearWorkspace
    }
}

extension WorkspaceOperationalClient: DependencyKey {
    public static let liveValue = Self(
        updates: {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        sync: { _, _ in },
        markTerminalRead: { _, _ in },
        requestMetadataRefresh: { _, _ in },
        clearWorkspace: { _ in }
    )
}

extension WorkspaceOperationalClient: TestDependencyKey {
    public static let testValue = Self(
        updates: {
            AsyncStream { continuation in
                continuation.finish()
            }
        },
        sync: { _, _ in },
        markTerminalRead: { _, _ in },
        requestMetadataRefresh: { _, _ in },
        clearWorkspace: { _ in }
    )
}

public extension DependencyValues {
    var workspaceOperationalClient: WorkspaceOperationalClient {
        get { self[WorkspaceOperationalClient.self] }
        set { self[WorkspaceOperationalClient.self] = newValue }
    }
}
