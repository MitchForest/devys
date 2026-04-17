// CanvasModel.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Observation
import SwiftUI

/// The workflow canvas model.
///
/// Manages:
/// - Viewport position (offset) and zoom level (scale)
/// - Coordinate transforms between screen and canvas space
/// - Nodes, selection, and z-ordering
/// - Workflow connectors between nodes
/// - Snap guides during drag operations
@MainActor
@Observable
public final class CanvasModel {

    // MARK: - Viewport

    /// Viewport state (position and zoom)
    public let viewport = CanvasViewport()

    /// Convenience accessors
    public var offset: CGPoint { viewport.offset }
    public var scale: CGFloat { viewport.scale }

    // MARK: - Nodes

    /// All nodes on the canvas
    public internal(set) var nodes: [CanvasNode] = []

    /// Currently selected node IDs
    public internal(set) var selectedNodeIds: Set<UUID> = []

    /// Currently hovered node ID (for hover effects)
    public internal(set) var hoveredNodeId: UUID?

    /// Next z-index to assign
    @ObservationIgnored private var nextZIndex: Int = 0

    // MARK: - Snapping

    /// Current snap guides to display
    public internal(set) var activeSnapGuides: [SnapGuide] = []

    /// Snap engine for calculating alignments
    @ObservationIgnored public let snapEngine = SnapEngine()

    /// Whether snapping is disabled (Shift key held)
    @ObservationIgnored private(set) var isSnappingDisabled: Bool = false

    // MARK: - Node Drag State

    /// Live drag offsets for individual nodes (used for connector routing)
    public internal(set) var nodeDragOffsets: [UUID: CGSize] = [:]

    // MARK: - Workflow Connectors

    /// All workflow connectors on the canvas
    public internal(set) var connectors: [WorkflowConnector] = []

    /// Currently selected connector IDs
    public internal(set) var selectedConnectorIds: Set<UUID> = []

    /// Active connector drag state (when creating a new connection)
    public internal(set) var connectorDragState: ConnectorDragState?

    /// Currently hovered node ID during connector drag
    public internal(set) var connectorDragHoverNodeId: UUID?

    /// Currently hovered port during connector drag
    public internal(set) var connectorDragHoverPort: PortPosition?

    // MARK: - View State

    /// Current viewport size (set by WorkflowCanvasView)
    public var viewportSize = CGSize(width: 1200, height: 800)

    // MARK: - Initialization

    public init() {
        viewport.onDirty = { [weak self] in
            _ = self // trigger observation
        }
    }

    // MARK: - Node Queries

    /// Get a node by ID
    public func node(withId id: UUID) -> CanvasNode? {
        nodes.first { $0.id == id }
    }

    /// Get the index of a node by ID
    func nodeIndex(withId id: UUID) -> Int? {
        nodes.firstIndex { $0.id == id }
    }

    /// Get nodes sorted by z-index (for rendering)
    public var nodesSortedByZIndex: [CanvasNode] {
        nodes.sorted { $0.zIndex < $1.zIndex }
    }

    /// Get visible nodes within a viewport
    public func visibleNodes(in viewportRect: CGRect) -> [CanvasNode] {
        nodesSortedByZIndex.filter { $0.frame.intersects(viewportRect) }
    }

    // MARK: - Node Creation

    /// Create a new node at a position, resolving overlaps with existing nodes.
    @discardableResult
    public func createNode(at center: CGPoint, title: String = "Node") -> UUID {
        var node = CanvasNode.create(at: center, title: title)
        node.zIndex = nextZIndex
        nextZIndex += 1

        // Resolve overlaps so the node doesn't land on top of another
        node.frame = resolveCollision(for: node.frame, excludingId: nil)

        nodes.append(node)
        selectedNodeIds = [node.id]
        return node.id
    }

    /// Replace all nodes and connectors from an external source of truth.
    public func replaceContents(
        nodes: [CanvasNode],
        connectors: [WorkflowConnector]
    ) {
        self.nodes = nodes
        self.connectors = connectors
        self.selectedNodeIds = selectedNodeIds.filter { id in
            nodes.contains { $0.id == id }
        }
        self.selectedConnectorIds = selectedConnectorIds.filter { id in
            connectors.contains { $0.id == id }
        }
        self.nodeDragOffsets = [:]
        self.activeSnapGuides = []
        self.connectorDragState = nil
        self.connectorDragHoverNodeId = nil
        self.connectorDragHoverPort = nil
        self.nextZIndex = (nodes.map(\.zIndex).max() ?? -1) + 1
    }

    // MARK: - Collision Resolution

