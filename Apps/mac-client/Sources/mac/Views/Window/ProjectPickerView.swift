// ProjectPickerView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct ProjectPickerView: View {
    @Environment(\.devysTheme) private var theme

    let recentFolders: [URL]
    let onOpenFolder: () -> Void
    let onOpenRecent: (URL) -> Void

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
            if recentFolders.isEmpty {
                emptyState
            } else {
                recentList
            }

            // Divider
            TerminalDivider()
                .frame(maxWidth: 500)
                .padding(.horizontal, DevysSpacing.space8)

            // Open folder action
            openFolderSection

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }

    private var emptyState: some View {
        VStack(spacing: DevysSpacing.space2) {
            Text("no recent projects")
                .font(DevysTypography.sm)
                .foregroundStyle(theme.textSecondary)

            Text("$ open a folder to get started")
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
                ForEach(Array(recentFolders.enumerated()), id: \.element) { index, url in
                    RecentFolderRow(
                        url: url,
                        isLast: index == recentFolders.count - 1
                    ) {
                        onOpenRecent(url)
                    }
                }
            }
            .frame(maxWidth: 500)
        }
    }

    private var openFolderSection: some View {
        HStack(spacing: DevysSpacing.space3) {
            TerminalCommandButton("open folder", icon: "folder", isAccent: true) {
                onOpenFolder()
            }
            
            KeyboardShortcutBadge("CMD+O")
        }
    }
}

// MARK: - Recent Folder Row

private struct RecentFolderRow: View {
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
