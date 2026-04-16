import Dependencies
import Foundation
import Git
import Workspace

public struct WorkspaceCatalogRefreshClient: Sendable {
    public var refreshRepositories:
        @MainActor @Sendable (
            WindowFeature.RepositoryCatalogSnapshot,
            [Repository.ID]
        ) async -> WindowFeature.RepositoryCatalogSnapshot

    public init(
        refreshRepositories: @escaping @MainActor @Sendable
            (
                WindowFeature.RepositoryCatalogSnapshot,
                [Repository.ID]
            ) async -> WindowFeature.RepositoryCatalogSnapshot
    ) {
        self.refreshRepositories = refreshRepositories
    }
}

extension WorkspaceCatalogRefreshClient: DependencyKey {
    public static let liveValue = Self { snapshot, _ in snapshot }
}

extension WorkspaceCatalogRefreshClient: TestDependencyKey {
    public static let testValue = Self(
        refreshRepositories: unimplemented(
            "\(Self.self).refreshRepositories",
            placeholder: WindowFeature.RepositoryCatalogSnapshot()
        )
    )
}

public extension DependencyValues {
    var workspaceCatalogRefreshClient: WorkspaceCatalogRefreshClient {
        get { self[WorkspaceCatalogRefreshClient.self] }
        set { self[WorkspaceCatalogRefreshClient.self] = newValue }
    }
}

public extension WorkspaceCatalogRefreshClient {
    static func live(
        gitWorktreeService: any GitWorktreeService = DefaultGitWorktreeService()
    ) -> Self {
        Self { snapshot, repositoryIDs in
            let targetRepositoryIDs = repositoryIDs.isEmpty
                ? Set(snapshot.repositories.map(\.id))
                : Set(repositoryIDs)
            var worktreesByRepository = snapshot.worktreesByRepository

            for repository in snapshot.repositories where targetRepositoryIDs.contains(repository.id) {
                let worktrees: [Worktree]
                do {
                    worktrees = try await gitWorktreeService.listWorktrees(for: repository.rootURL)
                } catch {
                    worktrees = []
                }

                worktreesByRepository[repository.id] = resolvedWorktrees(
                    for: repository,
                    worktrees: worktrees
                )
            }

            return WindowFeature.RepositoryCatalogSnapshot(
                repositories: snapshot.repositories,
                worktreesByRepository: worktreesByRepository,
                workspaceStatesByID: snapshot.workspaceStatesByID
            )
            .normalizedForReducer()
        }
    }
}

private func resolvedWorktrees(
    for repository: Repository,
    worktrees: [Worktree]
) -> [Worktree] {
    guard !worktrees.isEmpty else {
        return [
            Worktree(
                workingDirectory: repository.rootURL,
                repositoryRootURL: repository.rootURL,
                name: repository.rootURL.lastPathComponent,
                detail: "."
            )
        ]
    }

    return worktrees
}
