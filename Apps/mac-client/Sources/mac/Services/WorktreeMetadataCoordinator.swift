// WorktreeMetadataCoordinator.swift
// Devys - Repository-scoped worktree metadata ownership.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import Observation
import Workspace

@MainActor
@Observable
final class WorktreeMetadataCoordinator {
    typealias StoreFactory = @MainActor () -> WorktreeInfoStore

    private let storeFactory: StoreFactory
    private(set) var activeRepositoryID: Repository.ID?
    private var storesByRepositoryID: [Repository.ID: WorktreeInfoStore] = [:]
    private var syncDebounceTask: Task<Void, Never>?

    init(storeFactory: @escaping StoreFactory = { WorktreeInfoStore() }) {
        self.storeFactory = storeFactory
    }
}

@MainActor
extension WorktreeMetadataCoordinator {
    var activeStore: WorktreeInfoStore? {
        guard let activeRepositoryID else { return nil }
        return storesByRepositoryID[activeRepositoryID]
    }

    var entriesByWorkspaceID: [Workspace.ID: WorktreeInfoEntry] {
        storesByRepositoryID.values.reduce(into: [:]) { partialResult, store in
            partialResult.merge(store.entriesById) { _, new in
                new
            }
        }
    }

    /// Cheap structural sync: prunes removed repos, ensures stores exist,
    /// updates activeRepositoryID. Does NOT call store.update() so no
    /// git operations are triggered.
    func syncCatalogStructure(_ snapshot: WindowCatalogRuntimeSnapshot) {
        let repositoryIDs = Set(snapshot.repositories.map(\.id))

        for repositoryID in Set(storesByRepositoryID.keys).subtracting(repositoryIDs) {
            storesByRepositoryID.removeValue(forKey: repositoryID)
        }

        activeRepositoryID = snapshot.selectedRepositoryID

        for repository in snapshot.repositories {
            _ = ensureStore(for: repository.id)
        }
    }

    /// Full sync: prunes repos, ensures stores, and calls store.update()
    /// which triggers git operations (branch, log, diff, status).
    /// Debounced at 200ms to coalesce rapid-fire calls during workspace
    /// switch/restore sequences.
    func syncCatalog(_ snapshot: WindowCatalogRuntimeSnapshot) {
        // Always apply structural changes immediately (cheap)
        syncCatalogStructure(snapshot)

        // Debounce the expensive store.update() calls
        syncDebounceTask?.cancel()
        syncDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.executeSyncCatalog(snapshot)
        }
    }

    private func executeSyncCatalog(_ snapshot: WindowCatalogRuntimeSnapshot) {
        for repository in snapshot.repositories {
            let store = ensureStore(for: repository.id)
            let isActiveRepository = repository.id == snapshot.selectedRepositoryID
            let worktrees = snapshot.worktreesByRepository[repository.id] ?? []
            let selectedWorktreeID = isActiveRepository ? snapshot.selectedWorkspaceID : nil
            let updateResult = store.update(
                worktrees: worktrees,
                repositoryRootURL: repository.rootURL,
                isActiveRepository: isActiveRepository
            )
            store.setSelectedWorktreeId(selectedWorktreeID)
            if isActiveRepository {
                let immediateRefreshWorktreeIds = updateResult.immediateRefreshWorktreeIds
                if !immediateRefreshWorktreeIds.isEmpty {
                    store.refresh(worktreeIds: immediateRefreshWorktreeIds)
                }
            }
        }
    }

    func refresh(
        worktreeIds: [Worktree.ID],
        in repositoryID: Repository.ID? = nil,
        reason: WorktreeInfoStore.RefreshReason = .manual
    ) {
        let targetRepositoryID = repositoryID ?? activeRepositoryID
        guard let targetRepositoryID,
              let store = storesByRepositoryID[targetRepositoryID] else {
            return
        }
        store.refresh(worktreeIds: worktreeIds, reason: reason)
    }
}

@MainActor
private extension WorktreeMetadataCoordinator {
    func ensureStore(for repositoryID: Repository.ID) -> WorktreeInfoStore {
        if let existing = storesByRepositoryID[repositoryID] {
            return existing
        }

        let store = storeFactory()
        storesByRepositoryID[repositoryID] = store
        return store
    }
}
