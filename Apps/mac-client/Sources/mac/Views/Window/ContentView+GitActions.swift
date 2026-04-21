// ContentView+GitActions.swift
// Devys - Active workspace Git actions.

import AppFeatures
import AppKit
import Git
import Workspace

@MainActor
extension ContentView {
    func handleCreatedPullRequest() async {
        if let activeWorktreeID = activeWorktree?.id {
            store.send(
                .requestWorkspaceOperationalMetadataRefresh(
                    worktreeIDs: [activeWorktreeID],
                    repositoryID: selectedRepositoryID
                )
            )
        }
    }

    func initializeRepository(_ repositoryID: Repository.ID) async {
        guard let repository = store.repositories.first(where: { $0.id == repositoryID }) else { return }

        let store = GitStore(projectFolder: repository.rootURL)

        await store.initializeRepository()

        if let message = store.errorMessage, !message.isEmpty {
            showLauncherUnavailableAlert(title: "Initialize Git Failed", message: message)
            return
        }

        await self.store.send(.setRepositorySourceControl(.git, for: repositoryID)).finish()
        await refreshRepositoryCatalog(repositoryID: repositoryID)

        if selectedRepositoryID == repositoryID,
           let selectedWorktree = selectedCatalogWorktree,
           visibleWorkspaceID == selectedWorktree.id {
            self.store.send(
                .requestWorkspaceOperationalMetadataRefresh(
                    worktreeIDs: [selectedWorktree.id],
                    repositoryID: repositoryID
                )
            )
        }
    }
}
