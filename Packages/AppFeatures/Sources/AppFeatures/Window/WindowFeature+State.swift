import Foundation
import Split
import Workspace

private struct WorktreeSortKey {
    let isArchived: Bool
    let pinnedOrder: Int
    let explicitOrder: Int
    let lastFocusedTime: TimeInterval
    let name: String
}

private func orderedWorktrees(
    _ worktrees: [Worktree],
    workspaceStatesByID: [Worktree.ID: WorktreeState]
) -> [Worktree] {
    worktrees.sorted { lhs, rhs in
        let left = worktreeSortKey(for: lhs, workspaceStatesByID: workspaceStatesByID)
        let right = worktreeSortKey(for: rhs, workspaceStatesByID: workspaceStatesByID)

        if left.isArchived != right.isArchived { return !left.isArchived && right.isArchived }
        if left.pinnedOrder != right.pinnedOrder { return left.pinnedOrder < right.pinnedOrder }
        if left.explicitOrder != right.explicitOrder {
            return left.explicitOrder < right.explicitOrder
        }
        if left.lastFocusedTime != right.lastFocusedTime {
            return left.lastFocusedTime > right.lastFocusedTime
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}

private func worktreeSortKey(
    for worktree: Worktree,
    workspaceStatesByID: [Worktree.ID: WorktreeState]
) -> WorktreeSortKey {
    let state = workspaceStatesByID[worktree.id] ?? WorktreeState(worktreeId: worktree.id)
    let displayName = state.displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
    return WorktreeSortKey(
        isArchived: state.isArchived,
        pinnedOrder: state.isPinned ? 0 : 1,
        explicitOrder: state.order ?? Int.max,
        lastFocusedTime: state.lastFocused?.timeIntervalSince1970 ?? 0,
        name: (displayName?.isEmpty == false ? displayName : nil) ?? worktree.name
    )
}

extension WindowFeature.State {
    var workspaceOperationalCatalogContext: WorkspaceOperationalCatalogContext {
        WorkspaceOperationalCatalogContext(
            repositories: repositories,
            worktreesByRepository: worktreesByRepository,
            selectedRepositoryID: selectedRepositoryID,
            selectedWorkspaceID: selectedWorkspaceID
        )
    }

    var repositoryCatalogSnapshot: WindowFeature.RepositoryCatalogSnapshot {
        WindowFeature.RepositoryCatalogSnapshot(
            repositories: repositories,
            worktreesByRepository: worktreesByRepository,
            workspaceStatesByID: workspaceStatesByID
        )
    }

    var visibleNavigatorWorkspaces: [(repositoryID: Repository.ID, workspace: Worktree)] {
        repositories.flatMap { repository in
            (worktreesByRepository[repository.id] ?? []).compactMap { worktree in
                let isArchived = workspaceStatesByID[worktree.id]?.isArchived == true
                return isArchived ? nil : (repository.id, worktree)
            }
        }
    }

    public var hasRepositories: Bool {
        !repositories.isEmpty
    }

    public var selectedRepository: Repository? {
        guard let selectedRepositoryID else { return nil }
        return repositories.first { $0.id == selectedRepositoryID }
    }

    var selectedWorktree: Worktree? {
        worktree(for: selectedWorkspaceID)
    }

    func worktree(for workspaceID: Workspace.ID?) -> Worktree? {
        guard let workspaceID else { return nil }
        return worktreesByRepository.values
            .flatMap { $0 }
            .first { $0.id == workspaceID }
    }

    func repositoryID(containing workspaceID: Workspace.ID) -> Repository.ID? {
        repositories.first { repository in
            worktreesByRepository[repository.id]?.contains { $0.id == workspaceID } == true
        }?.id
    }

    mutating func applyRepositoryCatalogSnapshot(
        _ snapshot: WindowFeature.RepositoryCatalogSnapshot
    ) {
        let normalizedSnapshot = snapshot.normalizedForReducer()
        repositories = normalizedSnapshot.repositories
        worktreesByRepository = normalizedSnapshot.worktreesByRepository
        workspaceStatesByID = normalizedSnapshot.workspaceStatesByID
        normalizeSelection()
    }

    mutating func openResolvedRepositories(
        _ repositories: [Repository]
    ) -> [URL] {
        let uniqueRepositories = uniqueRepositoriesForOpen(repositories)
        guard let lastRepository = uniqueRepositories.last else {
            return []
        }

        importRepositories(
            uniqueRepositories,
            selectLast: selectedRepositoryID != lastRepository.id
        )
        return uniqueRepositories.map(\.rootURL)
    }

    mutating func importRepositories(
        _ repositories: [Repository],
        selectLast: Bool
    ) {
        for repository in repositories {
            if let existingIndex = self.repositories.firstIndex(where: { $0.id == repository.id }) {
                self.repositories[existingIndex] = repository
            } else {
                self.repositories.append(repository)
            }
        }

        if selectLast {
            selectedRepositoryID = repositories.last?.id ?? selectedRepositoryID
            selectedWorkspaceID = nil
        }

        lastErrorMessage = nil
        normalizeSelection()
        if selectLast {
            restoreWorkspaceShell(for: selectedWorkspaceID)
        }
    }

    func uniqueRepositoriesForOpen(_ repositories: [Repository]) -> [Repository] {
        var seenRepositoryIDs: Set<Repository.ID> = []
        return repositories.filter { repository in
            seenRepositoryIDs.insert(repository.id).inserted
        }
    }

    mutating func normalizeSelection() {
        guard !repositories.isEmpty else {
            selectedRepositoryID = nil
            selectedWorkspaceID = nil
            selectedTabID = nil
            return
        }

        if let selectedRepositoryID,
           repositories.contains(where: { $0.id == selectedRepositoryID }) {
            normalizeWorkspaceSelection(in: selectedRepositoryID)
            return
        }

        selectedRepositoryID = repositories.last?.id
        if let selectedRepositoryID {
            normalizeWorkspaceSelection(in: selectedRepositoryID)
        } else {
            selectedWorkspaceID = nil
        }
        selectedTabID = nil
    }

    mutating func normalizeWorkspaceSelection(in repositoryID: Repository.ID) {
        let worktrees = worktreesByRepository[repositoryID] ?? []

        if let selectedWorkspaceID,
           worktrees.contains(where: { $0.id == selectedWorkspaceID }),
           workspaceStatesByID[selectedWorkspaceID]?.isArchived != true {
            return
        }

        selectedWorkspaceID = worktrees.first { workspace in
            workspaceStatesByID[workspace.id]?.isArchived != true
        }?.id
    }

    mutating func moveRepository(
        _ repositoryID: Repository.ID,
        by offset: Int
    ) {
        guard let currentIndex = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }

        let destinationIndex = max(0, min(repositories.count - 1, currentIndex + offset))
        guard destinationIndex != currentIndex else { return }

        let repository = repositories.remove(at: currentIndex)
        repositories.insert(repository, at: destinationIndex)
    }

    mutating func reorderRepository(
        _ repositoryID: Repository.ID,
        toIndex destinationIndex: Int
    ) {
        guard let currentIndex = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }
        guard currentIndex != destinationIndex else { return }

        let repository = repositories.remove(at: currentIndex)
        let clampedIndex = max(0, min(repositories.count, destinationIndex))
        repositories.insert(repository, at: clampedIndex)
    }

    mutating func setRepositoryDisplayInitials(
        _ repositoryID: Repository.ID,
        initials: String?
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
        let trimmed = initials?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            repositories[index].displayInitials = String(trimmed.prefix(2))
        } else {
            repositories[index].displayInitials = nil
        }
    }

    mutating func setRepositoryDisplaySymbol(
        _ repositoryID: Repository.ID,
        symbol: String?
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else { return }
        repositories[index].displaySymbol = symbol
    }

    mutating func removeRepository(_ repositoryID: Repository.ID) {
        let removedWorkspaceIDs = Set((worktreesByRepository[repositoryID] ?? []).map(\.id))
        repositories.removeAll { $0.id == repositoryID }
        worktreesByRepository.removeValue(forKey: repositoryID)

        for workspaceID in removedWorkspaceIDs {
            workspaceStatesByID.removeValue(forKey: workspaceID)
            hostedWorkspaceContentByID.removeValue(forKey: workspaceID)
            workflowWorkspacesByID.removeValue(forKey: workspaceID)
            workspaceShells.removeValue(forKey: workspaceID)
            operational.removeWorkspace(workspaceID)
        }

        normalizeSelection()
    }

    mutating func setRepositorySourceControl(
        _ sourceControl: RepositorySourceControl,
        for repositoryID: Repository.ID
    ) {
        guard let index = repositories.firstIndex(where: { $0.id == repositoryID }) else {
            return
        }
        repositories[index].sourceControl = sourceControl
    }

    mutating func setWorkspacePinned(
        _ workspaceID: Workspace.ID,
        in repositoryID: Repository.ID,
        isPinned: Bool
    ) {
        updateWorkspaceState(workspaceID, in: repositoryID) { state in
            state.isPinned = isPinned
        }
        reorderWorktrees(in: repositoryID)
    }

    mutating func setWorkspaceArchived(
        _ workspaceID: Workspace.ID,
        in repositoryID: Repository.ID,
        isArchived: Bool
    ) {
        updateWorkspaceState(workspaceID, in: repositoryID) { state in
            state.isArchived = isArchived
        }
        reorderWorktrees(in: repositoryID)
        if selectedRepositoryID == repositoryID {
            normalizeWorkspaceSelection(in: repositoryID)
        }
    }

    mutating func setWorkspaceDisplayName(
        _ displayName: String?,
        for workspaceID: Workspace.ID,
        in repositoryID: Repository.ID
    ) {
        updateWorkspaceState(workspaceID, in: repositoryID) { state in
            let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            state.displayNameOverride = (trimmed?.isEmpty == false) ? trimmed : nil
        }
        reorderWorktrees(in: repositoryID)
    }

    mutating func removeWorkspaceState(
        _ workspaceID: Workspace.ID,
        in repositoryID: Repository.ID
    ) {
        guard worktreesByRepository[repositoryID]?.contains(where: { $0.id == workspaceID }) == true else {
            return
        }
        workspaceStatesByID.removeValue(forKey: workspaceID)
        operational.removeWorkspace(workspaceID)
        reorderWorktrees(in: repositoryID)
        if selectedRepositoryID == repositoryID {
            normalizeWorkspaceSelection(in: repositoryID)
        }
    }

    mutating func persistActiveWorkspaceShellIfNeeded() {
        guard let selectedWorkspaceID else { return }
        var shell = workspaceShells[selectedWorkspaceID]
            ?? WindowFeature.WorkspaceShell(activeSidebar: activeSidebar)
        shell.activeSidebar = activeSidebar
        if shell.focusedPaneID == nil {
            shell.focusedPaneID = shell.layout?.focusedFallbackPaneID
        }
        workspaceShells[selectedWorkspaceID] = shell
    }

    mutating func restoreWorkspaceShell(for workspaceID: Workspace.ID?) {
        selectedWorkspaceID = workspaceID

        guard let workspaceID else {
            selectedTabID = nil
            return
        }

        let shell = workspaceShells[workspaceID]
            ?? WindowFeature.WorkspaceShell(activeSidebar: activeSidebar)
        activeSidebar = shell.activeSidebar
        let focusedPaneID = shell.focusedPaneID ?? shell.layout?.focusedFallbackPaneID
        selectedTabID = shell.layout?.selectedTabID(in: focusedPaneID)
    }

    mutating func updateActiveWorkspaceShell(
        _ update: (inout WindowFeature.WorkspaceShell) -> Void
    ) {
        guard let selectedWorkspaceID else { return }
        var shell = workspaceShells[selectedWorkspaceID]
            ?? WindowFeature.WorkspaceShell(activeSidebar: activeSidebar)
        update(&shell)
        workspaceShells[selectedWorkspaceID] = shell
        if self.selectedWorkspaceID == selectedWorkspaceID {
            let focusedPaneID = shell.focusedPaneID ?? shell.layout?.focusedFallbackPaneID
            selectedTabID = shell.layout?.selectedTabID(in: focusedPaneID)
        }
    }

    mutating func clearWorkspacePreviewTabID(
        workspaceID: Workspace.ID,
        matching tabID: TabID
    ) {
        guard var shell = workspaceShells[workspaceID],
              let layout = shell.layout else {
            return
        }

        shell.layout = WindowFeature.WorkspaceLayout(
            root: clearingPreviewTabID(tabID, in: layout.root)
        )
        workspaceShells[workspaceID] = shell
    }

    private func clearingPreviewTabID(
        _ tabID: TabID,
        in node: WindowFeature.WorkspaceLayoutNode
    ) -> WindowFeature.WorkspaceLayoutNode {
        switch node {
        case .pane(var pane):
            if pane.previewTabID == tabID {
                pane.previewTabID = nil
            }
            return .pane(pane)
        case .split(var split):
            split.first = clearingPreviewTabID(tabID, in: split.first)
            split.second = clearingPreviewTabID(tabID, in: split.second)
            return .split(split)
        }
    }

    mutating func updateWorkspaceState(
        _ workspaceID: Workspace.ID,
        in repositoryID: Repository.ID,
        update: (inout WorktreeState) -> Void
    ) {
        guard worktreesByRepository[repositoryID]?.contains(where: { $0.id == workspaceID }) == true else {
            return
        }
        var state = workspaceStatesByID[workspaceID] ?? WorktreeState(worktreeId: workspaceID)
        update(&state)
        workspaceStatesByID[workspaceID] = state
    }

    mutating func reorderWorktrees(in repositoryID: Repository.ID) {
        guard let worktrees = worktreesByRepository[repositoryID] else { return }
        worktreesByRepository[repositoryID] = orderedWorktrees(
            worktrees,
            workspaceStatesByID: workspaceStatesByID
        )
    }

    func adjacentVisibleWorkspace(offset: Int) -> (repositoryID: Repository.ID, workspace: Worktree)? {
        let workspaces = visibleNavigatorWorkspaces
        guard !workspaces.isEmpty else { return nil }

        guard let selectedWorkspaceID,
              let currentIndex = workspaces.firstIndex(where: { $0.workspace.id == selectedWorkspaceID }) else {
            let fallbackIndex = offset >= 0 ? 0 : max(0, workspaces.count - 1)
            return workspaces[fallbackIndex]
        }

        let nextIndex = max(0, min(workspaces.count - 1, currentIndex + offset))
        guard nextIndex != currentIndex else { return nil }
        return workspaces[nextIndex]
    }

}

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
