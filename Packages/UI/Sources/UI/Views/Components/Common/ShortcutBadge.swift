// ShortcutBadge.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Badge displaying a keyboard shortcut.
///
/// Chip-style: monospace text on an elevated background with standard radius.
public struct ShortcutBadge: View {
    @Environment(\.theme) private var theme

    private let keys: String

    public init(_ keys: String) {
        self.keys = keys
    }

    public var body: some View {
        Text(keys)
            .font(Typography.Code.gutter.weight(.medium))
            .foregroundStyle(theme.textTertiary)
            .padding(.horizontal, Spacing.normal)
            .padding(.vertical, 3)
            .background(theme.overlay, in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Shortcuts") {
    HStack(spacing: Spacing.space2) {
        ShortcutBadge("⌘K")
        ShortcutBadge("⌃⇧P")
        ShortcutBadge("⌘S")
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
