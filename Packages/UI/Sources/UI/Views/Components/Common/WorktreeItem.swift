// WorktreeItem.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Worktree item nested under a repo in the left rail.
///
/// Shows a position number (doubling as keyboard shortcut hint) and a
/// status dot. The full branch name appears in the tooltip on hover.
/// Active state highlights the number.
public struct WorktreeItem: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let index: Int
    private let branchName: String
    private let isActive: Bool
    private let statusHint: StatusHint?
    private let onSelect: () -> Void

    @State private var isHovered = false

    public init(
        index: Int,
        branchName: String,
        isActive: Bool = false,
        statusHint: StatusHint? = nil,
        onSelect: @escaping () -> Void
    ) {
        self.index = index
        self.branchName = branchName
        self.isActive = isActive
        self.statusHint = statusHint
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 4) {
                // Status dot
                Circle()
                    .fill(dotColor)
                    .frame(width: 5, height: 5)

                // Position number (keyboard shortcut hint)
                Text("\(index + 1)")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(labelColor)
                    .monospacedDigit()
            }
            .frame(width: layout.repoItemSize, height: layout.worktreeItemHeight)
            .background(
                isActive
                    ? AnyShapeStyle(theme.accentSubtle)
                    : isHovered
                        ? AnyShapeStyle(theme.hover)
                        : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: Spacing.radiusMicro, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(shortcutHint)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    // MARK: - Computed

    private var shortcutHint: String {
        if index < 9 {
            return "\(branchName)  ⌘\(index + 1)"
        }
        return branchName
    }

    private var dotColor: Color {
        if let statusHint { return statusHint.color(theme: theme) }
        if isActive { return theme.accent }
        return theme.textTertiary
    }

    private var labelColor: Color {
        if isActive { return theme.text }
        if isHovered { return theme.textSecondary }
        return theme.textTertiary
    }
}

// MARK: - Previews

#Preview("Worktree Items") {
    VStack(spacing: Spacing.space1) {
        WorktreeItem(index: 0, branchName: "main", isActive: true) {}
        WorktreeItem(index: 1, branchName: "feature/auth", statusHint: .dirty) {}
        WorktreeItem(index: 2, branchName: "dev") {}
        WorktreeItem(index: 3, branchName: "hotfix/crash", statusHint: .error) {}
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
