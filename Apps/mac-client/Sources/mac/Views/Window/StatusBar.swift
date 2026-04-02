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
    
    let branchName: String?
    let worktreeDetail: String?
    let lineChanges: WorktreeLineChanges?
    let pullRequest: PullRequest?
    let prAvailability: Bool?
    let runIsActive: Bool
    let onRun: (() -> Void)?
    let onStop: (() -> Void)?
    let onEditRunCommand: (() -> Void)?
    let onClearRunCommand: (() -> Void)?
    
    static var height: CGFloat { 24 }
    
    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(theme.surface)

            HStack(spacing: DevysSpacing.space3) {
                if let branchLabel = branchName {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)

                        Text(branchLabel)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.text)
                    }
                } else {
                    Text("NO WORKTREE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
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

                Spacer()

                if let onRun {
                    HStack(spacing: 6) {
                        if runIsActive, let onStop {
                            actionButton(
                                icon: "stop.fill",
                                label: "Stop",
                                tint: DevysColors.error,
                                action: onStop,
                                onEdit: onEditRunCommand,
                                onClear: onClearRunCommand
                            )
                        } else {
                            actionButton(
                                icon: "play.fill",
                                label: "Run",
                                tint: DevysColors.success,
                                action: onRun,
                                onEdit: onEditRunCommand,
                                onClear: onClearRunCommand
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

    private func actionButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void,
        onEdit: (() -> Void)?,
        onClear: (() -> Void)?
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
            if let onEdit {
                Button("Edit Run Command") {
                    onEdit()
                }
            }
            if let onClear {
                Button("Clear Run Command") {
                    onClear()
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
            branchName: "main",
            worktreeDetail: ".",
            lineChanges: WorktreeLineChanges(added: 12, removed: 3),
            pullRequest: nil,
            prAvailability: true,
            runIsActive: false,
            onRun: {},
            onStop: {},
            onEditRunCommand: {},
            onClearRunCommand: {}
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
            branchName: "feature/worktree-ui",
            worktreeDetail: "../feature/worktree-ui",
            lineChanges: WorktreeLineChanges(added: 0, removed: 0),
            pullRequest: nil,
            prAvailability: false,
            runIsActive: true,
            onRun: {},
            onStop: {},
            onEditRunCommand: {},
            onClearRunCommand: {}
        )
    }
    .frame(width: 800)
    .environment(\.devysTheme, DevysTheme(isDark: true))
    .preferredColorScheme(.dark)
}
