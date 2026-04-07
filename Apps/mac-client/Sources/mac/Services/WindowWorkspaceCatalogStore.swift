// WindowWorkspaceCatalogStore.swift
// Devys - Window-owned repository and workspace catalog.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Observation
import Workspace
import Git

@MainActor
@Observable
final class WindowWorkspaceCatalogStore {
    typealias WorktreeManagerFactory = @MainActor () -> WorktreeManager

    private let worktreeManagerFactory: WorktreeManagerFactory
    private var managersByRepositoryID: [Repository.ID: WorktreeManager] = [:]

    private(set) var repositories: [Repository] = []
    private(set) var worktreesByRepository: [Repository.ID: [Worktree]] = [:]
    private(set) var selectedRepositoryID: Repository.ID?
    private(set) var selectedWorkspaceID: Workspace.ID?

    init(
        worktreeManagerFactory: @escaping WorktreeManagerFactory = {
            WorktreeManager(listingService: DefaultGitWorktreeService())
        }
    ) {
        self.worktreeManagerFactory = worktreeManagerFactory
    }
}

@MainActor
extension WindowWorkspaceCatalogStore {
    var hasRepositories: Bool {
        !repositories.isEmpty
    }

    var selectedRepository: Repository? {
        guard let selectedRepositoryID else { return nil }
        return repositories.first { $0.id == selectedRepositoryID }
    }

    var selectedRepositoryRootURL: URL? {
        selectedRepository?.rootURL
    }

    var selectedWorktree: Worktree? {
        guard let selectedRepositoryID,
              let selectedWorkspaceID else {
            return nil
        }
        return worktreesByRepository[selectedRepositoryID]?.first { $0.id == selectedWorkspaceID }
    }

    var workspaceStatesByID: [Worktree.ID: WorktreeState] {
        managersByRepositoryID.values.reduce(into: [:]) { partialResult, manager in
            for (workspaceID, state) in manager.statesById {
                partialResult[workspaceID] = state
            }
        }
    }

    func repository(for repositoryID: Repository.ID) -> Repository? {
        repositories.first { $0.id == repositoryID }
    }

    func hasResolvedRepository(_ repositoryID: Repository.ID) -> Bool {
        worktreesByRepository[repositoryID] != nil
    }

    func canResolveWorkspaceSelection(
        _ workspaceID: Workspace.ID,
        in repositoryID: Repository.ID
    ) -> Bool {
        worktreesByRepository[repositoryID]?.contains { $0.id == workspaceID } == true
    }

    func repositoryContainingWorkspace(_ workspaceID: Workspace.ID) -> Repository? {
        repositories.first { repository in
            worktreesByRepository[repository.id]?.contains { $0.id == workspaceID } == true
        }
    }

    func workspaceContext(
        for workspaceID: Workspace.ID
    ) -> (repository: Repository, worktree: Worktree)? {
        guard let repository = repositoryContainingWorkspace(workspaceID),
              let worktree = worktreesByRepository[repository.id]?.first(where: { $0.id == workspaceID }) else {
            return nil
        }
        return (repository, worktree)
    }

    func worktreeState(for workspaceID: Workspace.ID) -> WorktreeState? {
        workspaceStatesByID[workspaceID]
    }

    func displayName(for worktree: Worktree) -> String {
        manager(forRepositoryRootURL: worktree.repositoryRootURL)?.displayName(for: worktree) ?? worktree.name
    }

    func visibleNavigatorWorkspaces() -> [(repositoryID: Repository.ID, workspace: Worktree)] {
        repositories.flatMap { repository in
            (worktreesByRepository[repository.id] ?? []).compactMap { worktree in
                let isArchived = manager(for: repository.id)?.state(for: worktree.id)?.isArchived == true
                return isArchived ? nil : (repository.id, worktree)
            }
        }
    }

    func importRepository(_ repository: Repository) {
        if let existingIndex = repositories.firstIndex(where: { $0.id == repository.id }) {
            repositories[existingIndex] = repository
        } else {
            repositories.append(repository)
        }

        _ = ensureManager(for: repository.id)
        selectedRepositoryID = repository.id
        selectedWorkspaceID = nil
        normalizeSelection()
    }

    func removeRepository(_ repositoryID: Repository.ID) {
        repositories.removeAll { $0.id == repositoryID }
        worktreesByRepository.removeValue(forKey: repositoryID)
        managersByRepositoryID.removeValue(forKey: repositoryID)
        if selectedRepositoryID == repositoryID {
            selectedRepositoryID = repositories.last?.id
            selectedWorkspaceID = selectedRepositoryID.flatMap { manager(for: $0)?.selection.selectedWorktreeId }
        }
        normalizeSelection()
    }

    func selectRepository(_ repositoryID: Repository.ID?) {
        selectedRepositoryID = repositoryID
        if let repositoryID {
            selectedWorkspaceID = manager(for: repositoryID)?.selection.selectedWorktreeId
        } else {
            selectedWorkspaceID = nil
        }
        normalizeSelection()
    }

