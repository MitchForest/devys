// Shadows.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Shadow tokens. Three presets matching the three elevation levels.
public enum Shadows {

    /// Card surfaces (split panes)
    public static let sm = ShadowStyle(color: .black.opacity(0.06), radius: 4, y: 1)

    /// Popovers, dropdowns, tooltips
    public static let md = ShadowStyle(color: .black.opacity(0.10), radius: 12, y: 4)

    /// Modals, command palette, sheets
    public static let lg = ShadowStyle(color: .black.opacity(0.16), radius: 32, y: 12)

}

// MARK: - Shadow Style

public struct ShadowStyle: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.x = x
        self.y = y
    }
}

// MARK: - View Modifier

public extension View {
    func shadowStyle(_ style: ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
