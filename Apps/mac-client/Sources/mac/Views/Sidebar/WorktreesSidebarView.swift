// WorktreesSidebarView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import SwiftUI
import AppKit
import Workspace
import Git
import GhosttyTerminal
import UI

struct WorktreesSidebarView: View {
    @Environment(\.devysTheme) private var theme

    @Bindable var manager: WorktreeManager
    @Bindable var infoStore: WorktreeInfoStore
    @Bindable var runCommandStore: RunCommandStore
    let notificationStore: TerminalNotificationStore?
    let terminalSessions: [UUID: GhosttyTerminalSession]
    let onSelectTerminal: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Rectangle()
                .fill(theme.borderSubtle)
                .frame(width: 1)
        }
        .background(theme.surface)
    }

    private var header: some View {
        HStack {
            Text("WORKTREES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Spacer()

            Button {
                Task {
                    await manager.refresh(for: manager.repositoryRoot)
                    infoStore.refreshAll()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Refresh Worktrees")
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.vertical, DevysSpacing.space2)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DevysSpacing.space1) {
                if manager.orderedWorktrees.isEmpty {
                    Text("No worktrees found")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, DevysSpacing.space3)
                        .padding(.vertical, DevysSpacing.space2)
                } else {
                    ForEach(manager.orderedWorktrees) { worktree in
                        worktreeSection(for: worktree)
                    }
                }
            }
            .padding(.top, DevysSpacing.space1)
        }
    }

    @ViewBuilder
    private func worktreeSection(for worktree: Worktree) -> some View {
        let state = worktreeSectionState(for: worktree)
        VStack(alignment: .leading, spacing: 2) {
            worktreeHeaderButton(worktree: worktree, state: state)
            worktreeTerminalList(terminalIds: state.terminalIds)
        }
        .padding(.horizontal, 6)
    }

    // MARK: - Section State

    private struct WorktreeSectionState {
        let branchName: String
        let lineChanges: WorktreeLineChanges?
        let statusSummary: WorktreeStatusSummary?
        let pullRequest: PullRequest?
        let hasUnread: Bool
        let isRunningTask: Bool
        let isSelected: Bool
        let lastFocused: Date?
        let assignedAgent: String?
        let terminalIds: [UUID]
    }

    private func worktreeSectionState(for worktree: Worktree) -> WorktreeSectionState {
        let terminalIds = terminalIdsByWorktree[worktree.id] ?? []
        let info = infoStore.entriesById[worktree.id]
        let hasUnread = terminalIds.contains { notificationStore?.isUnread($0) == true }
        let worktreeState = manager.statesById[worktree.id]
        return WorktreeSectionState(
            branchName: info?.branchName ?? worktree.name,
            lineChanges: info?.lineChanges,
            statusSummary: info?.statusSummary,
            pullRequest: info?.pullRequest,
            hasUnread: hasUnread,
            isRunningTask: runCommandStore.state(for: worktree.id)?.isRunning == true,
            isSelected: manager.selection.selectedWorktreeId == worktree.id,
            lastFocused: worktreeState?.lastFocused,
            assignedAgent: worktreeState?.assignedAgentName,
            terminalIds: terminalIds
        )
    }

    // MARK: - Worktree Header

    private func worktreeHeaderButton(worktree: Worktree, state: WorktreeSectionState) -> some View {
        Button {
            manager.selectWorktree(worktree.id)
        } label: {
            worktreeHeaderContent(worktree: worktree, state: state)
        }
        .buttonStyle(.plain)
        .contextMenu {
            worktreeContextMenu(for: worktree)
        }
    }

    private func worktreeHeaderContent(worktree: Worktree, state: WorktreeSectionState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top line: branch icon, name, line changes, PR badge
            HStack(spacing: DevysSpacing.space2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)

                Text(state.branchName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(state.isSelected ? theme.text : theme.textSecondary)

                Spacer(minLength: 0)

                if let lineChanges = state.lineChanges, !lineChanges.isEmpty {
                    lineChangesView(lineChanges)
                }

                if let pullRequest = state.pullRequest {
                    prBadge(pullRequest)
                }

                if state.isRunningTask {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DevysColors.success)
                        .padding(4)
                        .background(DevysColors.success.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if state.hasUnread {
                    Circle()
                        .fill(DevysColors.warning)
                        .frame(width: 6, height: 6)
                }
            }

            // Bottom line: detail path, last focused, assigned agent, status summary
            worktreeDetailRow(worktree: worktree, state: state)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DevysSpacing.space3)
        .background(
            RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                .fill(state.isSelected ? theme.active : Color.clear)
        )
    }

}

