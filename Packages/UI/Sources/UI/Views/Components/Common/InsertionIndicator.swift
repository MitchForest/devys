// InsertionIndicator.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A 2pt vertical line shown between tabs during drag reorder.
///
/// Appears at the insertion point to communicate where the tab will land.
/// Uses accent color by default for clear visibility against tab backgrounds.
public struct InsertionIndicator: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let color: Color?

    public init(color: Color? = nil) {
        self.color = color
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color ?? theme.accent)
            .frame(width: 2, height: layout.tabHeight)
    }
}

// MARK: - Previews

#Preview("Insertion Indicator") {
    let theme = Theme(isDark: true)
    HStack(spacing: Spacing.space1) {
        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            .fill(Color(hex: "#1C1A17"))
            .frame(width: 140, height: 34)
            .overlay(
                Text("Tab A")
                    .font(Typography.label)
                    .foregroundStyle(Color(hex: "#9E978C"))
            )

        InsertionIndicator()

        RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            .fill(Color(hex: "#1C1A17"))
            .frame(width: 140, height: 34)
            .overlay(
                Text("Tab B")
                    .font(Typography.label)
                    .foregroundStyle(Color(hex: "#9E978C"))
            )
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, theme)
    .environment(\.densityLayout, DensityLayout(.comfortable))
}
