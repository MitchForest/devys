// SectionHeader.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Section header with title, optional count badge, and optional trailing action.
public struct SectionHeader: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let count: Int?
    private let actionIcon: String?
    private let action: (() -> Void)?

    @State private var isActionHovered = false

    public init(
        _ title: String,
        count: Int? = nil,
        actionIcon: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.count = count
        self.actionIcon = actionIcon
        self.action = action
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            Text(title)
                .font(Typography.heading)
                .foregroundStyle(theme.textSecondary)

            if let count {
                Chip(.count(count))
            }

            Spacer()

            if let actionIcon, let action {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(Typography.label)
                        .foregroundStyle(isActionHovered ? theme.text : theme.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(
                            isActionHovered ? theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .onHover { h in
                    withAnimation(Animations.micro) { isActionHovered = h }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Section Headers") {
    VStack(alignment: .leading, spacing: Spacing.space4) {
        SectionHeader("Files")
        SectionHeader("Staged Changes", count: 3)
        SectionHeader("Agents", count: 2, actionIcon: "plus") {}
    }
    .frame(width: 260)
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
