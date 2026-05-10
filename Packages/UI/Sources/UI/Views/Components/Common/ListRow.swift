// ListRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Standard list row: leading icon + title + subtitle + trailing accessory.
///
/// Hover reveals the interactive layer (background highlight, trailing controls).
public struct ListRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let icon: String?
    private let iconColor: Color?
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing
    private let action: (() -> Void)?

    @State private var isHovered = false

    public init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.trailing = trailing()
    }

    public var body: some View {
        let content = HStack(spacing: Spacing.space2) {
            if let icon {
                DevysIcon(icon, size: 14, weight: .medium)
                    .foregroundStyle(iconColor ?? theme.textSecondary)
                    .frame(width: 18)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            trailing
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, layout.itemPaddingH)
        .padding(.vertical, layout.itemPaddingV)
        .frame(minHeight: layout.listRowHeight)
        .background(
            isHovered ? theme.hover : .clear,
            in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
        )
        .onHover { h in
            withAnimation(Animations.micro) { isHovered = h }
        }

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("List Rows") {
    VStack(spacing: 0) {
        ListRow(
            icon: "doc.text",
            title: "ContentView.swift",
            subtitle: "Views/Window"
        )
        ListRow(
            icon: "terminal",
            iconColor: Colors.success,
            title: "Web Server",
            subtitle: "Running on :3000",
            action: nil
        ) {
            Chip(.status("Running", Colors.success))
        }
        ListRow(
            icon: "person.crop.circle",
            iconColor: AgentColor.forIndex(1).solid,
            title: "API Refactor",
            subtitle: "Working on auth.swift",
            action: nil
        ) {
            StatusDot(.running)
        }
    }
    .frame(width: 280)
    .padding(Spacing.space4)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
