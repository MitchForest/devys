// CanvasModel+Connectors.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics

// MARK: - Connector CRUD

extension CanvasModel {

    /// Create a new connector between two nodes.
    @discardableResult
    public func createConnector(
        from sourceId: UUID,
        sourcePort: PortPosition,
        to targetId: UUID,
        targetPort: PortPosition,
        label: String? = nil
    ) -> WorkflowConnector? {
        // Prevent duplicate connections
        let exists = connectors.contains {
            $0.sourceId == sourceId && $0.targetId == targetId &&
            $0.sourcePort == sourcePort && $0.targetPort == targetPort
        }
        guard !exists else { return nil }
        guard sourceId != targetId else { return nil }

        let connector = WorkflowConnector(
            sourceId: sourceId,
            targetId: targetId,
            sourcePort: sourcePort,
            targetPort: targetPort,
            label: label
        )
        connectors.append(connector)
        return connector
    }

    /// Delete a connector by ID.
    public func deleteConnector(_ id: UUID) {
        connectors.removeAll { $0.id == id }
        selectedConnectorIds.remove(id)
    }

    /// Delete selected connectors.
    public func deleteSelectedConnectors() {
        for id in selectedConnectorIds {
            connectors.removeAll { $0.id == id }
        }
        selectedConnectorIds.removeAll()
    }

    // MARK: - Connector Selection

    /// Select a connector.
    public func selectConnector(_ id: UUID) {
        selectedNodeIds.removeAll()
        selectedConnectorIds = [id]
    }

    /// Toggle connector selection.
    public func toggleConnectorSelection(_ id: UUID) {
        if selectedConnectorIds.contains(id) {
            selectedConnectorIds.remove(id)
        } else {
            selectedConnectorIds.insert(id)
        }
    }

    /// Check if a connector is selected.
    public func isConnectorSelected(_ id: UUID) -> Bool {
        selectedConnectorIds.contains(id)
    }

    // MARK: - Connector Drag Operations

    /// Begin dragging from a port to create a new connector.
    public func beginConnectorDrag(from nodeId: UUID, port: PortPosition, startPosition: CGPoint) {
        let canvasPos = canvasPoint(from: startPosition, viewportSize: viewportSize)
        connectorDragState = ConnectorDragState(
            sourceNodeId: nodeId,
            sourcePort: port,
            currentPosition: canvasPos
        )
    }

    /// Update the connector drag position (screen coordinates converted to canvas).
    public func updateConnectorDrag(to screenPosition: CGPoint) {
        guard connectorDragState != nil else { return }
        let canvasPos = canvasPoint(from: screenPosition, viewportSize: viewportSize)
        connectorDragState?.currentPosition = canvasPos
    }

    /// Update the hover target during connector drag.
    public func updateConnectorDragHover(nodeId: UUID?, port: PortPosition?) {
        guard connectorDragState != nil else { return }
        connectorDragState?.hoverTargetNodeId = nodeId
        connectorDragState?.hoverTargetPort = port
        connectorDragHoverNodeId = nodeId
        connectorDragHoverPort = port
    }

    /// End the connector drag, creating a connection if valid.
    @discardableResult
    public func endConnectorDrag() -> WorkflowConnector? {
        guard let dragState = connectorDragState else { return nil }

        var result: WorkflowConnector?

        if dragState.isValidTarget,
           let targetId = dragState.hoverTargetNodeId,
           let targetPort = dragState.hoverTargetPort {
            result = createConnector(
                from: dragState.sourceNodeId,
                sourcePort: dragState.sourcePort,
                to: targetId,
                targetPort: targetPort
            )
        }

        connectorDragState = nil
        connectorDragHoverNodeId = nil
        connectorDragHoverPort = nil

        return result
    }

    /// Cancel the connector drag.
    public func cancelConnectorDrag() {
        connectorDragState = nil
        connectorDragHoverNodeId = nil
        connectorDragHoverPort = nil
    }

    // MARK: - Port Position Calculation

