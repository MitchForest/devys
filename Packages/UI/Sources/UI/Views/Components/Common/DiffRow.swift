// DiffRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A diff file entry in the Changes sidebar section.
///
/// Shows git status indicator, file name, and addition/deletion counts.
/// Operations on the file (stage, unstage, discard, open in new window)
/// are exposed through right-click context menus and an optional
/// double-click on the host row, not through hover-revealed buttons.
/// The baseline UI stays quiet; power-user actions stay discoverable
/// but out of the way.
public struct DiffRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let fileName: String
    private let gitStatus: GitFileStatus
    private let additions: Int
    private let deletions: Int
    private let isStaged: Bool
    private let onTap: () -> Void
    private let onDoubleTap: (() -> Void)?

    @State private var isHovered = false

    public init(
        fileName: String,
        gitStatus: GitFileStatus,
        additions: Int = 0,
        deletions: Int = 0,
        isStaged: Bool = false,
        onTap: @escaping () -> Void,
        onDoubleTap: (() -> Void)? = nil
    ) {
        self.fileName = fileName
        self.gitStatus = gitStatus
        self.additions = additions
        self.deletions = deletions
        self.isStaged = isStaged
        self.onTap = onTap
        self.onDoubleTap = onDoubleTap
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            GitStatusIndicator(gitStatus)

            Text(fileName)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer(minLength: Spacing.space1)

            changeStats
        }
        .padding(.horizontal, layout.itemPaddingH)
        .frame(height: layout.sidebarRowHeight)
        .background(
            isHovered ? theme.text.opacity(0.05) : .clear,
            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .onTapGesture(count: 2) {
            (onDoubleTap ?? onTap)()
        }
        .onTapGesture(count: 1) {
            onTap()
        }
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
            onTap: {}
        )
        DiffRow(
            fileName: "AppDelegate.swift",
            gitStatus: .staged,
            additions: 5,
            deletions: 0,
            isStaged: true,
            onTap: {}
        )
        DiffRow(
            fileName: "NewFile.swift",
            gitStatus: .new,
            additions: 42,
            deletions: 0,
            isStaged: false,
            onTap: {}
        )
        DiffRow(
            fileName: "OldHelper.swift",
            gitStatus: .deleted,
            additions: 0,
            deletions: 87,
            isStaged: false,
            onTap: {}
        )
        DiffRow(
            fileName: "Config.swift",
            gitStatus: .conflict,
            additions: 8,
            deletions: 4,
            isStaged: false,
            onTap: {}
        )
    }
    .frame(width: 320)
    .padding(.vertical, Spacing.space2)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
