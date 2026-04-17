// CanvasGridView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// Renders a dot grid background that responds to pan and zoom.
struct CanvasGridView: View {
    let offset: CGPoint
    let scale: CGFloat

    private let dotSpacing: CGFloat = CanvasLayout.dotSpacing
    private let dotRadius: CGFloat = CanvasLayout.dotRadius
    private let minVisibleScale: CGFloat = 0.15

    var body: some View {
        Canvas { context, size in
            drawDots(context: context, size: size)
        }
        .drawingGroup()
    }

    private func drawDots(context: GraphicsContext, size: CGSize) {
        guard scale >= minVisibleScale else { return }

        let screenSpacing = dotSpacing * scale
        guard screenSpacing > 4 else { return }

        let offsetX = (offset.x * scale).truncatingRemainder(dividingBy: screenSpacing)
        let offsetY = (offset.y * scale).truncatingRemainder(dividingBy: screenSpacing)
        let centerOffsetX = size.width.truncatingRemainder(dividingBy: screenSpacing) / 2
        let centerOffsetY = size.height.truncatingRemainder(dividingBy: screenSpacing) / 2

        let startX = offsetX + centerOffsetX
        let startY = offsetY + centerOffsetY
        let cols = Int(ceil(size.width / screenSpacing)) + 2
        let rows = Int(ceil(size.height / screenSpacing)) + 2

        let dotColor = Color.secondary.opacity(0.3)

        for row in -1..<rows {
            for col in -1..<cols {
                var x = startX + CGFloat(col) * screenSpacing
                var y = startY + CGFloat(row) * screenSpacing

                if x < 0 { x += screenSpacing }
                if y < 0 { y += screenSpacing }

                guard x >= -dotRadius && x <= size.width + dotRadius &&
                      y >= -dotRadius && y <= size.height + dotRadius else { continue }

                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
            }
        }
    }
}
