// EmptyState.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Centered empty state with icon, title, description, and optional CTA.
///
/// Generous spacing makes it feel intentional, not broken.
public struct EmptyState: View {
    @Environment(\.theme) private var theme

    private let icon: String
    private let title: String
    private let description: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        description: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.space4) {
            Icon(icon, size: .custom(32), color: theme.textTertiary)

            VStack(spacing: Spacing.space2) {
                Text(title)
                    .font(Typography.heading)
                    .foregroundStyle(theme.textSecondary)

                Text(description)
                    .font(Typography.body)
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let actionTitle, let action {
                ActionButton(actionTitle, style: .primary, action: action)
            }
        }
        .padding(Spacing.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Empty States") {
    VStack {
        EmptyState(
            icon: "doc.text.magnifyingglass",
            title: "No Results",
            description: "Try a different search term."
        )

        Separator()

        EmptyState(
            icon: "sparkles",
            title: "No Agents Running",
            description: "Launch an agent to start coding with AI.",
            actionTitle: "New Agent"
        ) {}
    }
    .frame(width: 400, height: 500)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