    func selectWorkspace(
        _ workspaceID: Workspace.ID?,
        in repositoryID: Repository.ID? = nil
    ) {
        if let repositoryID {
            selectedRepositoryID = repositoryID
        }

        guard let selectedRepositoryID else {
            selectedWorkspaceID = nil
            return
        }

        let manager = ensureManager(for: selectedRepositoryID)
        manager.selectWorktree(workspaceID)
        selectedWorkspaceID = manager.selection.selectedWorktreeId
        normalizeSelection()
    }

    func restoreSelection(
        repositoryID: Repository.ID?,
        workspaceID: Workspace.ID?
    ) {
        selectedRepositoryID = repositoryID
        selectedWorkspaceID = workspaceID
        normalizeSelection()
    }

    func refreshRepositories(_ repositoryIDs: [Repository.ID]? = nil) async {
        let targetRepositoryIDs = repositoryIDs ?? repositories.map(\.id)
        for repositoryID in targetRepositoryIDs {
            await refreshRepository(repositoryID: repositoryID)
        }
    }

    func refreshRepository(repositoryID: Repository.ID) async {
        guard let repository = repository(for: repositoryID) else { return }
        let manager = ensureManager(for: repositoryID)
        await manager.refresh(for: repository.rootURL)

        if selectedRepositoryID == repositoryID,
           let selectedWorkspaceID,
           manager.worktrees.contains(where: { $0.id == selectedWorkspaceID }) {
            manager.selectWorktree(selectedWorkspaceID)
        }

        worktreesByRepository[repositoryID] = orderedWorktrees(
            for: manager,
            worktrees: manager.worktrees
        )

        if selectedRepositoryID == repositoryID {
            selectedWorkspaceID = manager.selection.selectedWorktreeId
        }

        normalizeSelection()
    }

    func setWorkspacePinned(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID,
        isPinned: Bool
    ) {
        guard let manager = manager(for: repositoryID) else { return }
        manager.setPinned(workspaceID, isPinned: isPinned)
        reorderRepository(repositoryID)
    }

    func setWorkspaceArchived(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID,
        isArchived: Bool
    ) {
        guard let manager = manager(for: repositoryID) else { return }
        manager.setArchived(workspaceID, isArchived: isArchived)
        reorderRepository(repositoryID)

        if selectedRepositoryID == repositoryID {
            selectedWorkspaceID = manager.selection.selectedWorktreeId
            normalizeSelection()
        }
    }

    func setWorkspaceDisplayName(
        _ value: String?,
        for workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) {
        guard let manager = manager(for: repositoryID) else { return }
        manager.setDisplayNameOverride(value, for: workspaceID)
        reorderRepository(repositoryID)
    }

    func removeWorkspaceState(
        _ workspaceID: Worktree.ID,
        in repositoryID: Repository.ID
    ) {
        guard let manager = manager(for: repositoryID) else { return }
        manager.removeState(for: workspaceID)
        reorderRepository(repositoryID)
        if selectedRepositoryID == repositoryID {
            selectedWorkspaceID = manager.selection.selectedWorktreeId
            normalizeSelection()
        }
    }
}

@MainActor
private extension WindowWorkspaceCatalogStore {
    func ensureManager(for repositoryID: Repository.ID) -> WorktreeManager {
        if let existing = managersByRepositoryID[repositoryID] {
            return existing
        }

        let manager = worktreeManagerFactory()
        managersByRepositoryID[repositoryID] = manager
        return manager
    }

    func manager(for repositoryID: Repository.ID) -> WorktreeManager? {
        managersByRepositoryID[repositoryID]
    }

    func manager(forRepositoryRootURL repositoryRootURL: URL) -> WorktreeManager? {
        managersByRepositoryID[repositoryRootURL.standardizedFileURL.path]
    }

    func reorderRepository(_ repositoryID: Repository.ID) {
        guard let manager = manager(for: repositoryID),
              let worktrees = worktreesByRepository[repositoryID] else {
            return
        }
        worktreesByRepository[repositoryID] = orderedWorktrees(for: manager, worktrees: worktrees)
    }

    func orderedWorktrees(
        for manager: WorktreeManager,
        worktrees: [Worktree]
    ) -> [Worktree] {
        manager.visibleWorktrees(from: worktrees) + manager.archivedWorktrees(from: worktrees)
    }

    func normalizeSelection() {
        repositories = repositories.uniqued(by: \.id)

        for repositoryID in Set(worktreesByRepository.keys).subtracting(repositories.map(\.id)) {
            worktreesByRepository.removeValue(forKey: repositoryID)
            managersByRepositoryID.removeValue(forKey: repositoryID)
        }

        guard !repositories.isEmpty else {
            selectedRepositoryID = nil
            selectedWorkspaceID = nil
            return
        }

        if let selectedRepositoryID,
           repositories.contains(where: { $0.id == selectedRepositoryID }) {
            if let worktrees = worktreesByRepository[selectedRepositoryID],
               let selectedWorkspaceID,
               worktrees.contains(where: { $0.id == selectedWorkspaceID }) {
                return
            }
            selectedWorkspaceID = manager(for: selectedRepositoryID)?.selection.selectedWorktreeId
            return
        }

        selectedRepositoryID = repositories.last?.id
        selectedWorkspaceID = selectedRepositoryID.flatMap { manager(for: $0)?.selection.selectedWorktreeId }
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen: Set<Key> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
