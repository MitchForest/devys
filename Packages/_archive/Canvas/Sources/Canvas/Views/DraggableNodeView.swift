// DraggableNodeView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppKit
import SwiftUI
import UI

/// Wrapper that makes a node draggable on the canvas.
///
/// Handles drag gesture, click to select, hover for ports,
/// and port drag callbacks for connector creation.
struct DraggableNodeView: View {
    let node: CanvasNode
    let canvas: CanvasModel

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false
    @State private var startFrame: CGRect = .zero
    @State private var isHovered: Bool = false
    @State private var currentScreenSize: CGSize = .zero

    @Environment(\.devysTheme) private var theme

    private var liveNode: CanvasNode {
        canvas.node(withId: node.id) ?? node
    }

    private var effectiveOffset: CGSize {
        isDragging ? dragOffset : .zero
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Node content
                nodeContent

                // Port overlays for workflow connections
                PortOverlayView(
                    nodeSize: geometry.size,
                    isVisible: shouldShowPorts,
                    onDragStart: { port, startPoint in
                        canvas.beginConnectorDrag(from: node.id, port: port, startPosition: startPoint)
                    },
                    onDragMove: { point in
                        handlePortDragMove(point: point)
                    },
                    onDragEnd: { _ in
                        _ = canvas.endConnectorDrag()
                    }
                )

                // Port target overlay when another node is dragging a connector toward us
                if let dragState = canvas.connectorDragState,
                   dragState.sourceNodeId != node.id {
                    PortTargetOverlayView(
                        nodeSize: geometry.size,
                        hoveredPort: canvas.connectorDragHoverNodeId == node.id
                            ? canvas.connectorDragHoverPort : nil,
                        isValidTarget: dragState.sourceNodeId != node.id
                    )
                }
            }
            .onChange(of: geometry.size) { _, newSize in currentScreenSize = newSize }
            .onAppear { currentScreenSize = geometry.size }
        }
        .offset(x: effectiveOffset.width, y: effectiveOffset.height)
        .gesture(dragGesture)
        .onTapGesture { handleTap() }
        .onHover { hovering in
            isHovered = hovering
            canvas.setHoveredNode(hovering ? node.id : nil)
        }
        .animation(isDragging ? nil : .easeOut(duration: 0.1), value: effectiveOffset)
    }

    // MARK: - Node Content

    @ViewBuilder
    private var nodeContent: some View {
        let isSelected = canvas.isNodeSelected(node.id)

        RoundedRectangle(cornerRadius: CanvasLayout.nodeCornerRadius, style: .continuous)
            .fill(theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: CanvasLayout.nodeCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.accent : theme.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0.08), radius: isSelected ? 8 : 4, y: 2)
            .overlay(
                // Title centered
                Text(liveNode.title)
                    .font(DevysTypography.label)
                    .foregroundStyle(theme.textSecondary)
            )
            .overlay(alignment: .topTrailing) {
                // Close button — visible on hover or selection
                if isHovered || isSelected {
                    Button {
                        canvas.deleteNode(node.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(theme.elevated)
                                    .overlay(
                                        Circle().strokeBorder(theme.borderSubtle, lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Port Visibility

    private var shouldShowPorts: Bool {
        let isSourceOfDrag = canvas.connectorDragState?.sourceNodeId == node.id
        return isHovered || canvas.isNodeSelected(node.id) || isSourceOfDrag
    }

    // MARK: - Port Drag Handling

    private func handlePortDragMove(point: CGPoint) {
        canvas.updateConnectorDrag(to: point)

        let canvasPoint = canvas.canvasPoint(from: point, viewportSize: canvas.viewportSize)
        var foundNode: (id: UUID, port: PortPosition)?

        for n in canvas.nodes where n.id != node.id {
            let hitFrame = n.frame.insetBy(dx: -10, dy: -10)
            if hitFrame.contains(canvasPoint) {
                let isLeftHalf = canvasPoint.x < n.frame.midX
                foundNode = (n.id, isLeftHalf ? .left : .right)
                break
            }
        }

        canvas.updateConnectorDragHover(nodeId: foundNode?.id, port: foundNode?.port)
    }

    // MARK: - Tap

    private func handleTap() {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) || modifiers.contains(.command) {
            canvas.toggleNodeSelection(node.id)
        } else {
            canvas.selectNode(node.id)
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    startFrame = canvas.beginNodeDrag(node.id) ?? liveNode.frame
                }

                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                dragOffset = canvas.updateNodeDrag(
                    nodeId: node.id,
                    startFrame: startFrame,
                    translation: value.translation,
                    shiftHeld: shiftHeld
                )
            }
            .onEnded { value in
                isDragging = false
                canvas.endNodeDrag(
                    nodeId: node.id,
                    startFrame: startFrame,
                    translation: value.translation
                )
                dragOffset = .zero
                startFrame = .zero
            }
    }
}
