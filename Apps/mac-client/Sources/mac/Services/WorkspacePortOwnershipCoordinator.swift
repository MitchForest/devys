// WorkspacePortOwnershipCoordinator.swift
// Devys - Repository-scoped workspace port ownership orchestration.
//
// Copyright © 2026 Devys. All rights reserved.

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

    /// Cheap structural sync: prunes removed repos, ensures stores exist,
    /// updates activeRepositoryID. Does NOT call store.update() so no
    /// lsof/ps commands are triggered.
    func syncCatalogStructure(
        _ catalog: WindowWorkspaceCatalogStore,
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]]
    ) {
        synchronizeStores(
            catalog,
            managedProcessesByWorkspace: managedProcessesByWorkspace,
            activeMode: .structureOnly
        )
    }

    /// Full sync: updates store context for every repository and lets the
    /// active repository decide whether it needs an immediate ownership scan.
    func syncCatalog(
        _ catalog: WindowWorkspaceCatalogStore,
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]]
    ) {
        synchronizeStores(
            catalog,
            managedProcessesByWorkspace: managedProcessesByWorkspace,
            activeMode: .refreshIfNeeded
        )
    }

    func ports(for workspaceID: Workspace.ID?) -> [WorkspacePort] {
        guard let workspaceID else { return [] }
        for store in storesByRepositoryID.values {
            let ports = store.ports(for: workspaceID)
            if !ports.isEmpty {
                return ports
            }
        }
        return []
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

    func refresh(
        workspaceIDs: [Workspace.ID],
        in repositoryID: Repository.ID? = nil
    ) {
        let targetRepositoryID = repositoryID ?? activeRepositoryID
        guard let targetRepositoryID,
              let store = storesByRepositoryID[targetRepositoryID] else {
            return
        }
        store.refresh(workspaceIDs: workspaceIDs)
    }

    func clearWorkspace(_ workspaceID: Workspace.ID) {
        for store in storesByRepositoryID.values {
            store.clearWorkspace(workspaceID)
        }
    }

    func clearRepository(_ repositoryID: Repository.ID) {
        storesByRepositoryID.removeValue(forKey: repositoryID)
        if activeRepositoryID == repositoryID {
            activeRepositoryID = nil
        }
    }
}

@MainActor
private extension WorkspacePortOwnershipCoordinator {
    func synchronizeStores(
        _ catalog: WindowWorkspaceCatalogStore,
        managedProcessesByWorkspace: [Workspace.ID: [ManagedWorkspaceProcess]],
        activeMode: WorkspacePortStore.UpdateMode
    ) {
        let repositoryIDs = Set(catalog.repositories.map(\.id))

        for repositoryID in Set(storesByRepositoryID.keys).subtracting(repositoryIDs) {
            storesByRepositoryID.removeValue(forKey: repositoryID)
        }

        activeRepositoryID = catalog.selectedRepositoryID

        for repository in catalog.repositories {
            let store = ensureStore(for: repository.id)
            let worktrees = catalog.worktreesByRepository[repository.id] ?? []
            let activeWorktreeIDs = Set(worktrees.map(\.id))
            let filteredManagedProcesses = managedProcessesByWorkspace.filter {
                activeWorktreeIDs.contains($0.key)
            }
            let isActiveRepository = repository.id == catalog.selectedRepositoryID

            store.update(
                worktrees: worktrees,
                managedProcessesByWorkspace: filteredManagedProcesses,
                selectedWorktreeId: isActiveRepository ? catalog.selectedWorkspaceID : nil,
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
