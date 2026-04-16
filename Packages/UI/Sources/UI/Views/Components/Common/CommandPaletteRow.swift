// CommandPaletteRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Individual result row in the command palette.
///
/// Shows an icon, title with optional subtitle, and an optional keyboard shortcut badge.
/// Active state highlights with accent-muted background and a left accent border.
public struct CommandPaletteRow: View {
    @Environment(\.theme) private var theme

    private let icon: String
    private let iconColor: Color?
    private let title: String
    private let subtitle: String?
    private let shortcut: String?
    private let isActive: Bool

    @State private var isHovered = false

    public init(
        icon: String,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        shortcut: String? = nil,
        isActive: Bool = false
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.shortcut = shortcut
        self.isActive = isActive
    }

    public var body: some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: icon)
                .font(Typography.title.weight(.regular))
                .foregroundStyle(iconColor ?? theme.textSecondary)
                .frame(width: 18, height: 18)

            titleLabel

            Spacer(minLength: 4)

            if let shortcut {
                ShortcutBadge(shortcut)
            }
        }
        .padding(.horizontal, Spacing.space3)
        .frame(height: 36)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(theme.accent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var titleLabel: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Typography.body)
                .foregroundStyle(theme.text)
                .lineLimit(1)

            if let subtitle {
                Text(" \u{2014} ")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                + Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .lineLimit(1)
    }

    private var backgroundColor: Color {
        if isActive {
            return theme.accentMuted
        }
        return isHovered ? theme.accentSubtle : .clear
    }
}

// MARK: - Previews

#Preview("Command Palette Rows") {
    VStack(spacing: 2) {
        CommandPaletteRow(
            icon: "doc.text",
            title: "ContentView.swift",
            subtitle: "Views/Window",
            shortcut: "Cmd+P",
            isActive: true
        )
        CommandPaletteRow(
            icon: "terminal",
            iconColor: Colors.success,
            title: "Run Build",
            subtitle: "Tasks",
            shortcut: "Cmd+B"
        )
        CommandPaletteRow(
            icon: "sparkles",
            iconColor: AgentColor.forIndex(2).solid,
            title: "Ask Agent",
            subtitle: "AI Assistant"
        )
        CommandPaletteRow(
            icon: "gearshape",
            title: "Settings",
            shortcut: "Cmd+,"
        )
    }
    .frame(width: 480)
    .padding(Spacing.space4)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
