// Toolbar.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Horizontal toolbar for panel headers.
///
/// Three slots: leading (left-aligned), center (centered), trailing (right-aligned).
/// Background is the surface level with a subtle bottom border.
public struct Toolbar<Leading: View, Center: View, Trailing: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.densityLayout) private var layout

    private let leading: Leading
    private let center: Center
    private let trailing: Trailing

    public init(
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder center: () -> Center = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Center content
                HStack {
                    Spacer()
                    center
                    Spacer()
                }

                // Leading + Trailing content
                HStack(spacing: 0) {
                    leading
                    Spacer()
                    trailing
                }
            }
            .padding(.horizontal, Spacing.space3)
            .frame(height: layout.toolbarHeight)
            .background(theme.card)

            // Bottom border
            Rectangle()
                .fill(theme.border)
                .frame(height: Spacing.borderWidth)
        }
    }
}

// MARK: - Previews

#Preview("Toolbar") {
    VStack(spacing: Spacing.space4) {
        Toolbar {
            ActionButton("Back", icon: "chevron.left", style: .ghost) {}
        } center: {
            Text("Package.swift")
                .font(Typography.label)
                .foregroundStyle(Color(hex: "#EDE8E0"))
        } trailing: {
            HStack(spacing: Spacing.space1) {
                ActionButton("Share", icon: "square.and.arrow.up", style: .ghost) {}
                ActionButton("More", icon: "ellipsis", style: .ghost) {}
            }
        }

        Toolbar {
            Text("Explorer")
                .font(Typography.heading)
                .foregroundStyle(Color(hex: "#9E978C"))
        } trailing: {
            ActionButton("New", icon: "plus", style: .ghost) {}
        }
    }
    .frame(width: 400)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
