import Foundation
import Workspace

public extension WindowFeature {
    enum WorkspaceTransitionCatalogRefreshStrategy: String, Equatable, Sendable {
        case none
        case retryIfSelectionMissing
        case blockingTargetWorkspace
    }

    struct WorkspaceTransitionRequest: Equatable, Identifiable, Sendable {
        public let id: UUID
        public var sourceRepositoryID: Repository.ID?
        public var sourceWorkspaceID: Workspace.ID?
        public var targetRepositoryID: Repository.ID
        public var targetWorkspaceID: Workspace.ID?
        public var requiresRepositoryConfirmation: Bool
        public var shouldPersistVisibleWorkspaceState: Bool
        public var shouldResetHostWorkspaceState: Bool
        public var catalogRefreshStrategy: WorkspaceTransitionCatalogRefreshStrategy
        public var shouldScheduleDeferredRefresh: Bool

        public init(
            sourceRepositoryID: Repository.ID? = nil,
            sourceWorkspaceID: Workspace.ID? = nil,
            targetRepositoryID: Repository.ID,
            targetWorkspaceID: Workspace.ID? = nil,
            requiresRepositoryConfirmation: Bool,
            shouldPersistVisibleWorkspaceState: Bool,
            shouldResetHostWorkspaceState: Bool,
            catalogRefreshStrategy: WorkspaceTransitionCatalogRefreshStrategy,
            shouldScheduleDeferredRefresh: Bool,
            id: UUID = UUID()
        ) {
            self.id = id
            self.sourceRepositoryID = sourceRepositoryID
            self.sourceWorkspaceID = sourceWorkspaceID
            self.targetRepositoryID = targetRepositoryID
            self.targetWorkspaceID = targetWorkspaceID
            self.requiresRepositoryConfirmation = requiresRepositoryConfirmation
            self.shouldPersistVisibleWorkspaceState = shouldPersistVisibleWorkspaceState
            self.shouldResetHostWorkspaceState = shouldResetHostWorkspaceState
            self.catalogRefreshStrategy = catalogRefreshStrategy
            self.shouldScheduleDeferredRefresh = shouldScheduleDeferredRefresh
        }
    }
}
