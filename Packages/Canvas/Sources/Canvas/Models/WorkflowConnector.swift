// WorkflowConnector.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics

/// Represents a connection between two nodes in a workflow.
///
/// Connectors are visual bezier curves that show data/control flow
/// between workflow nodes.
public struct WorkflowConnector: Identifiable, Equatable, Sendable {
    /// Unique identifier
    public let id: UUID

    /// Source node ID (where the connection starts)
    public var sourceId: UUID

    /// Target node ID (where the connection ends)
    public var targetId: UUID

    /// Which port on the source node
    public var sourcePort: PortPosition

    /// Which port on the target node
    public var targetPort: PortPosition

    /// Optional label displayed on the curve
    public var label: String?

    public init(
        id: UUID = UUID(),
        sourceId: UUID,
        targetId: UUID,
        sourcePort: PortPosition = .right,
        targetPort: PortPosition = .left,
        label: String? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.sourcePort = sourcePort
        self.targetPort = targetPort
        self.label = label
    }
}

/// Position of a port on a node edge
public enum PortPosition: String, Sendable, CaseIterable {
    case left
    case right

    /// Returns the opposite port position
    public var opposite: PortPosition {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }
}

/// State for an in-progress connector drag operation
public struct ConnectorDragState: Equatable, Sendable {
    /// The node where the drag started
    public let sourceNodeId: UUID

    /// The port where the drag started
    public let sourcePort: PortPosition

    /// Current drag position in canvas coordinates
    public var currentPosition: CGPoint

    /// The node currently being hovered (if any)
    public var hoverTargetNodeId: UUID?

    /// The port currently being hovered (if any)
    public var hoverTargetPort: PortPosition?

    /// Whether the current hover target is valid
    public var isValidTarget: Bool {
        guard let targetId = hoverTargetNodeId else { return false }
        return targetId != sourceNodeId
    }

    public init(
        sourceNodeId: UUID,
        sourcePort: PortPosition,
        currentPosition: CGPoint,
        hoverTargetNodeId: UUID? = nil,
        hoverTargetPort: PortPosition? = nil
    ) {
        self.sourceNodeId = sourceNodeId
        self.sourcePort = sourcePort
        self.currentPosition = currentPosition
        self.hoverTargetNodeId = hoverTargetNodeId
        self.hoverTargetPort = hoverTargetPort
    }
}
