// ContentView+GitActions.swift
// Devys - Active workspace Git actions.

import AppFeatures
import AppKit
import Git
import Workspace

@MainActor
extension ContentView {
    var activeWorktreeInfo: WorktreeInfoEntry? {
        guard let activeWorktree else { return nil }
        return workspaceOperationalState.metadataEntriesByWorkspaceID[activeWorktree.id]
    }

    func fetchSelectedWorkspaceRemote() {
        guard let gitStore, gitStore.isRepositoryAvailable else { return }
        Task { @MainActor in
            await gitStore.fetch()
            presentGitActionErrorIfNeeded(title: "Fetch Failed")
        }
    }

    func pullSelectedWorkspaceRemote() {
        guard let gitStore, gitStore.isRepositoryAvailable else { return }
        Task { @MainActor in
            await gitStore.pull()
            presentGitActionErrorIfNeeded(title: "Pull Failed")
        }
    }

    func pushSelectedWorkspaceRemote() {
        guard let gitStore, gitStore.isRepositoryAvailable else { return }
        Task { @MainActor in
            await gitStore.push()
            presentGitActionErrorIfNeeded(title: "Push Failed")
        }
    }

    func commitSelectedWorkspaceChanges() {
        guard (activeWorktreeInfo?.statusSummary?.staged ?? 0) > 0 else { return }
        store.send(.setGitCommitSheetPresented(true))
    }

    func createPullRequestForSelectedWorkspace() {
        guard gitStore?.isRepositoryAvailable == true else { return }
        store.send(.setCreatePullRequestSheetPresented(true))
    }

    func openSelectedWorkspacePullRequest() {
        guard let gitStore,
              let pullRequest = activeWorktreeInfo?.pullRequest else {
            showLauncherUnavailableAlert(
                title: "No Pull Request",
                message: "This workspace does not have an open pull request."
            )
            return
        }

        Task { @MainActor in
            guard let url = await gitStore.prURL(pullRequest) else {
                showLauncherUnavailableAlert(
                    title: "Open Pull Request Failed",
                    message: "Devys could not resolve the pull request URL for this workspace."
                )
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    func handleCreatedPullRequest() async {
        await gitStore?.refresh()
        if let activeWorktreeID = activeWorktree?.id {
            store.send(
                .requestWorkspaceOperationalMetadataRefresh(
                    worktreeIDs: [activeWorktreeID],
                    repositoryID: selectedRepositoryID
                )
            )
        }
    }

    private func presentGitActionErrorIfNeeded(title: String) {
        guard let message = gitStore?.errorMessage,
              !message.isEmpty else { return }
        showLauncherUnavailableAlert(title: title, message: message)
    }

    func initializeRepository(_ repositoryID: Repository.ID) async {
        guard let repository = store.repositories.first(where: { $0.id == repositoryID }) else { return }

        let store: GitStore
        if selectedRepositoryID == repositoryID,
           let activeStore = gitStore {
            store = activeStore
        } else {
            store = GitStore(projectFolder: repository.rootURL)
        }

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
