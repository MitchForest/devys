import Foundation
import Workspace

struct WindowCatalogRuntimeSnapshot: Equatable {
    var repositories: [Repository]
    var worktreesByRepository: [Repository.ID: [Worktree]]
    var selectedRepositoryID: Repository.ID?
    var selectedWorkspaceID: Workspace.ID?
}
