// PortOverlayView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// Visual overlay showing connection ports on node edges.
struct PortOverlayView: View {
    let nodeSize: CGSize
    let isVisible: Bool
    let onDragStart: (PortPosition, CGPoint) -> Void
    let onDragMove: (CGPoint) -> Void
    let onDragEnd: (CGPoint) -> Void

    private let portSize: CGFloat = 12

    var body: some View {
        ZStack {
            portView(position: .left).position(x: 0, y: nodeSize.height / 2)
            portView(position: .right).position(x: nodeSize.width, y: nodeSize.height / 2)
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isVisible)
        .allowsHitTesting(isVisible)
    }

    @ViewBuilder
    private func portView(position: PortPosition) -> some View {
        PortDragHandle(
            portSize: portSize,
            onDragStart: { startPoint in onDragStart(position, startPoint) },
            onDragMove: onDragMove,
            onDragEnd: onDragEnd
        )
    }
}

/// Individual port drag handle with gesture handling
private struct PortDragHandle: View {
    let portSize: CGFloat
    let onDragStart: (CGPoint) -> Void
    let onDragMove: (CGPoint) -> Void
    let onDragEnd: (CGPoint) -> Void

    @Environment(\.devysTheme) private var theme
    @State private var isHovered = false
    @State private var isDragging = false

    private let hitPadding: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: portSize + hitPadding * 2, height: portSize + hitPadding * 2)
                .contentShape(Circle())

            Circle()
                .fill(portFill)
                .frame(width: effectiveSize, height: effectiveSize)
                .overlay(Circle().strokeBorder(portStroke, lineWidth: 1.5))
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
        .scaleEffect(isDragging ? 1.3 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .gesture(dragGesture)
    }

    private var effectiveSize: CGFloat { isHovered ? portSize + 2 : portSize }

    private var portFill: some ShapeStyle {
        isDragging
            ? AnyShapeStyle(theme.accent)
            : AnyShapeStyle(theme.card)
    }

    private var portStroke: some ShapeStyle {
        isDragging || isHovered
            ? AnyShapeStyle(theme.accent)
            : AnyShapeStyle(theme.border)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvasViewport"))
            .onChanged { value in
                if !isDragging { isDragging = true; onDragStart(value.startLocation) }
                onDragMove(value.location)
            }
            .onEnded { value in
                isDragging = false
                onDragEnd(value.location)
            }
    }
}

/// Overlay shown on potential target nodes during connector drag
struct PortTargetOverlayView: View {
    let nodeSize: CGSize
    let hoveredPort: PortPosition?
    let isValidTarget: Bool

    @Environment(\.devysTheme) private var theme

    private let portSize: CGFloat = 16
    private var isHovered: Bool { hoveredPort != nil }

    var body: some View {
        ZStack {
            if isHovered && isValidTarget {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.accent, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent.opacity(0.1)))
            }

            if let port = hoveredPort, isValidTarget {
                Circle()
                    .fill(theme.accent)
                    .frame(width: portSize + 4, height: portSize + 4)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 2))
                    .shadow(color: theme.accent.opacity(0.5), radius: 4)
                    .position(x: port == .left ? 0 : nodeSize.width, y: nodeSize.height / 2)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .allowsHitTesting(false)
    }
}
