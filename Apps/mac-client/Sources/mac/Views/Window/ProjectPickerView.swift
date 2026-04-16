// ProjectPickerView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct ProjectPickerView: View {
    @Environment(\.devysTheme) private var theme

    let recentRepositories: [URL]
    let canRestorePreviousSession: Bool
    let onAddRepository: () -> Void
    let onRestorePreviousSession: () -> Void
    let onOpenRecentRepository: (URL) -> Void

    var body: some View {
        VStack(spacing: Spacing.space8) {
            Spacer()

            // Welcome heading
            VStack(spacing: Spacing.space2) {
                Image(systemName: "hand.wave")
                    .font(Typography.display.weight(.light))
                    .foregroundStyle(theme.textTertiary)

                Text("Welcome to Devys")
                    .font(Typography.title)
                    .foregroundStyle(theme.text)
            }

            Separator()
                .frame(maxWidth: 500)
                .padding(.horizontal, Spacing.space8)

            // Recent projects or empty state
            if recentRepositories.isEmpty {
                emptyState
            } else {
                recentList
            }

            Separator()
                .frame(maxWidth: 500)
                .padding(.horizontal, Spacing.space8)

            actionsSection

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.space2) {
            Text("No recent projects")
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)

            Text("Add a project to get started")
                .font(Typography.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.vertical, Spacing.space4)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Text("Recent Projects")
                .font(Typography.heading)
                .foregroundStyle(theme.textSecondary)
                .padding(.leading, Spacing.space4)

            VStack(spacing: 0) {
                ForEach(recentRepositories, id: \.self) { url in
                    RecentRepositoryRow(url: url) {
                        onOpenRecentRepository(url)
                    }
                }
            }
            .frame(maxWidth: 500)
        }
    }

    private var actionsSection: some View {
        VStack(spacing: Spacing.space3) {
            ActionButton("Add Repository", icon: "folder.badge.plus", style: .primary) {
                onAddRepository()
            }
            .keyboardShortcut("o", modifiers: .command)

            if canRestorePreviousSession {
                Button(action: onRestorePreviousSession) {
                    HStack(spacing: Spacing.space2) {
                        Text("Restore previous session")
                            .font(Typography.body)
                            .foregroundStyle(theme.accent)
                        Text("Reopen repositories and workspace state")
                            .font(Typography.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Recent Repository Row

private struct RecentRepositoryRow: View {
    @Environment(\.devysTheme) private var theme

    let url: URL
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "folder")
                    .font(Typography.heading)
                    .foregroundStyle(theme.textSecondary)

                Text(url.lastPathComponent)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isHovered ? theme.accent : theme.text)

                Spacer()

                Text(shortenedPath)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.space4)
            .padding(.vertical, Spacing.space2)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .fill(isHovered ? theme.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    private var shortenedPath: String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
