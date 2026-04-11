// RepositoryNavigatorView.swift
// Devys - Repository and workspace navigator.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Git
import Workspace
import UI

struct RepositoryNavigatorView: View {
    @Environment(\.devysTheme) private var theme

    let repositories: [Repository]
    let selectedRepositoryID: Repository.ID?
    let selectedWorkspaceID: Workspace.ID?
    let worktreesByRepository: [Repository.ID: [Worktree]]
    let revealedWorkspaceRequest: NavigatorRevealRequest?
    let workspaceStatesByID: [Worktree.ID: WorktreeState]
    let infoEntriesByWorkspaceID: [Worktree.ID: WorktreeInfoEntry]
    let attentionSummariesByWorkspaceID: [Worktree.ID: WorkspaceAttentionSummary]
    let onAddRepository: () -> Void
    let onMoveRepository: (Repository.ID, Int) -> Void
    let onRemoveRepository: (Repository.ID) -> Void
    let onInitializeRepository: (Repository.ID) -> Void
    let onCreateWorkspace: (Repository.ID) -> Void
    let onSelectRepository: (Repository.ID) -> Void
    let onSelectWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onSetWorkspacePinned: (Repository.ID, Worktree.ID, Bool) -> Void
    let onSetWorkspaceArchived: (Repository.ID, Worktree.ID, Bool) -> Void
    let onRenameWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onDeleteWorkspace: (Repository.ID, Worktree.ID) -> Void
    let onRevealWorkspaceInFinder: (Repository.ID, Worktree.ID) -> Void
    let onOpenWorkspaceInExternalEditor: (Repository.ID, Worktree.ID) -> Void