// MARK: - Components

extension WorktreesSidebarView {
    private func worktreeDetailRow(worktree: Worktree, state: WorktreeSectionState) -> some View {
        HStack(spacing: DevysSpacing.space2) {
            Text(worktree.detail)
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let lastFocused = state.lastFocused {
                Text(relativeTime(from: lastFocused))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }

            if let assignedAgent = state.assignedAgent, !assignedAgent.isEmpty {
                agentChip(assignedAgent)
            }

            if let statusSummary = state.statusSummary {
                statusSummaryView(statusSummary)
            }
        }
    }

    @ViewBuilder
    func worktreeTerminalList(terminalIds: [UUID]) -> some View {
        if !terminalIds.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(terminalIds, id: \.self) { terminalId in
                    if let session = terminalSessions[terminalId] {
                        terminalRow(session: session, terminalId: terminalId)
                    }
                }
            }
            .padding(.leading, DevysSpacing.space4)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    func worktreeContextMenu(for worktree: Worktree) -> some View {
        let isPinned = manager.statesById[worktree.id]?.isPinned == true
        let isArchived = manager.statesById[worktree.id]?.isArchived == true
        let assignedAgent = manager.statesById[worktree.id]?.assignedAgentName

        Button(isPinned ? "Unpin Worktree" : "Pin Worktree") {
            manager.setPinned(worktree.id, isPinned: !isPinned)
        }

        Button(isArchived ? "Unarchive Worktree" : "Archive Worktree") {
            manager.setArchived(worktree.id, isArchived: !isArchived)
        }

        Divider()

        Button("Open in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([worktree.workingDirectory])
        }

        Button("Open in Xcode") {
            openInXcode(worktree)
        }

        Divider()

        Button("Assign Agent") {
            assignAgent(worktree)
        }

        if assignedAgent != nil {
            Button("Clear Agent") {
                manager.setAssignedAgent(worktree.id, name: nil)
            }
        }

        Divider()

        Button("Remove Worktree") {
            confirmRemoveWorktree(worktree)
        }
    }

