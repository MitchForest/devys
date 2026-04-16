// DiffRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A diff file entry in the Changes sidebar section.
///
/// Shows git status indicator, file name, addition/deletion counts,
/// and hover-revealed stage/unstage/discard action buttons.
public struct DiffRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let fileName: String
    private let gitStatus: GitFileStatus
    private let additions: Int
    private let deletions: Int
    private let isStaged: Bool
    private let onTap: () -> Void
    private let onStage: (() -> Void)?
    private let onUnstage: (() -> Void)?
    private let onDiscard: (() -> Void)?

    @State private var isHovered = false

    public init(
        fileName: String,
        gitStatus: GitFileStatus,
        additions: Int = 0,
        deletions: Int = 0,
        isStaged: Bool = false,
        onTap: @escaping () -> Void,
        onStage: (() -> Void)? = nil,
        onUnstage: (() -> Void)? = nil,
        onDiscard: (() -> Void)? = nil
    ) {
        self.fileName = fileName
        self.gitStatus = gitStatus
        self.additions = additions
        self.deletions = deletions
        self.isStaged = isStaged
        self.onTap = onTap
        self.onStage = onStage
        self.onUnstage = onUnstage
        self.onDiscard = onDiscard
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.space2) {
                // Git status indicator
                GitStatusIndicator(gitStatus)

                // File name
                Text(fileName)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                Spacer(minLength: Spacing.space1)

                // Change stats
                if !isHovered {
                    changeStats
                }

                // Hover action buttons
                if isHovered {
                    hoverActions
                }
            }
            .padding(.horizontal, layout.itemPaddingH)
            .frame(height: layout.sidebarRowHeight)
            .background(
                isHovered ? theme.hover : .clear,
                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    // MARK: - Change Stats

    private var changeStats: some View {
        HStack(spacing: Spacing.space1) {
            if additions > 0 {
                Text("+\(additions)")
                    .font(Typography.micro)
                    .foregroundStyle(theme.success)
            }
            if deletions > 0 {
                Text("-\(deletions)")
                    .font(Typography.micro)
                    .foregroundStyle(theme.error)
            }
        }
    }

    // MARK: - Hover Actions

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: Spacing.space1) {
            // Always show stats even on hover, just compact
            changeStats

            if isStaged {
                if let onUnstage {
                    ActionButton("Unstage", style: .ghost, action: onUnstage)
                        .controlSize(.small)
                }
            } else {
                if let onStage {
                    ActionButton("Stage", style: .ghost, action: onStage)
                        .controlSize(.small)
                }
                if let onDiscard {
                    ActionButton(
                        "Discard",
                        style: .ghost,
                        tone: .destructive,
                        action: onDiscard
                    )
                        .controlSize(.small)
                }
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Previews

#Preview("Diff Rows") {
    VStack(spacing: 0) {
        DiffRow(
            fileName: "ContentView.swift",
            gitStatus: .modified,
            additions: 12,
            deletions: 3,
            isStaged: false,
            onTap: {},
            onStage: {},
            onDiscard: {}
        )
        DiffRow(
            fileName: "AppDelegate.swift",
            gitStatus: .staged,
            additions: 5,
            deletions: 0,
            isStaged: true,
            onTap: {},
            onUnstage: {}
        )
        DiffRow(
            fileName: "NewFile.swift",
            gitStatus: .new,
            additions: 42,
            deletions: 0,
            isStaged: false,
            onTap: {},
            onStage: {}
        )
        DiffRow(
            fileName: "OldHelper.swift",
            gitStatus: .deleted,
            additions: 0,
            deletions: 87,
            isStaged: false,
            onTap: {},
            onStage: {},
            onDiscard: {}
        )
        DiffRow(
            fileName: "Config.swift",
            gitStatus: .conflict,
            additions: 8,
            deletions: 4,
            isStaged: false
        ) {}
    }
    .frame(width: 320)
    .padding(.vertical, Spacing.space2)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
