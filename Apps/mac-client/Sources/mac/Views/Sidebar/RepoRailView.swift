// RepoRailView.swift
// Devys - Slim repo/worktree rail (Slack-style).
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import RemoteCore
import SwiftUI
import UI
import Workspace

// MARK: - RepoRailView

struct RepoRailView: View {
    @Environment(\.devysTheme) private var theme
    @Environment(\.densityLayout) private var layout

    let repositories: [Repository]
    let remoteRepositories: [RemoteRepositoryAuthority]
    let selectedRepositoryID: Repository.ID?
    let selectedRemoteRepositoryID: RemoteRepositoryAuthority.ID?
    let selectedWorkspaceID: Workspace.ID?
    let worktreesByRepository: [Repository.ID: [Worktree]]
    let remoteWorktreesByRepository: [RemoteRepositoryAuthority.ID: [RemoteWorktree]]
    let workspaceStatesByID: [Worktree.ID: WorktreeState]
    let worktreeStatusHints: [Worktree.ID: StatusHint]
    let remoteWorktreeStatusHints: [RemoteWorktree.ID: StatusHint]

    let onAddRepository: () -> Void
    let onRemoveRepository: (Repository.ID) -> Void
    let onRemoveRemoteRepository: (RemoteRepositoryAuthority.ID) -> Void
    let onInitializeRepository: (Repository.ID) -> Void
    let onCreateWorkspace: (Repository.ID) -> Void
    let onCreateRemoteWorktree: (RemoteRepositoryAuthority.ID) -> Void
    let onSelectWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onSelectRemoteWorktree: (RemoteRepositoryAuthority.ID, RemoteWorktree.ID) -> Void
    let onReorderRepository: (Repository.ID, Int) -> Void
    let onSetWorkspacePinned: (Repository.ID, Worktree.ID, Bool) -> Void
    let onSetWorkspaceArchived: (Repository.ID, Worktree.ID, Bool) -> Void
    let onRenameWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onDeleteWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onRevealWorkspaceInFinder: (Repository.ID, Worktree.ID) -> Void
    let onOpenWorkspaceInExternalEditor: (Repository.ID, Worktree.ID) -> Void
    let onRevealRepositoryInFinder: (Repository.ID) -> Void
    let onRefreshRemoteRepository: (RemoteRepositoryAuthority.ID) -> Void
    let onFetchRemoteRepository: (RemoteRepositoryAuthority.ID) -> Void
    let onPullRemoteWorktree: (RemoteRepositoryAuthority.ID, RemoteWorktree.ID) -> Void
    let onPushRemoteWorktree: (RemoteRepositoryAuthority.ID, RemoteWorktree.ID) -> Void

    @State private var expandedRepos: Set<String> = []
    @State private var draggedRepositoryID: Repository.ID?
    @State private var dropTargetIndex: Int?

