import Foundation
import Workspace

struct StubCatalogWorktreeListingService: WorktreeListingService {
    let worktreesByRepositoryRoot: [String: [Worktree]]

    func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree] {
        worktreesByRepositoryRoot[repositoryRoot.standardizedFileURL.path] ?? []
    }
}
