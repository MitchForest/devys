// WorkflowCanvasView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

/// The main infinite canvas view that hosts workflow nodes and connectors.
///
/// Provides:
/// - Infinite pannable/zoomable workspace
/// - Dot grid background
/// - Draggable nodes with snap alignment
/// - Bezier curve connectors with obstacle avoidance
/// - Double-click to show quick-add picker
/// - Cmd+/- to zoom in/out
public struct WorkflowCanvasView: View {
    @Bindable var canvas: CanvasModel

    @Environment(\.devysTheme) private var theme

    @State private var dragOffset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var isPanningCanvas: Bool = false
    @State private var currentViewportSize: CGSize = .zero

    /// Whether the quick add picker is showing
    @State private var isShowingQuickAdd = false

    /// Screen position where double-click occurred (for popover positioning)
    @State private var quickAddScreenPosition: CGPoint = .zero

    /// Canvas position where double-click occurred (for node creation)
    @State private var quickAddCanvasPosition: CGPoint = .zero

    public init(canvas: CanvasModel) {
        self.canvas = canvas
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                theme.base.ignoresSafeArea()

                // Dot grid
                CanvasGridView(offset: effectiveOffset, scale: effectiveScale)

                // Connectors layer (below nodes)
                connectorsLayer(viewportSize: geometry.size)
                    .offset(x: dragOffset.width, y: dragOffset.height)

                // Nodes layer
                nodesLayer(viewportSize: geometry.size)
                    .offset(x: dragOffset.width, y: dragOffset.height)

                // Snap guides layer (above nodes)
                SnapGuideView(guides: canvas.activeSnapGuides, canvas: canvas)

                // Toolbar overlay (top-right: add button, bottom-right: zoom)
                canvasToolbar

                // Quick add popover (positioned at double-click location)
                if isShowingQuickAdd {
                quickAddPopover()
                }
            }
            .coordinateSpace(name: "canvasViewport")
            .contentShape(Rectangle())
            .clipped()
            .contextMenu {
                Button {
                    // Create at center of viewport
                    let center = canvas.canvasPoint(
                        from: CGPoint(x: currentViewportSize.width / 2, y: currentViewportSize.height / 2),
                        viewportSize: currentViewportSize
                    )
                    canvas.createNode(at: center)
                } label: {
                    Label("Add Node", systemImage: "plus.rectangle")
                }

                Divider()

                Button { canvas.zoomIn() } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                Button { canvas.zoomOut() } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                Button { canvas.zoomTo100() } label: {
                    Label("Zoom to 100%", systemImage: "1.magnifyingglass")
                }

                if !canvas.selectedNodeIds.isEmpty || !canvas.selectedConnectorIds.isEmpty {
                    Divider()
                    Button(role: .destructive) {
                        canvas.deleteSelectedNodes()
                        canvas.deleteSelectedConnectors()
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.delete) {
                canvas.deleteSelectedNodes()
                canvas.deleteSelectedConnectors()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                canvas.deleteSelectedNodes()
                canvas.deleteSelectedConnectors()
                return .handled
            }
            // Double-click to show quick-add picker (higher priority than single-tap)
            .gesture(canvasDoubleClickGesture(viewportSize: geometry.size)
                .exclusively(before: canvasBackgroundTapGesture))
            .gesture(panGesture)
            .gesture(zoomGesture)
            .scrollZoom(canvas: canvas)
            .onAppear {
                currentViewportSize = geometry.size
                canvas.viewportSize = geometry.size
            }
            .onChange(of: geometry.size) { _, newSize in
                currentViewportSize = newSize
                canvas.viewportSize = newSize
            }
        }
    }
}

private extension WorkflowCanvasView {
    // MARK: - Nodes Layer

    @ViewBuilder
    func nodesLayer(viewportSize: CGSize) -> some View {
        let visibleRect = canvas.visibleRect(viewportSize: viewportSize)

        ForEach(canvas.visibleNodes(in: visibleRect)) { node in
            nodeView(for: node, viewportSize: viewportSize)
        }
    }

    @ViewBuilder
    func nodeView(for node: CanvasNode, viewportSize: CGSize) -> some View {
        let screenPos = canvas.screenPoint(from: node.center, viewportSize: viewportSize)
        let screenSize = canvas.screenSize(from: node.frame.size)

        DraggableNodeView(node: node, canvas: canvas)
            .frame(width: screenSize.width, height: screenSize.height)
            .position(x: screenPos.x, y: screenPos.y)
    }

    // MARK: - Connectors Layer

    @ViewBuilder
    func connectorsLayer(viewportSize: CGSize) -> some View {
        ForEach(canvas.connectors) { connector in
            connectorView(for: connector, viewportSize: viewportSize)
        }

        if let dragState = canvas.connectorDragState {
            dragPreviewConnector(dragState: dragState, viewportSize: viewportSize)
        }
    }

