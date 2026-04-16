// RepoItem.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Repository item in the left rail.
///
/// Displays a 2-letter abbreviation (or optional SF Symbol) in a circle.
/// Active state shows an accent ring. Tooltip shows the full repo name.
public struct RepoItem: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let abbreviation: String
    private let customSymbol: String?
    private let repoName: String
    private let isActive: Bool
    private let onSelect: () -> Void

    @State private var isHovered = false

    public init(
        abbreviation: String,
        customSymbol: String? = nil,
        repoName: String = "",
        isActive: Bool = false,
        onSelect: @escaping () -> Void
    ) {
        self.abbreviation = String(abbreviation.prefix(2))
        self.customSymbol = customSymbol
        self.repoName = repoName
        self.isActive = isActive
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            ZStack {
                // Background circle
                Circle()
                    .fill(backgroundColor)
                    .frame(width: layout.repoItemSize, height: layout.repoItemSize)

                // Active ring
                if isActive {
                    Circle()
                        .strokeBorder(theme.accent, lineWidth: 2)
                        .frame(width: layout.repoItemSize, height: layout.repoItemSize)
                }

                // Content: symbol or abbreviation
                Group {
                    if let customSymbol {
                        Image(systemName: customSymbol)
                            .font(Typography.label.weight(.semibold))
                    } else {
                        Text(abbreviation.uppercased())
                            .font(Typography.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(foregroundColor)
            }
        }
        .buttonStyle(.plain)
        .help(repoName.isEmpty ? abbreviation : repoName)
        .accessibilityLabel(repoName.isEmpty ? abbreviation : repoName)
        .onHover { hovering in
            withAnimation(Animations.micro) { isHovered = hovering }
        }
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        if isActive { return theme.accentMuted }
        if isHovered { return theme.hover }
        return theme.overlay
    }

    private var foregroundColor: Color {
        if isActive { return theme.accent }
        if isHovered { return theme.text }
        return theme.textSecondary
    }
}

// MARK: - Previews

#Preview("Repo Items") {
    HStack(spacing: Spacing.space2) {
        RepoItem(abbreviation: "DV", repoName: "devys", isActive: true) {}
        RepoItem(abbreviation: "AF", repoName: "agent-flows") {}
        RepoItem(abbreviation: "UI", customSymbol: "paintbrush.fill", repoName: "devys-ui") {}
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
