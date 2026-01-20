import Foundation
import CoreGraphics
import SwiftUI

/// Represents a single pane on the canvas.
///
/// Panes are the primary building blocks of the Devys workspace.
/// Each pane has a type (terminal, browser, etc.), position, size,
/// and can be grouped with other panes.
public struct Pane: Identifiable, Equatable {
    /// Unique identifier for this pane
    public let id: UUID

    /// The type of content this pane displays
    public var type: PaneType

    /// Position and size in canvas coordinates
    public var frame: CGRect

    /// Z-order for layering (higher = on top)
    public var zIndex: Int

    /// Group this pane belongs to (nil if ungrouped)
    public var groupId: UUID?

    /// Display title shown in the title bar
    public var title: String

    /// Whether the pane is collapsed (showing only title bar)
    public var isCollapsed: Bool

    // MARK: - Initialization

    public init(
        id: UUID = UUID(),
        type: PaneType,
        frame: CGRect,
        zIndex: Int = 0,
        groupId: UUID? = nil,
        title: String,
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.type = type
        self.frame = frame
        self.zIndex = zIndex
        self.groupId = groupId
        self.title = title
        self.isCollapsed = isCollapsed
    }

    // MARK: - Computed Properties

    /// Center point of the pane in canvas coordinates
    public var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Position for the left connection handle
    public var leftHandlePosition: CGPoint {
        CGPoint(x: frame.minX, y: frame.midY)
    }

    /// Position for the right connection handle
    public var rightHandlePosition: CGPoint {
        CGPoint(x: frame.maxX, y: frame.midY)
    }

    /// Position for the top connection handle
    public var topHandlePosition: CGPoint {
        CGPoint(x: frame.midX, y: frame.minY)
    }

    /// Position for the bottom connection handle
    public var bottomHandlePosition: CGPoint {
        CGPoint(x: frame.midX, y: frame.maxY)
    }

    // MARK: - Equatable

    public static func == (lhs: Pane, rhs: Pane) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Pane Creation Helpers

extension Pane {
    /// Create a pane with default size at a given position
    public static func create(
        type: PaneType,
        at position: CGPoint,
        title: String? = nil
    ) -> Pane {
        let size = CGSize(
            width: Layout.paneDefaultWidth,
            height: Layout.paneDefaultHeight
        )
        let frame = CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        return Pane(
            type: type,
            frame: frame,
            title: title ?? type.defaultTitle
        )
    }
}
