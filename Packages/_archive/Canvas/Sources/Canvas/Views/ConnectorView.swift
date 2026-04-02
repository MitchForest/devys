// ConnectorView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// Renders a bezier curve connector between two nodes.
struct ConnectorView: View {
    let segments: [BezierSegment]
    let label: String?
    let isSelected: Bool

    @Environment(\.devysTheme) private var theme

    init(segments: [BezierSegment], label: String? = nil, isSelected: Bool = false) {
        self.segments = segments
        self.label = label
        self.isSelected = isSelected
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let path = connectorPath
                let style = StrokeStyle(lineWidth: isSelected ? 2.5 : 2, lineCap: .round, lineJoin: .round)

                if isSelected {
                    let glowStyle = StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    context.stroke(path, with: .color(strokeColor.opacity(0.22)), style: glowStyle)
                }
                context.stroke(path, with: .color(strokeColor), style: style)

                if let arrow = arrowTransform {
                    let arrowStyle = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    context.translateBy(x: arrow.position.x, y: arrow.position.y)
                    context.rotate(by: arrow.angle)
                    context.stroke(arrowPath, with: .color(strokeColor), style: arrowStyle)
                    context.rotate(by: -arrow.angle)
                    context.translateBy(x: -arrow.position.x, y: -arrow.position.y)
                }
            }
            if let label, !label.isEmpty {
                labelView(text: label).position(labelPosition)
            }
        }
        .allowsHitTesting(false)
    }

    private var connectorPath: Path {
        Path { path in
            guard let first = segments.first else { return }
            path.move(to: first.start)
            for segment in segments {
                path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
            }
        }
    }

    private var strokeColor: Color {
        isSelected ? theme.accent : theme.textTertiary
    }

    private var arrowPath: Path {
        var path = Path()
        path.move(to: CGPoint(x: -6, y: -4))
        path.addLine(to: .zero)
        path.addLine(to: CGPoint(x: -6, y: 4))
        return path
    }

    private var arrowTransform: (position: CGPoint, angle: Angle)? {
        guard let last = segments.last else { return nil }
        let position = BezierPathfinder.bezierPoint(on: last, t: 0.95)
        let tangent = BezierPathfinder.bezierTangent(on: last, t: 0.95)
        return (position, Angle(radians: atan2(tangent.y, tangent.x)))
    }

    @ViewBuilder
    private func labelView(text: String) -> some View {
        Text(text)
            .font(DevysTypography.xs)
            .fontWeight(.medium)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.surface)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            )
    }

    private var labelPosition: CGPoint {
        pointAlongPath(t: 0.5)
    }

    private func pointAlongPath(t: CGFloat) -> CGPoint {
        guard !segments.isEmpty else { return .zero }
        let lengths = segments.map { segmentLength($0) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return segments.last?.end ?? .zero }

        let target = total * t
        var running: CGFloat = 0
        for (index, length) in lengths.enumerated() {
            if running + length >= target {
                let localT = (target - running) / max(length, 0.0001)
                return BezierPathfinder.bezierPoint(on: segments[index], t: localT)
            }
            running += length
        }
        return segments.last?.end ?? .zero
    }

    private func segmentLength(_ segment: BezierSegment) -> CGFloat {
        var length: CGFloat = 0
        var previous = segment.start
        for i in 1...10 {
            let t = CGFloat(i) / 10
            let point = BezierPathfinder.bezierPoint(on: segment, t: t)
            length += sqrt(pow(point.x - previous.x, 2) + pow(point.y - previous.y, 2))
            previous = point
        }
        return length
    }
}

/// A connector being dragged (not yet connected to a target)
struct DragPreviewConnectorView: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let isValidTarget: Bool
    let startPort: PortPosition?
    let endPort: PortPosition?

    @Environment(\.devysTheme) private var theme

    var body: some View {
        Canvas { context, _ in
            let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4])
            context.stroke(connectorPath, with: .color(strokeColor), style: style)

            let indicator = Path(ellipseIn: CGRect(x: endPoint.x - 5, y: endPoint.y - 5, width: 10, height: 10))
            context.fill(indicator, with: .color(isValidTarget ? theme.accent : theme.textDisabled))
        }
        .allowsHitTesting(false)
    }

    private var connectorPath: Path {
        Path { path in
            let segments = BezierPathfinder.calculateSegments(
                from: startPoint, to: endPoint, startPort: startPort, endPort: endPort
            )
            guard let first = segments.first else { return }
            path.move(to: first.start)
            for segment in segments {
                path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
            }
        }
    }

    private var strokeColor: Color {
        isValidTarget ? theme.accent : theme.textDisabled
    }
}
