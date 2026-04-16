import Dependencies
import Foundation
import Workspace

public struct WorkspaceCatalogPersistenceClient: Sendable {
    public var loadWorkspaceStates: @MainActor @Sendable () -> [WorktreeState]
    public var saveRepositories: @MainActor @Sendable ([Repository]) -> Void
    public var saveWorkspaceStates: @MainActor @Sendable ([WorktreeState]) -> Void

    public init(
        loadWorkspaceStates: @escaping @MainActor @Sendable () -> [WorktreeState],
        saveRepositories: @escaping @MainActor @Sendable ([Repository]) -> Void,
        saveWorkspaceStates: @escaping @MainActor @Sendable ([WorktreeState]) -> Void
    ) {
        self.loadWorkspaceStates = loadWorkspaceStates
        self.saveRepositories = saveRepositories
        self.saveWorkspaceStates = saveWorkspaceStates
    }
}

extension WorkspaceCatalogPersistenceClient: DependencyKey {
    public static let liveValue = Self(
        loadWorkspaceStates: { [] },
        saveRepositories: { _ in },
        saveWorkspaceStates: { _ in }
    )
}

extension WorkspaceCatalogPersistenceClient: TestDependencyKey {
    public static let testValue = Self(
        loadWorkspaceStates: { [] },
        saveRepositories: { _ in },
        saveWorkspaceStates: { _ in }
    )
}

public extension DependencyValues {
    var workspaceCatalogPersistenceClient: WorkspaceCatalogPersistenceClient {
        get { self[WorkspaceCatalogPersistenceClient.self] }
        set { self[WorkspaceCatalogPersistenceClient.self] = newValue }
    }
}

public extension WorkspaceCatalogPersistenceClient {
    static func live(
        repositoryPersistenceService: any RepositoryPersistenceService =
            UserDefaultsRepositoryPersistenceService(),
        worktreePersistenceService: any WorktreePersistenceService =
            UserDefaultsWorktreePersistenceService()
    ) -> Self {
        Self(
            loadWorkspaceStates: {
                worktreePersistenceService.loadStates()
            },
            saveRepositories: { repositories in
                repositoryPersistenceService.saveRepositories(repositories)
            },
            saveWorkspaceStates: { workspaceStates in
                worktreePersistenceService.saveStates(workspaceStates)
            }
        )
    }
}
