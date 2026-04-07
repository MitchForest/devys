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
        VStack(spacing: DevysSpacing.space10) {
            Spacer()

            // ASCII Logo with tagline
            DevysLogoBlock(showTypewriter: true)

            // Divider
            TerminalDivider()
                .frame(maxWidth: 500)
                .padding(.horizontal, DevysSpacing.space8)

            // Recent projects or empty state
            if recentRepositories.isEmpty {
                emptyState
            } else {
                recentList
            }

            // Divider
            TerminalDivider()
                .frame(maxWidth: 500)
                .padding(.horizontal, DevysSpacing.space8)

            // Open folder action
            actionsSection

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }

    private var emptyState: some View {
        VStack(spacing: DevysSpacing.space2) {
            Text("no recent repositories")
                .font(DevysTypography.sm)
                .foregroundStyle(theme.textSecondary)

            Text("$ add a repository to get started")
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.vertical, DevysSpacing.space4)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space3) {
            // Section header
            Text("RECENT_PROJECTS")
                .font(DevysTypography.heading)
                .tracking(DevysTypography.headerTracking)
                .foregroundStyle(theme.textSecondary)
                .padding(.leading, DevysSpacing.space4)

            // Project list with tree characters
            VStack(spacing: 0) {
                ForEach(Array(recentRepositories.enumerated()), id: \.element) { index, url in
                    RecentRepositoryRow(
                        url: url,
                        isLast: index == recentRepositories.count - 1
                    ) {
                        onOpenRecentRepository(url)
                    }
                }
            }
            .frame(maxWidth: 500)
        }
    }

    private var actionsSection: some View {
        VStack(spacing: DevysSpacing.space3) {
            HStack(spacing: DevysSpacing.space3) {
                TerminalCommandButton("add repository", icon: "folder", isAccent: true) {
                    onAddRepository()
                }
                
                KeyboardShortcutBadge("CMD+O")
            }

            if canRestorePreviousSession {
                Button(action: onRestorePreviousSession) {
                    HStack(spacing: DevysSpacing.space2) {
                        Text("> restore previous session")
                            .font(DevysTypography.sm)
                            .foregroundStyle(theme.accent)
                        Text("reopen repositories and workspace state")
                            .font(DevysTypography.xs)
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
    let isLast: Bool
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DevysSpacing.space2) {
                // Tree drawing characters
                Text(isLast ? "└──" : "├──")
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.textTertiary)

                // Folder name
                Text(url.lastPathComponent)
                    .font(DevysTypography.base)
                    .fontWeight(.medium)
                    .foregroundStyle(isHovered ? theme.accent : theme.text)

                Spacer()

                // Path (shortened)
                Text(shortenedPath)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DevysSpacing.space4)
            .padding(.vertical, DevysSpacing.space2)
            .background(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .fill(isHovered ? theme.elevated : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
    
    private var shortenedPath: String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
