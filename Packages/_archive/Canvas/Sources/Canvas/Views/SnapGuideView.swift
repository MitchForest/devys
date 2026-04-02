// SnapGuideView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// Renders snap guide lines on the canvas.
struct SnapGuideView: View {
    let guides: [SnapGuide]
    let canvas: CanvasModel

    @Environment(\.devysTheme) private var theme

    private let markerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            ForEach(guides) { guide in
                guideLine(for: guide, viewportSize: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func guideLine(for guide: SnapGuide, viewportSize: CGSize) -> some View {
        let color = guideColor(for: guide.type)

        switch guide.axis {
        case .horizontal:
            horizontalGuide(guide: guide, viewportSize: viewportSize, color: color)
        case .vertical:
            verticalGuide(guide: guide, viewportSize: viewportSize, color: color)
        }
    }

    @ViewBuilder
    private func horizontalGuide(guide: SnapGuide, viewportSize: CGSize, color: Color) -> some View {
        let y = canvas.screenPoint(from: CGPoint(x: 0, y: guide.position), viewportSize: viewportSize).y
        let startX = canvas.screenPoint(from: CGPoint(x: guide.start, y: 0), viewportSize: viewportSize).x
        let endX = canvas.screenPoint(from: CGPoint(x: guide.end, y: 0), viewportSize: viewportSize).x

        ZStack {
            Path { path in
                path.move(to: CGPoint(x: startX, y: y))
                path.addLine(to: CGPoint(x: endX, y: y))
            }
            .stroke(color, lineWidth: 1)

            Circle().fill(color).frame(width: markerRadius * 2, height: markerRadius * 2).position(x: startX, y: y)
            Circle().fill(color).frame(width: markerRadius * 2, height: markerRadius * 2).position(x: endX, y: y)
        }
    }

    @ViewBuilder
    private func verticalGuide(guide: SnapGuide, viewportSize: CGSize, color: Color) -> some View {
        let x = canvas.screenPoint(from: CGPoint(x: guide.position, y: 0), viewportSize: viewportSize).x
        let startY = canvas.screenPoint(from: CGPoint(x: 0, y: guide.start), viewportSize: viewportSize).y
        let endY = canvas.screenPoint(from: CGPoint(x: 0, y: guide.end), viewportSize: viewportSize).y

        ZStack {
            Path { path in
                path.move(to: CGPoint(x: x, y: startY))
                path.addLine(to: CGPoint(x: x, y: endY))
            }
            .stroke(color, lineWidth: 1)

            Circle().fill(color).frame(width: markerRadius * 2, height: markerRadius * 2).position(x: x, y: startY)
            Circle().fill(color).frame(width: markerRadius * 2, height: markerRadius * 2).position(x: x, y: endY)
        }
    }

    private func guideColor(for type: SnapGuide.SnapType) -> Color {
        // All guides use the theme accent at varying opacities
        switch type {
        case .edgeToEdge: return theme.accent
        case .sameLevel: return theme.accent.opacity(0.7)
        case .center: return theme.accent.opacity(0.85)
        case .equalSpacing: return theme.accent.opacity(0.6)
        case .viewportEdge: return theme.accent.opacity(0.5)
        }
    }
}