    /// Get the port position for a node in canvas coordinates.
    public func portPosition(for nodeId: UUID, port: PortPosition) -> CGPoint? {
        guard let node = node(withId: nodeId) else { return nil }
        let frame = displayFrame(for: node)
        switch port {
        case .left:
            return CGPoint(x: frame.minX, y: frame.midY)
        case .right:
            return CGPoint(x: frame.maxX, y: frame.midY)
        }
    }

    /// Returns the visible frame for a node, including live drag offsets.
    func displayFrame(for node: CanvasNode) -> CGRect {
        var frame = node.frame
        if let dragOffset = nodeDragOffsets[node.id] {
            frame = frame.offsetBy(dx: dragOffset.width, dy: dragOffset.height)
        }
        return frame
    }

    // MARK: - Spline Calculation

    /// Returns bezier spline segments for a connector (canvas coordinates).
    public func connectorSpline(for connector: WorkflowConnector) -> [BezierSegment] {
        guard let start = portPosition(for: connector.sourceId, port: connector.sourcePort),
              let end = portPosition(for: connector.targetId, port: connector.targetPort) else {
            return []
        }

        let clearance: CGFloat = 18
        let obstacles = connectorObstacleFrames(for: connector, clearance: clearance)

        let segments = BezierPathfinder.calculateSegments(
            from: start,
            to: end,
            obstacles: obstacles,
            clearance: clearance,
            startPort: connector.sourcePort,
            endPort: connector.targetPort
        )

        return segments
    }

    // MARK: - Obstacle Frames

    /// Returns obstacle frames for connector routing.
    private func connectorObstacleFrames(
        for connector: WorkflowConnector,
        clearance: CGFloat
    ) -> [CGRect] {
        var obstacles: [CGRect] = []

        for node in nodes {
            let frame = displayFrame(for: node)

            if node.id == connector.sourceId {
                obstacles.append(contentsOf: nodeObstacleFrames(
                    frame: frame,
                    port: connector.sourcePort,
                    clearance: clearance
                ))
                continue
            }

            if node.id == connector.targetId {
                obstacles.append(contentsOf: nodeObstacleFrames(
                    frame: frame,
                    port: connector.targetPort,
                    clearance: clearance
                ))
                continue
            }

            obstacles.append(frame)
        }

        return obstacles
    }

    /// Returns node obstacle frames with a small notch at the port edge.
    private func nodeObstacleFrames(
        frame: CGRect,
        port: PortPosition,
        clearance: CGFloat
    ) -> [CGRect] {
        guard frame.width > 0, frame.height > 0 else { return [] }

        let notchDepth = min(max(12, clearance * 1.4), frame.width * 0.6)
        let notchHalfHeight = min(max(14, clearance * 1.3), frame.height * 0.45)

        let notchTop = max(frame.minY, frame.midY - notchHalfHeight)
        let notchBottom = min(frame.maxY, frame.midY + notchHalfHeight)

        var rects: [CGRect] = []

        let top = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: max(0, notchTop - frame.minY)
        )
        if top.width > 0, top.height > 0 { rects.append(top) }

        let bottom = CGRect(
            x: frame.minX,
            y: notchBottom,
            width: frame.width,
            height: max(0, frame.maxY - notchBottom)
        )
        if bottom.width > 0, bottom.height > 0 { rects.append(bottom) }

        let midY = notchTop
        let midHeight = max(0, notchBottom - notchTop)

        switch port {
        case .left:
            let mid = CGRect(
                x: frame.minX + notchDepth,
                y: midY,
                width: max(0, frame.width - notchDepth),
                height: midHeight
            )
            if mid.width > 0, mid.height > 0 { rects.append(mid) }
        case .right:
            let mid = CGRect(
                x: frame.minX,
                y: midY,
                width: max(0, frame.width - notchDepth),
                height: midHeight
            )
            if mid.width > 0, mid.height > 0 { rects.append(mid) }
        }

        return rects
    }
}
