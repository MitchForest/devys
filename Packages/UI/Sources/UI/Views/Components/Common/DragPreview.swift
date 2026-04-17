// DragPreview.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A floating tab preview shown during drag operations.
///
/// Renders a simplified tab pill at 90% opacity with an elevated shadow
/// and slight scale-up to communicate "in flight."
public struct DragPreview: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let title: String
    private let icon: String?
    private let agentColor: AgentColor?
    private let minWidth: CGFloat?
    private let maxWidth: CGFloat?
    private let height: CGFloat?

    public init(
        title: String,
        icon: String? = nil,
        agentColor: AgentColor? = nil,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        height: CGFloat? = nil
    ) {
        self.title = title
        self.icon = icon
        self.agentColor = agentColor
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.height = height
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Agent identity stripe
            if let agentColor {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(agentColor.solid)
                    .frame(width: 2)
            }

            HStack(spacing: Spacing.space1) {
                if let icon {
                    DevysIcon(icon, size: 14)
                        .foregroundStyle(theme.textTertiary)
                }

                Text(title)
                    .font(Typography.label)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.space2)
        }
        .frame(height: height ?? layout.tabHeight)
        .frame(
            minWidth: minWidth ?? Spacing.tabMinWidth,
            maxWidth: maxWidth ?? Spacing.tabMaxWidth
        )
        .background(theme.card, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                .strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
        .shadowStyle(Shadows.lg)
        .opacity(0.9)
        .scaleEffect(1.05)
    }
}

// MARK: - Previews

#Preview("Drag Preview") {
    VStack(spacing: Spacing.space6) {
        DragPreview(title: "AppDelegate.swift", icon: "swift")

        DragPreview(
            title: "API Refactor",
            icon: "person.crop.circle",
            agentColor: .forIndex(1)
        )

        DragPreview(title: "Package.swift")
    }
    .padding(40)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
    .environment(\.densityLayout, DensityLayout(.comfortable))
}
