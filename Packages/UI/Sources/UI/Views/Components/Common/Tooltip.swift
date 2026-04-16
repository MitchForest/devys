// Tooltip.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Tooltip View Modifier

/// Displays a custom tooltip after a hover delay.
///
/// Usage: `.devysTooltip("File path: Sources/ContentView.swift")`
///
/// Respects `accessibilityReduceMotion` — when enabled, the tooltip appears instantly
/// with no fade animation.
struct DevysTooltipModifier: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    let delay: Duration
    let edge: Edge

    @State private var isHovered = false
    @State private var isVisible = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: delay)
                        guard !Task.isCancelled else { return }
                        if reduceMotion {
                            isVisible = true
                        } else {
                            withAnimation(Animations.micro) { isVisible = true }
                        }
                    }
                } else {
                    if reduceMotion {
                        isVisible = false
                    } else {
                        withAnimation(Animations.micro) { isVisible = false }
                    }
                }
            }
            .overlay(alignment: tooltipAlignment) {
                if isVisible {
                    tooltipLabel
                        .transition(.opacity)
                }
            }
    }

    private var tooltipLabel: some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(theme.text)
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, Spacing.space1)
            .background(
                theme.active,
                in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
            )
            .shadowStyle(Shadows.sm)
            .fixedSize()
            .padding(edgePadding)
            .allowsHitTesting(false)
    }

    private var tooltipAlignment: Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    private var edgePadding: EdgeInsets {
        switch edge {
        case .top: EdgeInsets(top: -Spacing.space1, leading: 0, bottom: 0, trailing: 0)
        case .bottom: EdgeInsets(top: 0, leading: 0, bottom: -Spacing.space1, trailing: 0)
        case .leading: EdgeInsets(top: 0, leading: -Spacing.space1, bottom: 0, trailing: 0)
        case .trailing: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: -Spacing.space1)
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Attach a custom tooltip that appears after a hover delay.
    ///
    /// - Parameters:
    ///   - text: The tooltip text.
    ///   - delay: How long to hover before showing. Default 600ms.
    ///   - edge: Which edge to display the tooltip on. Default `.bottom`.
    func devysTooltip(
        _ text: String,
        delay: Duration = .milliseconds(600),
        edge: Edge = .bottom
    ) -> some View {
        modifier(DevysTooltipModifier(text: text, delay: delay, edge: edge))
    }
}

// MARK: - Previews

#Preview("Tooltip") {
    VStack(spacing: Spacing.space8) {
        Text("Hover me (bottom)")
            .font(Typography.body)
            .padding(Spacing.space3)
            .background(Color(hex: "#252320"), in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .devysTooltip("This appears below after 600ms")

        Text("Hover me (top)")
            .font(Typography.body)
            .padding(Spacing.space3)
            .background(Color(hex: "#252320"), in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .devysTooltip("This appears above", edge: .top)

        Text("Quick tooltip")
            .font(Typography.body)
            .padding(Spacing.space3)
            .background(Color(hex: "#252320"), in: RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
            .devysTooltip("Fast!", delay: .milliseconds(200))
    }
    .padding(60)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true))
}
