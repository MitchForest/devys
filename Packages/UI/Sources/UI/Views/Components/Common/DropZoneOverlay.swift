// DropZoneOverlay.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A semi-transparent overlay for split creation during tab drag.
///
/// Shows a highlighted zone (center, left, right, top, bottom) with a dashed
/// accent border to communicate where dropping will create a new split.
public struct DropZoneOverlay: View {
    @Environment(\.theme) private var theme

    private let zone: DropZone
    private let isActive: Bool

    public init(zone: DropZone, isActive: Bool) {
        self.zone = zone
        self.isActive = isActive
    }

    public var body: some View {
        GeometryReader { geometry in
            let rect = zoneRect(in: geometry.size)
            let shape = PositionedRoundedRect(
                rect: rect,
                cornerRadius: Spacing.radius
            )

            ZStack {
                if isActive {
                    shape
                        .fill(theme.accentSubtle)

                    shape
                        .stroke(
                            theme.accentMuted,
                            style: StrokeStyle(
                                lineWidth: 2,
                                dash: [6, 4]
                            )
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity)
            .animation(Animations.micro, value: isActive)
        }
    }

    // MARK: - Geometry

    private func zoneRect(in size: CGSize) -> CGRect {
        switch zone {
        case .center:
            return CGRect(origin: .zero, size: size)
        case .left:
            return CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
        case .right:
            return CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
        case .top:
            return CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
        case .bottom:
            return CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
        }
    }
}

// MARK: - Drop Zone

public enum DropZone: String, Sendable, CaseIterable {
    case center
    case left
    case right
    case top
    case bottom
}

// MARK: - Shape Helper

/// A rounded rectangle positioned at an arbitrary rect within the drawing bounds.
private struct PositionedRoundedRect: Shape {
    let rect: CGRect
    let cornerRadius: CGFloat

    func path(in _: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
    }
}

// MARK: - Previews

#Preview("Drop Zone Overlays") {
    let theme = Theme(isDark: true)
    VStack(spacing: Spacing.space4) {
        ForEach(DropZone.allCases, id: \.self) { zone in
            ZStack {
                RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                    .fill(Color(hex: "#1C1A17"))

                DropZoneOverlay(zone: zone, isActive: true)

                Text(zone.rawValue.capitalized)
                    .font(Typography.caption)
                    .foregroundStyle(Color(hex: "#9E978C"))
            }
            .frame(width: 200, height: 120)
        }
    }
    .padding(24)
    .background(Color(hex: "#121110"))
    .environment(\.theme, theme)
}
