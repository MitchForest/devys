// ConnectorLine.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Subtle vertical and horizontal connector lines for file tree indentation.
///
/// Draws vertical guide lines at each depth level and an L-shaped connector
/// for the last child in a group. Uses SwiftUI `Path` drawing with theme border colors.
public struct ConnectorLine: View {
    @Environment(\.theme) private var theme

    private let depth: Int
    private let isLast: Bool
    // Reserved for future connector variants (e.g., expanded folder connector).
    // periphery:ignore
    private let hasChildren: Bool

    /// The horizontal offset per depth level.
    private let indentStep: CGFloat = Spacing.space4

    /// Line weight.
    private let lineWeight: CGFloat = Spacing.borderWidth

    public init(
        depth: Int,
        isLast: Bool = false,
        hasChildren: Bool = false
    ) {
        self.depth = depth
        self.isLast = isLast
        self.hasChildren = hasChildren
    }

    public var body: some View {
        Canvas { context, size in
            let color = theme.border
            var path = Path()

            // Draw vertical guide lines for each ancestor depth
            for level in 0..<depth {
                let x = xPosition(for: level, in: size)

                if level == depth - 1 {
                    // Current level: draw connector
                    if isLast {
                        // L-shaped: vertical line from top to midpoint, then horizontal
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height / 2))
                        path.addLine(to: CGPoint(x: x + indentStep / 2, y: size.height / 2))
                    } else {
                        // T-shaped: full vertical line + horizontal to item
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        path.move(to: CGPoint(x: x, y: size.height / 2))
                        path.addLine(to: CGPoint(x: x + indentStep / 2, y: size.height / 2))
                    }
                } else {
                    // Ancestor levels: full vertical line
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }

            context.stroke(
                path,
                with: .color(color),
                lineWidth: lineWeight
            )
        }
        .frame(width: CGFloat(depth) * indentStep)
    }

    // MARK: - Helpers

    private func xPosition(for level: Int, in _: CGSize) -> CGFloat {
        (CGFloat(level) + 0.5) * indentStep
    }
}

// MARK: - Previews

#Preview("Connector Lines") {
    let theme = Theme(isDark: true)

    VStack(spacing: 0) {
        // Simulate a file tree with connectors
        HStack(spacing: 0) {
            ConnectorLine(depth: 1, isLast: false)
            Text("first-child.swift")
                .font(Typography.body)
                .foregroundStyle(theme.text)
            Spacer()
        }
        .frame(height: 32)

        HStack(spacing: 0) {
            ConnectorLine(depth: 1, isLast: false)
            Text("middle-child.swift")
                .font(Typography.body)
                .foregroundStyle(theme.text)
            Spacer()
        }
        .frame(height: 32)

        HStack(spacing: 0) {
            ConnectorLine(depth: 1, isLast: true)
            Text("last-child.swift")
                .font(Typography.body)
                .foregroundStyle(theme.text)
            Spacer()
        }
        .frame(height: 32)

        HStack(spacing: 0) {
            ConnectorLine(depth: 2, isLast: false)
            Text("nested/item.swift")
                .font(Typography.body)
                .foregroundStyle(theme.text)
            Spacer()
        }
        .frame(height: 32)

        HStack(spacing: 0) {
            ConnectorLine(depth: 2, isLast: true, hasChildren: true)
            Text("nested/last.swift")
                .font(Typography.body)
                .foregroundStyle(theme.text)
            Spacer()
        }
        .frame(height: 32)
    }
    .frame(width: 280)
    .padding(Spacing.space4)
    .background(Color(hex: "#121110"))
    .environment(\.theme, theme)
}