    /// Width-responsive: compact when narrow.
    @State private var isCompact = false
    @State private var collapsedRepos: Set<Repository.ID> = []
    @State private var isManagingRepositories = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                content
                    .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                        isCompact = newWidth < 160
                    }
            }

            // Fixed footer with add repository button
            navigatorFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface)
        .sheet(isPresented: $isManagingRepositories) {
            RepositoryManagementSheet(
                repositories: repositories,
                selectedRepositoryID: selectedRepositoryID,
                onMoveRepository: onMoveRepository,
                onRemoveRepository: onRemoveRepository
            )
            .frame(minWidth: 520, minHeight: 320)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        if repositories.isEmpty {
            emptyState
        } else {
            repositoryList
        }
    }

    private var navigatorFooter: some View {
        HStack(spacing: DevysSpacing.space2) {
            addRepositoryButton
            Spacer(minLength: 0)
            manageRepositoriesButton
        }
            .padding(.horizontal, DevysSpacing.space3)
            .padding(.vertical, DevysSpacing.space2)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.borderSubtle)
                    .frame(height: 1)
            }
    }

    private var addRepositoryButton: some View {
        Button(action: onAddRepository) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add repo")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .strokeBorder(theme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
        }
        .buttonStyle(.plain)
    }

    private var manageRepositoriesButton: some View {
        Button {
            isManagingRepositories = true
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 26, height: 24)
                .background(theme.elevated)
                .overlay {
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
        }
        .buttonStyle(.plain)
        .disabled(repositories.isEmpty)
        .help("Manage repositories")
    }

    private var emptyState: some View {
        VStack(spacing: DevysSpacing.space3) {
            Spacer()

            Text("No repositories")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(DevysSpacing.space3)
    }

    private var repositoryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                    ForEach(repositories) { repository in
                        repositorySection(repository)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: revealedWorkspaceRequest) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(newValue.workspaceID, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Repository Section

private extension RepositoryNavigatorView {
    func repositorySection(_ repository: Repository) -> some View {
        let worktrees = worktreesByRepository[repository.id] ?? []
        let visible = worktrees.filter { workspaceStatesByID[$0.id]?.isArchived != true }
        let archived = worktrees.filter { workspaceStatesByID[$0.id]?.isArchived == true }
        let isCollapsed = collapsedRepos.contains(repository.id)

        return VStack(alignment: .leading, spacing: 0) {
            repoHeader(repository, isCollapsed: isCollapsed)

            if !isCollapsed {
                worktreeList(visible, repositoryID: repository.id)
                addWorkspaceLink()
                archivedSection(archived, repositoryID: repository.id)
            }
        }
    }

    func worktreeList(_ worktrees: [Worktree], repositoryID: Repository.ID) -> some View {
        ForEach(worktrees) { worktree in
            workspaceRow(worktree, repositoryID: repositoryID)
        }
    }

    func workspaceRow(_ worktree: Worktree, repositoryID: Repository.ID) -> WorkspaceRow {
        WorkspaceRow(
            worktree: worktree,
            isSelected: selectedWorkspaceID == worktree.id,
            isCompact: isCompact,
            state: workspaceStatesByID[worktree.id],
            entry: infoEntriesByWorkspaceID[worktree.id],
            attentionSummary: attentionSummariesByWorkspaceID[worktree.id],
            onSelect: {
                onSelectWorkspace(repositoryID, worktree.id)
            },
            onSetPinned: {
                onSetWorkspacePinned(repositoryID, worktree.id, $0)
            },
            onSetArchived: {
                onSetWorkspaceArchived(repositoryID, worktree.id, $0)
            },
            onRename: {
                onRenameWorkspace(repositoryID, worktree.id)
            },
            onRevealInFinder: {
                onRevealWorkspaceInFinder(repositoryID, worktree.id)
            },
            onOpenInExternalEditor: {
                onOpenWorkspaceInExternalEditor(repositoryID, worktree.id)
            },
            onDelete: {
                onDeleteWorkspace(repositoryID, worktree.id)
            }
        )
    }

    @ViewBuilder
    func addWorkspaceLink() -> some View {
        EmptyView()
    }

    @ViewBuilder
    func archivedSection(
        _ worktrees: [Worktree],
        repositoryID: Repository.ID
    ) -> some View {
        if !worktrees.isEmpty {
            DisclosureGroup {
                ForEach(worktrees) { worktree in
                    workspaceRow(worktree, repositoryID: repositoryID)
                }
            } label: {
                Text("Archived (\(worktrees.count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.leading, DevysSpacing.space4)
            .padding(.trailing, DevysSpacing.space3)
            .padding(.top, 2)
        }
    }

    func repoHeader(
        _ repository: Repository,
        isCollapsed: Bool
    ) -> some View {
        HStack(spacing: DevysSpacing.space1) {
            collapseButton(for: repository, isCollapsed: isCollapsed)
            titleButton(for: repository)

            Spacer(minLength: 0)

            repositoryActionButton(for: repository)
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                .fill(selectedRepositoryID == repository.id ? theme.elevated : Color.clear)
        )
    }

    func collapseButton(
        for repository: Repository,
        isCollapsed: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isCollapsed {
                    collapsedRepos.remove(repository.id)
                } else {
                    collapsedRepos.insert(repository.id)
                }
            }
        } label: {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 12)
        }
        .buttonStyle(.plain)
    }

    func titleButton(for repository: Repository) -> some View {
        Button {
            onSelectRepository(repository.id)
        } label: {
            Text(repository.displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
    }

    func repositoryActionButton(for repository: Repository) -> some View {
        Button {
            if repository.isGitRepository {
                onCreateWorkspace(repository.id)
            } else {
                onInitializeRepository(repository.id)
            }
        } label: {
            Image(systemName: repository.isGitRepository ? "plus" : "arrow.triangle.branch")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textTertiary)
        }
        .buttonStyle(.plain)
        .help(repository.isGitRepository ? "Add workspace" : "Initialize Git")
    }
}

// MARK: - Workspace Row

private struct WorkspaceRow: View {
    @Environment(\.devysTheme) private var theme

    let worktree: Worktree
    let isSelected: Bool
    let isCompact: Bool
    let state: WorktreeState?
    let entry: WorktreeInfoEntry?
    let attentionSummary: WorkspaceAttentionSummary?
    let onSelect: () -> Void
    let onSetPinned: (Bool) -> Void
    let onSetArchived: (Bool) -> Void
    let onRename: () -> Void
    let onRevealInFinder: () -> Void
    let onOpenInExternalEditor: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DevysSpacing.space2) {
                statusDot

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? theme.text : theme.textSecondary)
                        .lineLimit(1)

                    if !isCompact {
                        badgeRow
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, DevysSpacing.space5)
            .padding(.trailing, DevysSpacing.space3)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .fill(isSelected ? theme.active : (isHovered ? theme.hover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .opacity(state?.isArchived == true ? 0.7 : 1)
        .id(worktree.id)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(state?.isPinned == true ? "Unpin" : "Pin") {
                onSetPinned(!(state?.isPinned ?? false))
            }
            Button(state?.isArchived == true ? "Unarchive" : "Archive") {
                onSetArchived(!(state?.isArchived ?? false))
            }
            Divider()
            Button("Rename", action: onRename)
            Button("Reveal in Finder", action: onRevealInFinder)
            Button("Open in External Editor", action: onOpenInExternalEditor)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(worktree.isPrimary)
        }
    }

    private var displayTitle: String {
        let override = state?.displayNameOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return override
        }
        return worktree.name
    }

    // MARK: - Status Dot

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
    }

    private var statusColor: Color {
        if let attentionSummary, attentionSummary.hasAttention {
            if attentionSummary.waitingCount > 0 { return DevysColors.warning }
            return theme.accent
        }
        if let statusSummary = entry?.statusSummary {
            if statusSummary.conflicts > 0 { return DevysColors.error }
            if statusSummary.isClean { return DevysColors.success }
            return DevysColors.warning
        }
        return theme.textTertiary
    }

    // MARK: - Badge Row (expanded mode only)

    @ViewBuilder
    private var badgeRow: some View {
        let badges = buildBadges(isHovered: isHovered)
        if !badges.isEmpty {
            HStack(spacing: 4) {
                ForEach(badges) { badge in
                    Text(badge.text)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(badge.foreground)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(badge.background)
                        )
                }
            }
        }
    }

    private func buildBadges(isHovered: Bool) -> [WorkspaceRowBadge] {
        var badges = primaryBadges()
        if isHovered { badges += hoverBadges() }
        return Array(badges.prefix(isHovered ? 5 : 2))
    }

    private func primaryBadges() -> [WorkspaceRowBadge] {
        var badges: [WorkspaceRowBadge] = []

        if let attentionSummary, attentionSummary.hasAttention {
            badges.append(attentionBadge(attentionSummary))
        }

        if let entry {
            if let pr = entry.pullRequest {
                badges.append(WorkspaceRowBadge(
                    id: "pr",
                    text: "PR #\(pr.number)",
                    foreground: theme.accent,
                    background: theme.active
                ))
            } else if let text = dirtyBadgeText(for: entry.statusSummary) {
                badges.append(WorkspaceRowBadge(
                    id: "dirty",
                    text: text,
                    foreground: dirtyBadgeForeground(for: entry.statusSummary),
                    background: theme.elevated
                ))
            }
        }

        return badges
    }

    private func hoverBadges() -> [WorkspaceRowBadge] {
        guard let entry else { return [] }
        var badges: [WorkspaceRowBadge] = []

        if let syncText = entry.repositoryInfo?.syncCountsText,
           !syncText.isEmpty {
            badges.append(WorkspaceRowBadge(
                id: "sync",
                text: syncText,
                foreground: theme.textSecondary,
                background: theme.elevated
            ))
        }
        if let lc = entry.lineChanges, lc.added > 0 || lc.removed > 0 {
            badges.append(WorkspaceRowBadge(
                id: "lines",
                text: "+\(lc.added) -\(lc.removed)",
                foreground: theme.textSecondary,
                background: theme.elevated
            ))
        }

        return badges
    }

    private func attentionBadge(_ summary: WorkspaceAttentionSummary) -> WorkspaceRowBadge {
        if summary.waitingCount > 0 {
            let source = summary.latestWaitingSource
            let text = summary.waitingCount == 1
                ? (source.map { "\($0.displayName) waiting" } ?? "waiting")
                : "\(summary.waitingCount) waiting"
            return WorkspaceRowBadge(
                id: "attention",
                text: text,
                foreground: DevysColors.warning,
                background: theme.elevated
            )
        }
        let count = summary.unreadCount
        let text = count == 1 ? "unread" : "\(count) unread"
        return WorkspaceRowBadge(
            id: "attention",
            text: text,
            foreground: theme.accent,
            background: theme.active
        )
    }

    private func dirtyBadgeText(for summary: WorktreeStatusSummary?) -> String? {
        guard let summary else { return nil }
        if summary.isClean { return nil }
        var parts: [String] = []
        if summary.conflicts > 0 { parts.append("!\(summary.conflicts)") }
        if summary.staged > 0 { parts.append("s\(summary.staged)") }
        if summary.unstaged > 0 { parts.append("m\(summary.unstaged)") }
        if summary.untracked > 0 { parts.append("?\(summary.untracked)") }
        return parts.joined(separator: " ")
    }

    private func dirtyBadgeForeground(for summary: WorktreeStatusSummary?) -> Color {
        guard let summary else { return theme.textSecondary }
        if summary.conflicts > 0 { return DevysColors.error }
        return theme.textSecondary
    }
}

private struct WorkspaceRowBadge: Identifiable {
    let id: String
    let text: String
    let foreground: Color
    let background: Color
}
