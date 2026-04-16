// Chip.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Small label for status, counts, tags, and shortcuts.
/// Uses the standard radius (12pt) like everything else.
public struct Chip: View {
    @Environment(\.theme) private var theme

    private let variant: Variant

    public init(_ variant: Variant) {
        self.variant = variant
    }

    public var body: some View {
        switch variant {
        case .status(let label, let statusColor):
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(statusColor)
                .padding(.horizontal, Spacing.normal)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.10), in: chipShape)

        case .count(let value):
            Text("\(value)")
                .font(Typography.micro)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, Spacing.normal)
                .padding(.vertical, 2)
                .background(theme.accentMuted, in: Capsule())
                .frame(minWidth: 20)

        case .tag(let label):
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, Spacing.normal)
                .padding(.vertical, 3)
                .background(theme.overlay, in: chipShape)

        case .shortcut(let keys):
            Text(keys)
                .font(Typography.Code.gutter.weight(.medium))
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, Spacing.normal)
                .padding(.vertical, 3)
                .background(theme.overlay, in: chipShape)
        }
    }

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
    }
}

// MARK: - Variant

public extension Chip {
    enum Variant: Sendable {
        /// Semantic status: "Running", "Complete", "Error"
        case status(String, Color)

        /// Count badge: "3", "12"
        case count(Int)

        /// Tag: file types, categories
        case tag(String)

        /// Keyboard shortcut: "⌘K"
        case shortcut(String)
    }
}

// MARK: - Previews

#Preview("Chips") {
    let theme = Theme(isDark: true)
    VStack(spacing: Spacing.space4) {
        HStack(spacing: Spacing.space2) {
            Chip(.status("Running", Colors.success))
            Chip(.status("Error", Colors.error))
            Chip(.status("Waiting", Colors.warning))
        }
        HStack(spacing: Spacing.space2) {
            Chip(.count(3))
            Chip(.count(42))
        }
        HStack(spacing: Spacing.space2) {
            Chip(.tag("Swift"))
            Chip(.tag("Config"))
        }
        HStack(spacing: Spacing.space2) {
            Chip(.shortcut("⌘K"))
            Chip(.shortcut("⌃⇧P"))
        }
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, theme)
}
