// StatusBar.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import Git
import UI

/// Worktree-aware bottom status bar for branch and repo context.
struct StatusBar: View {
    @Environment(\.devysTheme) private var theme

    let repositoryName: String?
    let branchName: String?
    let repositoryInfo: GitRepositoryInfo?
    let worktreeDetail: String?
    let lineChanges: WorktreeLineChanges?
    let pullRequest: PullRequest?
    let prAvailability: Bool?
    let portSummary: WorkspacePortSummary?
    let hasStagedChanges: Bool
    let onFetch: (() -> Void)?
    let onPull: (() -> Void)?
    let onPush: (() -> Void)?
    let onCommit: (() -> Void)?
    let onCreatePR: (() -> Void)?
    let onOpenPR: (() -> Void)?
    let runIsActive: Bool
    let onRun: (() -> Void)?
    let onStop: (() -> Void)?
    let onOpenRunSettings: (() -> Void)?
    let onToggleNavigator: (() -> Void)?
    
    static var height: CGFloat { 24 }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(theme.surface)

            HStack(spacing: DevysSpacing.space3) {
                // Repository and branch context (clickable to toggle navigator)
                Button {
                    onToggleNavigator?()
                } label: {
                    HStack(spacing: 6) {
                        if let repositoryName {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)

                            Text(repositoryName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)

                            Text("/")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.textTertiary)
                        }

                        if let branchLabel = branchName {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textSecondary)

                            Text(branchLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                        } else if repositoryName == nil {
                            Text("NO WORKTREE")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)

                if let repositoryInfo {
                    remoteBadge(repositoryInfo)
                }

                if let detail = worktreeDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }

                if let lineChanges, !lineChanges.isEmpty {
                    lineChangesView(lineChanges)
                }

                if prAvailability == false {
                    prUnavailableBadge
                }

                if let pullRequest {
                    prBadge(pullRequest)
                }

                if let portSummary, portSummary.hasPorts {
                    portsBadge(portSummary)
                }

                Spacer()

                if showsGitMenu {
                    gitActionsMenu
                }

