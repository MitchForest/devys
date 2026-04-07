// RepositoryNavigatorCatalogPlanner.swift
// Devys - Incremental navigator catalog update planning.

import Foundation
import Workspace

struct RepositoryNavigatorCatalogUpdatePlan: Equatable {
    let repositoryIDsToRemove: Set<Repository.ID>
    let repositoryIDsToRefresh: [Repository.ID]
}

enum RepositoryNavigatorCatalogPlanner {
    static func makePlan(
        previousRepositories: [Repository],
        currentRepositories: [Repository],
        cachedRepositoryIDs: Set<Repository.ID>
    ) -> RepositoryNavigatorCatalogUpdatePlan {
        let previousRepositoryIDs = Set(previousRepositories.map(\.id))
        let currentRepositoryIDs = Set(currentRepositories.map(\.id))
        let repositoryIDsToRemove = cachedRepositoryIDs.subtracting(currentRepositoryIDs)
        let repositoryIDsToRefresh = currentRepositories.compactMap { repository in
            if !previousRepositoryIDs.contains(repository.id) || !cachedRepositoryIDs.contains(repository.id) {
                return repository.id
            }
            return nil
        }

        return RepositoryNavigatorCatalogUpdatePlan(
            repositoryIDsToRemove: repositoryIDsToRemove,
            repositoryIDsToRefresh: repositoryIDsToRefresh
        )
    }
}
