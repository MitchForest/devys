// WorkspacePortOwnershipCoordinator.swift
// Devys - Repository-scoped workspace port ownership orchestration.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import Foundation
import Observation
import Workspace

@MainActor
@Observable
final class WorkspacePortOwnershipCoordinator {
    typealias StoreFactory = @MainActor () -> WorkspacePortStore

    private let storeFactory: StoreFactory
    private(set) var activeRepositoryID: Repository.ID?
    private var storesByRepositoryID: [Repository.ID: WorkspacePortStore] = [:]

    init(storeFactory: @escaping StoreFactory = { WorkspacePortStore() }) {
        self.storeFactory = storeFactory
    }
}

@MainActor
extension WorkspacePortOwnershipCoordinator {
    var activeStore: WorkspacePortStore? {
        guard let activeRepositoryID else { return nil }
        return storesByRepositoryID[activeRepositoryID]
    }

    var portsByWorkspaceID: [Workspace.ID: [WorkspacePort]] {
        storesByRepositoryID.values.reduce(into: [:]) { partialResult, store in
            partialResult.merge(store.portsByWorkspace) { _, new in
                new
            }
        }
    }

    var summariesByWorkspaceID: [Workspace.ID: WorkspacePortSummary] {
        storesByRepositoryID.values.reduce(into: [:]) { partialResult, store in
            partialResult.merge(store.summariesByWorkspace) { _, new in
                new
            }
        }
    }

    /// Cheap structural sync: prunes removed repos, ensures stores exist,
    /// updates activeRepositoryID. Does NOT call store.update() so no
    /// lsof/ps commands are triggered.
    func syncCatalogStructure(
        _ snapshot: WindowCatalogRuntimeSnapshot,
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]]
    ) {
        synchronizeStores(
            snapshot,
            managedProcessesByWorkspace: managedProcessesByWorkspace,
            activeMode: .structureOnly
        )
    }

    /// Full sync: updates store context for every repository and lets the
    /// active repository decide whether it needs an immediate ownership scan.
    func syncCatalog(
        _ snapshot: WindowCatalogRuntimeSnapshot,
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]]
    ) {
        synchronizeStores(
            snapshot,
            managedProcessesByWorkspace: managedProcessesByWorkspace,
            activeMode: .refreshIfNeeded
        )
    }

    func summary(for workspaceID: Workspace.ID?) -> WorkspacePortSummary? {
        guard let workspaceID else { return nil }
        for store in storesByRepositoryID.values {
            if let summary = store.summary(for: workspaceID) {
                return summary
            }
        }
        return nil
    }

    var activeSummariesByWorkspace: [Workspace.ID: WorkspacePortSummary] {
        activeStore?.summariesByWorkspace ?? [:]
    }

    func clearWorkspace(_ workspaceID: Workspace.ID) {
        for store in storesByRepositoryID.values {
            store.clearWorkspace(workspaceID)
        }
    }

}

@MainActor
private extension WorkspacePortOwnershipCoordinator {
    func synchronizeStores(
        _ snapshot: WindowCatalogRuntimeSnapshot,
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]],
        activeMode: WorkspacePortStore.UpdateMode
    ) {
        let repositoryIDs = Set(snapshot.repositories.map(\.id))

        for repositoryID in Set(storesByRepositoryID.keys).subtracting(repositoryIDs) {
            storesByRepositoryID.removeValue(forKey: repositoryID)
        }

        activeRepositoryID = snapshot.selectedRepositoryID

        for repository in snapshot.repositories {
            let store = ensureStore(for: repository.id)
            let worktrees = snapshot.worktreesByRepository[repository.id] ?? []
            let activeWorktreeIDs = Set(worktrees.map(\.id))
            let filteredManagedProcesses = managedProcessesByWorkspace.filter {
                activeWorktreeIDs.contains($0.key)
            }
            let isActiveRepository = repository.id == snapshot.selectedRepositoryID

            store.update(
                worktrees: worktrees,
                managedProcessesByWorkspace: filteredManagedProcesses,
                selectedWorktreeId: isActiveRepository ? snapshot.selectedWorkspaceID : nil,
                isActiveRepository: isActiveRepository,
                mode: isActiveRepository ? activeMode : .structureOnly
            )
        }
    }

    func ensureStore(for repositoryID: Repository.ID) -> WorkspacePortStore {
        if let existing = storesByRepositoryID[repositoryID] {
            return existing
        }

        let store = storeFactory()
        storesByRepositoryID[repositoryID] = store
        return store
    }
}