    @ViewBuilder
    func connectorView(for connector: WorkflowConnector, viewportSize: CGSize) -> some View {
        let segmentsCanvas = canvas.connectorSpline(for: connector)

        if !segmentsCanvas.isEmpty {
            let segmentsScreen = segmentsCanvas.map { segment in
                BezierSegment(
                    start: canvas.screenPoint(from: segment.start, viewportSize: viewportSize),
                    control1: canvas.screenPoint(from: segment.control1, viewportSize: viewportSize),
                    control2: canvas.screenPoint(from: segment.control2, viewportSize: viewportSize),
                    end: canvas.screenPoint(from: segment.end, viewportSize: viewportSize)
                )
            }

            ConnectorView(
                segments: segmentsScreen,
                label: connector.label,
                isSelected: canvas.isConnectorSelected(connector.id)
            )
            .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        }
    }

    @ViewBuilder
    func dragPreviewConnector(dragState: ConnectorDragState, viewportSize: CGSize) -> some View {
        if let startCanvas = canvas.portPosition(for: dragState.sourceNodeId, port: dragState.sourcePort) {
            let startScreen = canvas.screenPoint(from: startCanvas, viewportSize: viewportSize)
            let endScreen = dragPreviewEndPoint(dragState: dragState, viewportSize: viewportSize)

            DragPreviewConnectorView(
                startPoint: startScreen,
                endPoint: endScreen,
                isValidTarget: dragState.isValidTarget,
                startPort: dragState.sourcePort,
                endPort: dragState.hoverTargetPort
            )
            .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
        }
    }

    func dragPreviewEndPoint(dragState: ConnectorDragState, viewportSize: CGSize) -> CGPoint {
        if let targetId = dragState.hoverTargetNodeId,
           let targetPort = dragState.hoverTargetPort,
           let targetCanvas = canvas.portPosition(for: targetId, port: targetPort) {
            return canvas.screenPoint(from: targetCanvas, viewportSize: viewportSize)
        }
        return canvas.screenPoint(from: dragState.currentPosition, viewportSize: viewportSize)
    }

    // MARK: - Canvas Toolbar

    @ViewBuilder
    var canvasToolbar: some View {
        VStack {
            // Top-right: Add button
            HStack {
                Spacer()
                addNodeButton
                    .padding(12)
            }

            Spacer()

            // Bottom-right: Zoom controls
            HStack {
                Spacer()
                zoomControls
                    .padding(12)
            }
        }
    }

    @ViewBuilder
    var addNodeButton: some View {
        Button {
            // Create node at the center of the current viewport
            let center = canvas.canvasPoint(
                from: CGPoint(x: currentViewportSize.width / 2, y: currentViewportSize.height / 2),
                viewportSize: currentViewportSize
            )
            canvas.createNode(at: center)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.text)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusMicro)
                        .fill(theme.card)
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DevysSpacing.radiusMicro)
                        .strokeBorder(theme.border.opacity(0.6), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help("Add Node (double-click canvas)")
    }

    @ViewBuilder
    var zoomControls: some View {
        HStack(spacing: 4) {
            Button { canvas.zoomOut() } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Text("\(Int(canvas.scale * 100))%")
                .font(DevysTypography.micro)
                .foregroundStyle(theme.textTertiary)
                .frame(minWidth: 36)

            Button { canvas.zoomIn() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DevysSpacing.radiusMicro)
                .fill(theme.card.opacity(0.9))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DevysSpacing.radiusMicro)
                .strokeBorder(theme.border.opacity(0.6), lineWidth: 0.5)
        )
    }

    // MARK: - Quick Add Popover

    @ViewBuilder
    func quickAddPopover() -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .position(quickAddScreenPosition)
            .popover(isPresented: $isShowingQuickAdd, arrowEdge: .trailing) {
                QuickAddPicker(
                    canvasPosition: quickAddCanvasPosition,
                    onAddNode: { position in
                        canvas.createNode(at: position)
                        isShowingQuickAdd = false
                    },
                    onDismiss: {
                        isShowingQuickAdd = false
                    }
                )
            }
    }

    // MARK: - Computed Properties

    var effectiveOffset: CGPoint {
        CGPoint(
            x: canvas.offset.x + dragOffset.width / canvas.scale,
            y: canvas.offset.y + dragOffset.height / canvas.scale
        )
    }

    var effectiveScale: CGFloat {
        let newScale = canvas.scale * gestureScale
        return min(max(newScale, CanvasLayout.minScale), CanvasLayout.maxScale)
    }

    // MARK: - Gestures

    var canvasBackgroundTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { _ in
                canvas.clearSelection()
                canvas.cancelConnectorDrag()
                isShowingQuickAdd = false
            }
    }

    func canvasDoubleClickGesture(viewportSize: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                // Only show picker if double-click is on empty canvas (not on a node)
                if canvas.nodeId(at: value.location, viewportSize: viewportSize) == nil {
                    quickAddScreenPosition = value.location
                    quickAddCanvasPosition = canvas.canvasPoint(
                        from: value.location,
                        viewportSize: viewportSize
                    )
                    isShowingQuickAdd = true
                }
            }
    }

    var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isPanningCanvas {
                    if canvas.nodeId(at: value.startLocation, viewportSize: currentViewportSize) != nil {
                        dragOffset = .zero
                        return
                    }
                    isPanningCanvas = true
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard isPanningCanvas else { return }
                canvas.pan(by: value.translation)
                dragOffset = .zero
                isPanningCanvas = false
            }
    }

    var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                canvas.setScale(canvas.scale * value)
            }
    }
}
