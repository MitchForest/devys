// Elevation.swift
// Devys Design System — Dia-modeled surface elevation system
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Surface elevation levels.
///
/// Each level is a complete recipe: background + corner radius + border + shadow.
/// Use `.elevation(_:)` on any view instead of manually composing these properties.
public enum Elevation: Sendable {
    /// Window background, sidebar, rail, gaps between panes. Flat, no border, no shadow.
    case base

    /// Split pane content areas. Elevated card with subtle shadow.
    case card

    /// Popovers, dropdowns, tooltips, menus. Floating with medium shadow.
    case popover

    /// Modals, command palette, sheets. Highest level with strong shadow.
    case overlay
}

// MARK: - View Modifier

public struct ElevationModifier: ViewModifier {
    @Environment(\.theme) private var theme

    let elevation: Elevation

    public func body(content: Content) -> some View {
        switch elevation {
        case .base:
            content
                .background(theme.base)

        case .card:
            content
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
                )
                .shadowStyle(Shadows.sm)

        case .popover:
            content
                .background(theme.overlay)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
                )
                .shadowStyle(Shadows.md)

        case .overlay:
            content
                .background(theme.overlay)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: Spacing.borderWidth)
                )
                .shadowStyle(Shadows.lg)
        }
    }
}

public extension View {
    /// Applies a complete surface treatment: background, corner radius, border, and shadow.
    func elevation(_ level: Elevation) -> some View {
        modifier(ElevationModifier(elevation: level))
    }
}
