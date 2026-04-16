// DevysShape.swift
// Devys Design System — Continuous-curvature shape primitive
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// The standard Devys shape — a rounded rectangle with continuous (squircle) curvature.
///
/// Always uses `style: .continuous` for smooth curvature transitions.
/// This eliminates the visible kink where arc meets straight edge.
///
/// Usage:
/// ```swift
/// DevysShape()                     // 12pt (standard)
/// DevysShape(.micro)               // 4pt (tiny elements)
/// DevysShape(.full)                // 9999pt (circle)
/// DevysShape(innerPadding: 8)      // computed inner: 12 - 8 = 4pt
/// ```
public struct DevysShape: Shape {

    public enum RadiusToken: Sendable {
        /// 12pt — the standard radius for everything
        case standard
        /// 4pt — tiny inline elements
        case micro
        /// 9999pt — circles
        case full
        /// Custom value (use sparingly — prefer tokens)
        case custom(CGFloat)
    }

    private let cornerRadius: CGFloat

    public init(_ token: RadiusToken = .standard) {
        switch token {
        case .standard: self.cornerRadius = Spacing.radius
        case .micro: self.cornerRadius = Spacing.radiusMicro
        case .full: self.cornerRadius = Spacing.radiusFull
        case .custom(let value): self.cornerRadius = value
        }
    }

    /// Creates a shape with the computed inner radius for nesting.
    /// Inner radius = standard radius (12pt) minus the given padding.
    public init(innerPadding: CGFloat) {
        self.cornerRadius = Spacing.innerRadius(padding: innerPadding)
    }

    public func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .path(in: rect)
    }
}

// MARK: - View Modifier

public extension View {
    /// Clips the view to the standard Devys corner radius with continuous curvature.
    func devysCornerRadius(_ token: DevysShape.RadiusToken = .standard) -> some View {
        clipShape(DevysShape(token))
    }

    /// Clips the view with a computed inner radius for nesting inside a container
    /// with standard radius and the given padding.
    func devysInnerCornerRadius(padding: CGFloat) -> some View {
        clipShape(DevysShape(innerPadding: padding))
    }
}
