// Separator.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A themed divider using border tokens.
public struct Separator: View {
    @Environment(\.theme) private var theme

    private let axis: Axis

    public init(_ axis: Axis = .horizontal) {
        self.axis = axis
    }

    public var body: some View {
        switch axis {
        case .horizontal:
            Rectangle()
                .fill(theme.border)
                .frame(height: Spacing.borderWidth)
        case .vertical:
            Rectangle()
                .fill(theme.border)
                .frame(width: Spacing.borderWidth)
        }
    }
}

// MARK: - Previews

#Preview("Dividers") {
    VStack(spacing: Spacing.space4) {
        Text("Above")
            .font(Typography.body)
        Separator()
        Text("Below")
            .font(Typography.body)

        HStack(spacing: Spacing.space4) {
            Text("Left")
            Separator(.vertical)
                .frame(height: 20)
            Text("Right")
        }
        .font(Typography.body)
    }
    .foregroundStyle(Color(hex: "#EDE8E0"))
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