                if let onRun {
                    HStack(spacing: 6) {
                        if runIsActive, let onStop {
                            actionButton(
                                icon: "stop.fill",
                                label: "Stop",
                                tint: DevysColors.error,
                                action: onStop,
                                onOpenSettings: onOpenRunSettings
                            )
                        } else {
                            actionButton(
                                icon: "play.fill",
                                label: "Run",
                                tint: DevysColors.success,
                                action: onRun,
                                onOpenSettings: onOpenRunSettings
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, DevysSpacing.space3)
        }
        .frame(height: Self.height)
        .overlay(topBorder, alignment: .top)
    }

    private var showsGitMenu: Bool {
        onFetch != nil ||
        onPull != nil ||
        onPush != nil ||
        onCommit != nil ||
        onCreatePR != nil ||
        onOpenPR != nil
    }

    private var topBorder: some View {
        Rectangle()
            .fill(theme.borderSubtle)
            .frame(height: 1)
    }

    private func lineChangesView(_ changes: WorktreeLineChanges) -> some View {
        HStack(spacing: 4) {
            Text("+\(changes.added)")
                .foregroundStyle(DevysColors.success)
            Text("-\(changes.removed)")
                .foregroundStyle(DevysColors.error)
        }
        .font(.system(size: 10, weight: .semibold))
    }

    private func remoteBadge(_ repositoryInfo: GitRepositoryInfo) -> some View {
        Text(repositoryInfo.remoteStatusLabel)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(remoteBadgeForeground(for: repositoryInfo))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func prBadge(_ pr: PullRequest) -> some View {
        HStack(spacing: 6) {
            if let status = pr.checksStatus {
                Circle()
                    .fill(checksColor(status))
                    .frame(width: 6, height: 6)
            }
            Text("#\(pr.number)")
                .foregroundStyle(theme.textSecondary)
        }
        .font(.system(size: 10, weight: .semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var prUnavailableBadge: some View {
        Text("PR OFF")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func portsBadge(_ summary: WorkspacePortSummary) -> some View {
        let label = summary.totalCount == 1 ? "1 PORT" : "\(summary.totalCount) PORTS"
        let foreground = summary.hasConflicts ? DevysColors.warning : theme.textSecondary

        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var gitActionsMenu: some View {
        Menu {
            Button(action: onFetch ?? {}) {
                Label("Fetch", systemImage: "arrow.trianglehead.clockwise")
            }
            .disabled(onFetch == nil)

            Button(action: onPull ?? {}) {
                Label("Pull", systemImage: "arrow.down.circle")
            }
            .disabled(onPull == nil)

            Button(action: onPush ?? {}) {
                Label("Push", systemImage: "arrow.up.circle")
            }
            .disabled(onPush == nil)

            Divider()

            Button(action: onCommit ?? {}) {
                Label("Commit", systemImage: "checkmark.circle")
            }
            .disabled(onCommit == nil || !hasStagedChanges)

            Divider()

            Button(action: onCreatePR ?? {}) {
                Label("Create Pull Request", systemImage: "arrow.triangle.pull")
            }
            .disabled(onCreatePR == nil)

            Button(action: onOpenPR ?? {}) {
                Label("Open Pull Request", systemImage: "arrow.up.forward.app")
            }
            .disabled(onOpenPR == nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .semibold))
                Text("GIT")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(theme.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func checksColor(_ status: ChecksStatus) -> Color {
        switch status {
        case .passing:
            return DevysColors.success
        case .pending:
            return DevysColors.warning
        case .failing:
            return DevysColors.error
        }
    }

    private func remoteBadgeForeground(for repositoryInfo: GitRepositoryInfo) -> Color {
        if !repositoryInfo.hasUpstream {
            return theme.textTertiary
        }
        if repositoryInfo.behindCount > 0 {
            return DevysColors.warning
        }
        if repositoryInfo.aheadCount > 0 {
            return theme.textSecondary
        }
        return DevysColors.success
    }

    private func actionButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void,
        onOpenSettings: (() -> Void)?
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onOpenSettings {
                Button("Edit Startup Profiles") {
                    onOpenSettings()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("StatusBar Light") {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            Color.blue.opacity(0.2)
                .frame(width: 48)
            Color.green.opacity(0.2)
                .frame(width: 240)
            Color.orange.opacity(0.2)
        }
        .frame(height: 300)

        StatusBar(
            repositoryName: "devys",
            branchName: "main",
            repositoryInfo: GitRepositoryInfo(currentBranch: "main", upstreamBranch: "origin/main"),
            worktreeDetail: ".",
            lineChanges: WorktreeLineChanges(added: 12, removed: 3),
            pullRequest: nil,
            prAvailability: true,
            portSummary: WorkspacePortSummary(totalCount: 2, conflictCount: 0),
            hasStagedChanges: true,
            onFetch: {},
            onPull: {},
            onPush: {},
            onCommit: {},
            onCreatePR: {},
            onOpenPR: nil,
            runIsActive: false,
            onRun: {},
            onStop: {},
            onOpenRunSettings: {},
            onToggleNavigator: {}
        )
    }
    .frame(width: 800)
    .environment(\.devysTheme, DevysTheme(isDark: false))
}

#Preview("StatusBar Dark") {
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            Color.blue.opacity(0.2)
                .frame(width: 48)
            Color.green.opacity(0.2)
                .frame(width: 240)
            Color.orange.opacity(0.2)
        }
        .frame(height: 300)

        StatusBar(
            repositoryName: "devys",
            branchName: "feature/worktree-ui",
            repositoryInfo: GitRepositoryInfo(currentBranch: "feature/worktree-ui"),
            worktreeDetail: "../feature/worktree-ui",
            lineChanges: WorktreeLineChanges(added: 0, removed: 0),
            pullRequest: nil,
            prAvailability: false,
            portSummary: WorkspacePortSummary(totalCount: 1, conflictCount: 1),
            hasStagedChanges: false,
            onFetch: {},
            onPull: {},
            onPush: {},
            onCommit: nil,
            onCreatePR: nil,
            onOpenPR: nil,
            runIsActive: true,
            onRun: {},
            onStop: {},
            onOpenRunSettings: {},
            onToggleNavigator: {}
        )
    }
    .frame(width: 800)
    .environment(\.devysTheme, DevysTheme(isDark: true))
    .preferredColorScheme(.dark)
}
