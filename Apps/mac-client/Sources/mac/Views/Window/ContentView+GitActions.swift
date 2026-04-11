// ContentView+GitActions.swift
// Devys - Active workspace Git actions.

import AppKit
import Git
import Workspace

@MainActor
extension ContentView {
    var activeWorktreeInfo: WorktreeInfoEntry? {
        guard let activeWorktree else { return nil }
        return activeMetadataStore?.entriesById[activeWorktree.id]
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
        isGitCommitSheetPresented = true
    }

    func createPullRequestForSelectedWorkspace() {
        guard activeMetadataStore?.isPRAvailable == true else {
            showLauncherUnavailableAlert(
                title: "Pull Request Unavailable",
                message: "GitHub CLI integration is not available for this repository."
            )
            return
        }
        guard gitStore?.isRepositoryAvailable == true else { return }
        isCreatePullRequestSheetPresented = true
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
            runtimeRegistry.metadataCoordinator.refresh(worktreeIds: [activeWorktreeID])
        }
    }

    private func presentGitActionErrorIfNeeded(title: String) {
        guard let message = gitStore?.errorMessage,
              !message.isEmpty else { return }
        showLauncherUnavailableAlert(title: title, message: message)
    }

    func initializeRepository(_ repositoryID: Repository.ID) async {
        guard let repository = workspaceCatalog.repository(for: repositoryID) else { return }

        let store: GitStore
        if workspaceCatalog.selectedRepositoryID == repositoryID,
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

        workspaceCatalog.setRepositorySourceControl(.git, for: repositoryID)
        await refreshRepositoryCatalog(repositoryID: repositoryID)

        if workspaceCatalog.selectedRepositoryID == repositoryID,
           let selectedWorktree = selectedCatalogWorktree,
           visibleWorkspaceID == selectedWorktree.id {
            runtimeRegistry.metadataCoordinator.refresh(
                worktreeIds: [selectedWorktree.id],
                in: repositoryID
            )
        }
    }
}