    /// Nudge a frame until it no longer overlaps other nodes.
    ///
    /// Tries 8 directions at increasing distances. Falls back to placing
    /// to the right of all existing nodes if nothing works within 10 steps.
    func resolveCollision(for frame: CGRect, excludingId: UUID?) -> CGRect {
        let otherFrames = nodes
            .filter { $0.id != excludingId }
            .map(\.frame)

        guard overlaps(frame, with: otherFrames) else { return frame }

        let nudgeStep: CGFloat = 20
        let directions: [(CGFloat, CGFloat)] = [
            (1, 0), (0, 1), (-1, 0), (0, -1),
            (1, 1), (-1, 1), (1, -1), (-1, -1)
        ]

        for multiplier in 1...10 {
            for (dx, dy) in directions {
                let candidate = frame.offsetBy(
                    dx: dx * nudgeStep * CGFloat(multiplier),
                    dy: dy * nudgeStep * CGFloat(multiplier)
                )
                if !overlaps(candidate, with: otherFrames) {
                    return candidate
                }
            }
        }

        // Fallback: place to the right of all existing nodes
        let maxX = otherFrames.map(\.maxX).max() ?? frame.maxX
        return CGRect(
            x: maxX + nudgeStep,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    /// Check if a frame overlaps any of the given frames.
    private func overlaps(_ frame: CGRect, with others: [CGRect]) -> Bool {
        for other in others where frame.intersects(other) {
            return true
        }
        return false
    }

    /// Delete a node by ID. Also removes any connectors attached to it.
    public func deleteNode(_ id: UUID) {
        nodes.removeAll { $0.id == id }
        connectors.removeAll { $0.sourceId == id || $0.targetId == id }
        selectedNodeIds.remove(id)
        if hoveredNodeId == id { hoveredNodeId = nil }
    }

    /// Delete all selected nodes and their connectors.
    public func deleteSelectedNodes() {
        for id in selectedNodeIds {
            nodes.removeAll { $0.id == id }
            connectors.removeAll { $0.sourceId == id || $0.targetId == id }
        }
        selectedNodeIds.removeAll()
    }

    /// Move a node to an absolute position
    public func moveNodeTo(_ id: UUID, position: CGPoint) {
        guard let index = nodeIndex(withId: id) else { return }
        nodes[index].frame.origin = position
    }

    /// Bring a node to the front
    public func bringToFront(_ id: UUID) {
        guard let index = nodeIndex(withId: id) else { return }
        nodes[index].zIndex = nextZIndex
        nextZIndex += 1
    }

    // MARK: - Selection

    /// Select a node
    public func selectNode(_ id: UUID) {
        selectedNodeIds = [id]
        selectedConnectorIds.removeAll()
        bringToFront(id)
    }

    /// Toggle selection of a node (for multi-select)
    public func toggleNodeSelection(_ id: UUID) {
        if selectedNodeIds.contains(id) {
            selectedNodeIds.remove(id)
        } else {
            selectedNodeIds.insert(id)
            bringToFront(id)
        }
    }

    /// Check if a node is selected
    public func isNodeSelected(_ id: UUID) -> Bool {
        selectedNodeIds.contains(id)
    }

    /// Clear all selection
    public func clearSelection() {
        selectedNodeIds.removeAll()
        selectedConnectorIds.removeAll()
    }

    /// Update hovered node state
    public func setHoveredNode(_ id: UUID?) {
        hoveredNodeId = id
    }

    // MARK: - Snap State

    /// Update snapping disabled state (Shift key)
    func setSnappingDisabled(_ disabled: Bool) {
        isSnappingDisabled = disabled
    }

    /// Calculate snap for a moving node and return adjusted position
    func calculateSnapForNode(
        _ id: UUID,
        proposedFrame: CGRect
    ) -> CGRect {
        guard !isSnappingDisabled else {
            activeSnapGuides = []
            return proposedFrame
        }

        let otherNodes = nodes.filter { $0.id != id }
        let viewportBounds = visibleRect(viewportSize: viewportSize)

        let result = snapEngine.calculateSnap(
            movingFrame: proposedFrame,
            otherFrames: otherNodes.map(\.frame),
            viewportBounds: viewportBounds
        )

        activeSnapGuides = result.guides

        return CGRect(
            x: proposedFrame.origin.x + result.delta.width,
            y: proposedFrame.origin.y + result.delta.height,
            width: proposedFrame.width,
            height: proposedFrame.height
        )
    }

    /// Clear snap guides
    public func clearSnapGuides() {
        activeSnapGuides = []
    }

    // MARK: - Node Drag Offsets

    /// Track live drag offset for a node (used for connector routing)
    public func setNodeDragOffset(_ nodeId: UUID, offset: CGSize) {
        nodeDragOffsets[nodeId] = offset
    }

    /// Clear any live drag offset for a node
    public func clearNodeDragOffset(_ nodeId: UUID) {
        nodeDragOffsets.removeValue(forKey: nodeId)
    }

    // MARK: - Zoom Actions (delegate to viewport)

    public func zoomIn() { viewport.zoomIn() }
    public func zoomOut() { viewport.zoomOut() }
    public func zoomToFit() { viewport.zoomToFit() }
    public func zoomTo100() { viewport.zoomTo100() }
    public func setScale(_ newScale: CGFloat) { viewport.setScale(newScale) }

    // MARK: - Pan Actions (delegate to viewport)

    /// Move the canvas by a delta (in screen points).
    public func pan(by screenDelta: CGSize) { viewport.pan(by: screenDelta) }

    /// Set absolute offset position.
    public func setOffset(_ newOffset: CGPoint) { viewport.setOffset(newOffset) }

}
