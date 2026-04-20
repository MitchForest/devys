import Foundation
import Split
import Workspace

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

public extension WindowFeature.RepositoryCatalogSnapshot {
    func normalizedForReducer() -> Self {
        var normalizedWorktreesByRepository: [Repository.ID: [Worktree]] = [:]

        for (repositoryID, worktrees) in worktreesByRepository {
            normalizedWorktreesByRepository[repositoryID] = orderedWorktrees(
                worktrees,
                workspaceStatesByID: workspaceStatesByID
            )
        }

        return Self(
            repositories: repositories,
            worktreesByRepository: normalizedWorktreesByRepository,
            workspaceStatesByID: workspaceStatesByID
        )
    }
}

func workspaceLayoutSettingPreviewTabID(
    _ tabID: TabID?,
    in paneID: PaneID,
    layout: WindowFeature.WorkspaceLayout
) -> WindowFeature.WorkspaceLayout {
    WindowFeature.WorkspaceLayout(
        root: workspaceLayoutSettingPreviewTabID(tabID, in: paneID, node: layout.root)
    )
}

func workspaceLayoutSettingPreviewTabID(
    _ tabID: TabID?,
    in paneID: PaneID,
    node: WindowFeature.WorkspaceLayoutNode
) -> WindowFeature.WorkspaceLayoutNode {
    switch node {
    case .pane(var pane):
        guard pane.id == paneID else { return .pane(pane) }
        pane.previewTabID = tabID
        return .pane(pane)
    case .split(var split):
        split.first = workspaceLayoutSettingPreviewTabID(tabID, in: paneID, node: split.first)
        split.second = workspaceLayoutSettingPreviewTabID(tabID, in: paneID, node: split.second)
        return .split(split)
    }
}
