// WorkspaceCanvasToolbar.swift
// Devys - Active workspace terminal launcher toolbar.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct WorkspaceCanvasToolbar: View {
    @Environment(\.devysTheme) private var theme

    let repositoryName: String?
    let workspaceName: String?
    let isSidebarVisible: Bool
    let onToggleSidebar: () -> Void
    let onAgents: (() -> Void)?
    let onShell: (() -> Void)?
    let onClaude: (() -> Void)?
    let onCodex: (() -> Void)?
    let onRun: (() -> Void)?
    let onOpenRepositorySettings: (() -> Void)?
    let runDisabledReason: String?

    var body: some View {
        HStack(spacing: DevysSpacing.space3) {
            Button(action: onToggleSidebar) {
                Image(systemName: isSidebarVisible ? "sidebar.right" : "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(isSidebarVisible ? "Hide Sidebar (⌘\\)" : "Show Sidebar (⌘\\)")

            workspaceLabel

            Spacer()

            HStack(spacing: DevysSpacing.space2) {
                actionButton("Agents", icon: "message.badge.waveform", action: onAgents)
                actionButton("Shell", icon: "terminal", action: onShell)
                actionButton("Claude", icon: "brain", action: onClaude)
                actionButton("Codex", icon: "chevron.left.forwardslash.chevron.right", action: onCodex)
                actionButton("Run", icon: "play.fill", action: onRun)
                    .help(runDisabledReason ?? "Run the active workspace startup profile")
            }

            if let runDisabledReason,
               let onOpenRepositorySettings {
                Button("Settings") {
                    onOpenRepositorySettings()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .help(runDisabledReason)
            }
        }
        .padding(.horizontal, DevysSpacing.space3)
        .padding(.vertical, DevysSpacing.space2)
        .background(theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
        }
    }

    private var workspaceLabel: some View {
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

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.textSecondary)

            Text(workspaceName ?? "No Workspace")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(workspaceName == nil ? theme.textTertiary : theme.text)
                .lineLimit(1)
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(action == nil ? theme.textTertiary : theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(action == nil ? theme.base : theme.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        action == nil ? theme.borderSubtle : theme.border,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
