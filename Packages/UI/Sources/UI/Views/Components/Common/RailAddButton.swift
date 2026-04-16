// RailAddButton.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Circular add button for the bottom of the repo rail.
///
/// Matches the visual weight of `RepoItem` tiles. Ghost style at rest,
/// accent-tinted on hover.
public struct RailAddButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let action: () -> Void

    @State private var isHovered = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(Typography.label.weight(.medium))
                .foregroundStyle(isHovered ? theme.accent : theme.textTertiary)
                .frame(width: layout.repoItemSize, height: layout.repoItemSize)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .fill(isHovered ? theme.accentSubtle : .clear)
                        .strokeBorder(
                            isHovered ? theme.accent.opacity(0.3) : theme.border,
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Add Repository")
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }
}

// MARK: - Previews

#Preview("Rail Add Button") {
    VStack(spacing: Spacing.space2) {
        RepoItem(abbreviation: "DV", repoName: "devys", isActive: true) {}
        RailAddButton {}
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
