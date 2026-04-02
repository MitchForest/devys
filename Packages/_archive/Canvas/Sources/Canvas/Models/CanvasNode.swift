// CanvasNode.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import CoreGraphics

/// A node on the workflow canvas.
///
/// Nodes are positioned in canvas coordinates and rendered as
/// rounded-rect cards. Currently placeholders with just a title.
public struct CanvasNode: Identifiable, Equatable, Sendable {
    /// Unique identifier
    public let id: UUID

    /// Position and size in canvas coordinates
    public var frame: CGRect

    /// Z-order for rendering (higher = on top)
    public var zIndex: Int

    /// Display title
    public var title: String

    /// Center point in canvas coordinates
    public var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    public init(
        id: UUID = UUID(),
        frame: CGRect,
        zIndex: Int = 0,
        title: String = "Node"
    ) {
        self.id = id
        self.frame = frame
        self.zIndex = zIndex
        self.title = title
    }

    /// Create a node at a center position with default size.
    public static func create(
        at center: CGPoint,
        title: String = "Node",
        size: CGSize = CanvasLayout.defaultNodeSize
    ) -> CanvasNode {
        CanvasNode(
            frame: CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            title: title
        )
    }
}
