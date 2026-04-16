// FolderRow.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A folder entry in the sidebar file tree.
///
/// Features a disclosure triangle that rotates smoothly on expand/collapse,
/// folder name in medium weight, and an optional item count badge.
public struct FolderRow: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let name: String
    private let depth: Int
    private let isExpanded: Bool
    private let itemCount: Int?
    private let onToggle: () -> Void

    @State private var isHovered = false

    public init(
        name: String,
        depth: Int = 0,
        isExpanded: Bool = false,
        itemCount: Int? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.name = name
        self.depth = depth
        self.isExpanded = isExpanded
        self.itemCount = itemCount
        self.onToggle = onToggle
    }

    public var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.space2) {
                // Disclosure triangle
                Image(systemName: "chevron.right")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(Animations.micro, value: isExpanded)
                    .frame(width: 12)

                // Folder name
                Text(name)
                    .font(Typography.body.weight(.medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                // Optional item count
                if let itemCount {
                    Text("\(itemCount)")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: Spacing.space1)
            }
            .padding(.leading, indentation + layout.itemPaddingH)
            .padding(.trailing, layout.itemPaddingH)
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

    // MARK: - Computed Properties

    private var indentation: CGFloat {
        CGFloat(depth) * Spacing.space4
    }
}

// MARK: - Previews

#Preview("Folder Rows") {
    VStack(spacing: 0) {
        FolderRow(name: "Sources", depth: 0, isExpanded: true, itemCount: 12) {}
        FolderRow(name: "Models", depth: 1, isExpanded: true, itemCount: 5) {}
        FolderRow(name: "Views", depth: 1, isExpanded: false, itemCount: 8) {}
        FolderRow(name: "Components", depth: 2, isExpanded: false) {}
        FolderRow(name: "Tests", depth: 0, isExpanded: false, itemCount: 3) {}
    }
    .frame(width: 280)
    .padding(.vertical, Spacing.space2)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