    private func terminalRow(session: GhosttyTerminalSession, terminalId: UUID) -> some View {
        Button {
            onSelectTerminal(terminalId)
        } label: {
            HStack(spacing: DevysSpacing.space2) {
                Circle()
                    .fill(session.isRunning ? DevysColors.success : theme.textTertiary)
                    .frame(width: 6, height: 6)

                Text(session.tabTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if notificationStore?.isUnread(terminalId) == true {
                    Circle()
                        .fill(DevysColors.warning)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badges & Chips

extension WorktreesSidebarView {
    func lineChangesView(_ changes: WorktreeLineChanges) -> some View {
        HStack(spacing: 4) {
            Text("+\(changes.added)")
                .foregroundStyle(DevysColors.success)
            Text("-\(changes.removed)")
                .foregroundStyle(DevysColors.error)
        }
        .font(.system(size: 10, weight: .semibold))
    }

    func prBadge(_ pr: PullRequest) -> some View {
        HStack(spacing: 4) {
            if let status = pr.checksStatus {
                Circle()
                    .fill(checksColor(status))
                    .frame(width: 6, height: 6)
            }
            Text("#\(pr.number)")
                .foregroundStyle(theme.textSecondary)
        }
        .font(.system(size: 9, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func checksColor(_ status: ChecksStatus) -> Color {
        switch status {
        case .passing: return DevysColors.success
        case .pending: return DevysColors.warning
        case .failing: return DevysColors.error
        }
    }

    @ViewBuilder
    func statusSummaryView(_ summary: WorktreeStatusSummary) -> some View {
        if summary.isClean {
            Text("Clean")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
        } else {
            HStack(spacing: 4) {
                if summary.staged > 0 {
                    statusChip(label: "S\(summary.staged)", color: DevysColors.success)
                }
                if summary.unstaged > 0 {
                    statusChip(label: "U\(summary.unstaged)", color: DevysColors.warning)
                }
                if summary.untracked > 0 {
                    statusChip(label: "?\(summary.untracked)", color: DevysColors.warning)
                }
                if summary.conflicts > 0 {
                    statusChip(label: "!\(summary.conflicts)", color: DevysColors.error)
                }
            }
        }
    }

    private func statusChip(label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    func agentChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86_400))d"
    }
}

// MARK: - Actions

extension WorktreesSidebarView {
    private func openInXcode(_ worktree: Worktree) {
        Task {
            guard let xcodeURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.dt.Xcode"
            ) else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try? await NSWorkspace.shared.open(
                [worktree.workingDirectory],
                withApplicationAt: xcodeURL,
                configuration: configuration
            )
        }
    }

    @MainActor
    func confirmRemoveWorktree(_ worktree: Worktree) {
        if worktree.workingDirectory.standardizedFileURL == worktree.repositoryRootURL.standardizedFileURL {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cannot remove main worktree"
            alert.informativeText = "The main repository worktree cannot be removed."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove worktree?"
        alert.informativeText = "This will remove the worktree at \(worktree.workingDirectory.path)."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { @MainActor in
            await removeWorktree(worktree)
        }
    }

    @MainActor
    func assignAgent(_ worktree: Worktree) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Assign Agent"
        alert.informativeText = "Enter an agent name for \(worktree.name)."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = manager.statesById[worktree.id]?.assignedAgentName ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "Assign")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        manager.setAssignedAgent(worktree.id, name: name.isEmpty ? nil : name)
    }

    @MainActor
    private func removeWorktree(_ worktree: Worktree) async {
        let service = DefaultGitWorktreeService()
        do {
            try await service.removeWorktree(worktree, force: false)
            await manager.refresh(for: manager.repositoryRoot)
            infoStore.refreshAll()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Remove worktree failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

// MARK: - Terminal Matching

extension WorktreesSidebarView {
    var terminalIdsByWorktree: [Worktree.ID: [UUID]] {
        var result: [Worktree.ID: [UUID]] = [:]
        for (id, session) in terminalSessions {
            guard let worktreeId = worktreeId(for: session) else {
                continue
            }
            result[worktreeId, default: []].append(id)
        }
        return result
    }

    private func worktreeId(for session: GhosttyTerminalSession) -> Worktree.ID? {
        guard let directory = session.workingDirectory?.standardizedFileURL else { return nil }
        return manager.worktrees.first { $0.workingDirectory.standardizedFileURL == directory }?.id
    }
}

// MARK: - Preview

#Preview("Worktrees Sidebar") {
    struct PreviewListingService: WorktreeListingService {
        let worktrees: [Worktree]
        func listWorktrees(for repositoryRoot: URL) async throws -> [Worktree] {
            _ = repositoryRoot
            return worktrees
        }
    }

    let repoURL = URL(fileURLWithPath: "/tmp/repo")
    let previewDefaults = UserDefaults(suiteName: "com.devys.preview.worktrees") ?? .standard
    let manager = WorktreeManager(
        persistenceService: UserDefaultsWorktreePersistenceService(userDefaults: previewDefaults),
        listingService: PreviewListingService(
            worktrees: [
                Worktree(
                    name: "main",
                    detail: ".",
                    workingDirectory: repoURL,
                    repositoryRootURL: repoURL
                )
            ]
        )
    )
    let infoStore = WorktreeInfoStore(infoWatcher: NoopWorktreeInfoWatcher())
    infoStore.entriesById = [
        repoURL.path: WorktreeInfoEntry(
            branchName: "main",
            lineChanges: WorktreeLineChanges(added: 12, removed: 3),
            statusSummary: WorktreeStatusSummary(staged: 1, unstaged: 2, untracked: 1, conflicts: 0)
        )
    ]

    return WorktreesSidebarView(
        manager: manager,
        infoStore: infoStore,
        runCommandStore: RunCommandStore(),
        notificationStore: TerminalNotificationStore(),
        terminalSessions: [:]
    ) { _ in }
    .task { await manager.refresh(for: repoURL) }
    .frame(width: 280, height: 420)
    .environment(\.devysTheme, DevysTheme(isDark: false))
}