    var body: some View {
        VStack(spacing: 0) {
            scrollableRail

            Spacer(minLength: 0)

            RailAddButton(action: onAddRepository)
                .help("Add Repository")
            .padding(.vertical, Spacing.space2)
        }
        .frame(width: layout.repoRailWidth)
        .frame(maxHeight: .infinity)
        .background(theme.base)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.border)
                .frame(width: 1)
        }
        .onAppear {
            autoExpandSelectedRepo()
        }
        .onChange(of: selectedRepositoryID) { _, _ in
            autoExpandSelectedRepo()
        }
        .onChange(of: selectedRemoteRepositoryID) { _, _ in
            autoExpandSelectedRepo()
        }
    }

    // MARK: - Scrollable Content

    private var scrollableRail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.space1) {
                    ForEach(Array(repositories.enumerated()), id: \.element.id) { index, repo in
                        repoGroup(repo, at: index)
                    }

                    ForEach(remoteRepositories) { repository in
                        remoteRepoGroup(repository)
                    }
                }
                .padding(.vertical, Spacing.space2)
                .padding(.horizontal, railHorizontalPadding)
            }
            .onChange(of: selectedWorkspaceID) { _, newValue in
                guard let newValue else { return }
                withAnimation(Animations.spring) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private var railHorizontalPadding: CGFloat {
        (layout.repoRailWidth - layout.repoItemSize) / 2
    }

    // MARK: - Repo Group

    @ViewBuilder
    private func repoGroup(_ repo: Repository, at index: Int) -> some View {
        let isExpanded = expandedRepos.contains(repo.id)
        let isActive = selectedRepositoryID == repo.id

        VStack(spacing: 2) {
            // Repo tile (circle)
            RepoItem(
                abbreviation: repo.displayInitials ?? String(repo.displayName.prefix(2)),
                customSymbol: repo.displaySymbol,
                repoName: repo.displayName,
                isActive: isActive
            ) {
                toggleRepo(repo)
            }
            .id("repo-\(repo.id)")
            .contextMenu { repoContextMenu(repo) }
            .draggable(RepoRailTransfer(repositoryID: repo.id)) {
                RepoItem(
                    abbreviation: repo.displayInitials ?? String(repo.displayName.prefix(2)),
                    customSymbol: repo.displaySymbol,
                    repoName: repo.displayName,
                    isActive: true
                ) {}
                .opacity(0.85)
            }
            .opacity(draggedRepositoryID == repo.id ? 0.4 : 1)

            // Expanded worktree list
            if isExpanded {
                worktreeList(for: repo)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .dropDestination(for: RepoRailTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            onReorderRepository(transfer.repositoryID, index)
            return true
        } isTargeted: { isTargeted in
            withAnimation(Animations.micro) {
                dropTargetIndex = isTargeted ? index : nil
            }
        }
        .overlay(alignment: .top) {
            if dropTargetIndex == index && draggedRepositoryID != repo.id {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(theme.accent)
                    .frame(width: layout.repoItemSize, height: 2)
                    .offset(y: -3)
            }
        }
        .animation(Animations.spring, value: isExpanded)
    }

    @ViewBuilder
    private func remoteRepoGroup(_ repository: RemoteRepositoryAuthority) -> some View {
        let isExpanded = expandedRepos.contains(repository.id)
        let isActive = selectedRemoteRepositoryID == repository.id

        VStack(spacing: 2) {
            RepoItem(
                abbreviation: String(repository.displayName.prefix(2)),
                badgeSymbol: "server.rack",
                repoName: repository.railDisplayName,
                isActive: isActive
            ) {
                toggleRemoteRepo(repository)
            }
            .id("remote-\(repository.id)")
            .contextMenu { remoteRepoContextMenu(repository) }

            if isExpanded {
                remoteWorktreeList(for: repository)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Animations.spring, value: isExpanded)
    }

    // MARK: - Worktree List

    @ViewBuilder
    private func worktreeList(for repo: Repository) -> some View {
        let worktrees = visibleWorktrees(for: repo)

        ForEach(Array(worktrees.enumerated()), id: \.element.id) { worktreeIndex, worktree in
            let state = workspaceStatesByID[worktree.id]
            let displayName = state?.displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (displayName?.isEmpty == false ? displayName : nil) ?? worktree.name

            WorktreeItem(
                index: worktreeIndex,
                branchName: name,
                isActive: selectedWorkspaceID == worktree.id,
                statusHint: worktreeStatusHints[worktree.id]
            ) {
                onSelectWorkspace(repo.id, worktree.id)
            }
            .id(worktree.id)
            .contextMenu { worktreeContextMenu(repo, worktree) }
        }
    }

    @ViewBuilder
    private func remoteWorktreeList(
        for repository: RemoteRepositoryAuthority
    ) -> some View {
        let worktrees = remoteWorktreesByRepository[repository.id] ?? []

        ForEach(Array(worktrees.enumerated()), id: \.element.id) { worktreeIndex, worktree in
            WorktreeItem(
                index: worktreeIndex,
                branchName: worktree.branchName,
                isActive: selectedWorkspaceID == worktree.id,
                statusHint: remoteWorktreeStatusHints[worktree.id]
            ) {
                onSelectRemoteWorktree(repository.id, worktree.id)
            }
            .id(worktree.id)
            .contextMenu { remoteWorktreeContextMenu(repository, worktree) }
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func repoContextMenu(_ repo: Repository) -> some View {
        if repo.isGitRepository {
            Button("New Workspace") { onCreateWorkspace(repo.id) }
        } else {
            Button("Initialize Git") { onInitializeRepository(repo.id) }
        }

        Divider()

        Button("Reveal in Finder") { onRevealRepositoryInFinder(repo.id) }

        Divider()

        Button("Remove", role: .destructive) { onRemoveRepository(repo.id) }
    }

    @ViewBuilder
    private func remoteRepoContextMenu(_ repository: RemoteRepositoryAuthority) -> some View {
        Button("New Remote Worktree") { onCreateRemoteWorktree(repository.id) }
        Button("Refresh") { onRefreshRemoteRepository(repository.id) }
        Button("Fetch") { onFetchRemoteRepository(repository.id) }

        Divider()

        Button("Remove", role: .destructive) { onRemoveRemoteRepository(repository.id) }
    }

    @ViewBuilder
    private func worktreeContextMenu(_ repo: Repository, _ worktree: Worktree) -> some View {
        let state = workspaceStatesByID[worktree.id]

        Button(state?.isPinned == true ? "Unpin" : "Pin") {
            onSetWorkspacePinned(repo.id, worktree.id, !(state?.isPinned ?? false))
        }
        Button(state?.isArchived == true ? "Unarchive" : "Archive") {
            onSetWorkspaceArchived(repo.id, worktree.id, !(state?.isArchived ?? false))
        }

        Divider()

        Button("Rename") { onRenameWorkspace(repo.id, worktree.id) }
        Button("Reveal in Finder") { onRevealWorkspaceInFinder(repo.id, worktree.id) }
        Button("Open in External Editor") { onOpenWorkspaceInExternalEditor(repo.id, worktree.id) }

        Divider()

        Button("Delete", role: .destructive) { onDeleteWorkspace(repo.id, worktree.id) }
            .disabled(worktree.isPrimary)
    }

    @ViewBuilder
    private func remoteWorktreeContextMenu(
        _ repository: RemoteRepositoryAuthority,
        _ worktree: RemoteWorktree
    ) -> some View {
        Button("Pull") { onPullRemoteWorktree(repository.id, worktree.id) }
        Button("Push") { onPushRemoteWorktree(repository.id, worktree.id) }
    }

    // MARK: - Helpers

    private func toggleRepo(_ repo: Repository) {
        withAnimation(Animations.spring) {
            if expandedRepos.contains(repo.id) {
                if selectedRepositoryID == repo.id {
                    expandedRepos.remove(repo.id)
                } else {
                    expandedRepos.insert(repo.id)
                    selectFirstWorktree(in: repo)
                }
            } else {
                expandedRepos.insert(repo.id)
                selectFirstWorktree(in: repo)
            }
        }
    }

    private func toggleRemoteRepo(_ repository: RemoteRepositoryAuthority) {
        withAnimation(Animations.spring) {
            if expandedRepos.contains(repository.id) {
                if selectedRemoteRepositoryID == repository.id {
                    expandedRepos.remove(repository.id)
                } else {
                    expandedRepos.insert(repository.id)
                    selectFirstRemoteWorktree(in: repository)
                }
            } else {
                expandedRepos.insert(repository.id)
                selectFirstRemoteWorktree(in: repository)
            }
        }
    }

    private func selectFirstWorktree(in repo: Repository) {
        let worktrees = visibleWorktrees(for: repo)
        if let first = worktrees.first {
            onSelectWorkspace(repo.id, first.id)
        }
    }

    private func selectFirstRemoteWorktree(in repository: RemoteRepositoryAuthority) {
        guard let first = (remoteWorktreesByRepository[repository.id] ?? []).first else { return }
        onSelectRemoteWorktree(repository.id, first.id)
    }

    private func autoExpandSelectedRepo() {
        if let selectedRepositoryID {
            expandedRepos.insert(selectedRepositoryID)
        }
        if let selectedRemoteRepositoryID {
            expandedRepos.insert(selectedRemoteRepositoryID)
        }
    }

    private func visibleWorktrees(for repo: Repository) -> [Worktree] {
        let worktrees = worktreesByRepository[repo.id] ?? []
        return worktrees.filter { workspaceStatesByID[$0.id]?.isArchived != true }
    }
}
