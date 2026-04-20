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

    private static let contentWidth: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: Spacing.space8)

            VStack(spacing: Spacing.space12) {
                DevysLogo(size: .large, tagline: "the ai-native development environment")

                VStack(spacing: Spacing.space6) {
                    if recentRepositories.isEmpty {
                        emptyState
                    } else {
                        recentList
                    }

                    actionsSection
                }
                .frame(maxWidth: Self.contentWidth)
            }

            Spacer(minLength: Spacing.space8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.space2) {
            Text("No recent projects")
                .font(Typography.heading)
                .foregroundStyle(theme.textSecondary)

            Text("Add a local or SSH-backed repository to get started.")
                .font(Typography.caption)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.space6)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            Text("Recent")
                .font(Typography.caption)
                .foregroundStyle(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(Typography.headerTracking)
                .padding(.leading, Spacing.space3)

            VStack(spacing: Spacing.space1) {
                ForEach(recentRepositories, id: \.self) { url in
                    RecentRepositoryRow(url: url) {
                        onOpenRecentRepository(url)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack(spacing: Spacing.space3) {
            ActionButton("Add Repository", icon: "folder.badge.plus", style: .primary) {
                onAddRepository()
            }
            .keyboardShortcut("o", modifiers: .command)

            if canRestorePreviousSession {
                ActionButton(
                    "Restore Previous Session",
                    icon: "clock.arrow.circlepath",
                    style: .ghost
                ) {
                    onRestorePreviousSession()
                }
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
            HStack(spacing: Spacing.space3) {
                DevysIcon("folder", size: Spacing.iconMd, weight: .regular)
                    .foregroundStyle(isHovered ? theme.text : theme.textSecondary)

                Text(url.lastPathComponent)
                    .font(Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(isHovered ? theme.text : theme.text)

                Spacer(minLength: Spacing.space4)

                Text(shortenedPath)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space3)
            .contentShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
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
        url.deletingLastPathComponent()
            .path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
