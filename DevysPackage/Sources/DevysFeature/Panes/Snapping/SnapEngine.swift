import Foundation
import CoreGraphics

/// Engine for calculating snap alignments between panes.
///
/// Detects when a pane being dragged should snap to align with other panes.
/// Supports edge-to-edge, same-level, and center alignments.
public struct SnapEngine {

    /// Threshold distance for snapping (in canvas coordinates)
    public let threshold: CGFloat

    public init(threshold: CGFloat = Layout.snapThreshold) {
        self.threshold = threshold
    }

    /// Calculate snap adjustments for a pane being moved.
    ///
    /// - Parameters:
    ///   - movingFrame: The frame of the pane being moved
    ///   - otherPanes: Other panes to snap against
    /// - Returns: Snap result with adjustments and guides
    public func calculateSnap(
        movingFrame: CGRect,
        otherPanes: [Pane]
    ) -> SnapResult {
        var deltaX: CGFloat = 0
        var deltaY: CGFloat = 0
        var guides: [SnapGuide] = []
        var snappedPaneIds: Set<UUID> = []

        for pane in otherPanes {
            let targetFrame = pane.frame

            // Horizontal snaps (affects X position)
            if let (dx, guide) = findHorizontalSnap(moving: movingFrame, target: targetFrame) {
                if abs(dx) < abs(deltaX) || deltaX == 0 {
                    deltaX = dx
                    guides.removeAll { $0.axis == .vertical }
                    guides.append(guide)
                    snappedPaneIds.insert(pane.id)
                }
            }

            // Vertical snaps (affects Y position)
            if let (dy, guide) = findVerticalSnap(moving: movingFrame, target: targetFrame) {
                if abs(dy) < abs(deltaY) || deltaY == 0 {
                    deltaY = dy
                    guides.removeAll { $0.axis == .horizontal }
                    guides.append(guide)
                    snappedPaneIds.insert(pane.id)
                }
            }
        }

        return SnapResult(
            delta: CGSize(width: deltaX, height: deltaY),
            guides: guides,
            snappedPaneIds: snappedPaneIds
        )
    }

    // MARK: - Horizontal Snaps (X axis)

    private func findHorizontalSnap(
        moving: CGRect,
        target: CGRect
    ) -> (CGFloat, SnapGuide)? {
        var bestSnap: (CGFloat, SnapGuide)?

        // Helper to check if new snap is better than current best
        func isBetter(_ delta: CGFloat) -> Bool {
            guard let current = bestSnap else { return true }
            return abs(delta) < abs(current.0)
        }

        // Left-to-left
        let leftToLeft = target.minX - moving.minX
        if abs(leftToLeft) <= threshold && isBetter(leftToLeft) {
            let guide = SnapGuide(
                axis: .vertical,
                position: target.minX,
                start: min(moving.minY, target.minY),
                end: max(moving.maxY, target.maxY),
                type: .sameLevel
            )
            bestSnap = (leftToLeft, guide)
        }

        // Right-to-right
        let rightToRight = target.maxX - moving.maxX
        if abs(rightToRight) <= threshold && isBetter(rightToRight) {
            let guide = SnapGuide(
                axis: .vertical,
                position: target.maxX,
                start: min(moving.minY, target.minY),
                end: max(moving.maxY, target.maxY),
                type: .sameLevel
            )
            bestSnap = (rightToRight, guide)
        }

        // Left-to-right (edge-to-edge)
        let leftToRight = target.maxX - moving.minX
        if abs(leftToRight) <= threshold && isBetter(leftToRight) {
            let guide = SnapGuide(
                axis: .vertical,
                position: target.maxX,
                start: min(moving.minY, target.minY),
                end: max(moving.maxY, target.maxY),
                type: .edgeToEdge
            )
            bestSnap = (leftToRight, guide)
        }

        // Right-to-left (edge-to-edge)
        let rightToLeft = target.minX - moving.maxX
        if abs(rightToLeft) <= threshold && isBetter(rightToLeft) {
            let guide = SnapGuide(
                axis: .vertical,
                position: target.minX,
                start: min(moving.minY, target.minY),
                end: max(moving.maxY, target.maxY),
                type: .edgeToEdge
            )
            bestSnap = (rightToLeft, guide)
        }

        // Center-to-center
        let centerToCenter = target.midX - moving.midX
        if abs(centerToCenter) <= threshold && isBetter(centerToCenter) {
            let guide = SnapGuide(
                axis: .vertical,
                position: target.midX,
                start: min(moving.minY, target.minY),
                end: max(moving.maxY, target.maxY),
                type: .center
            )
            bestSnap = (centerToCenter, guide)
        }

        return bestSnap
    }

    // MARK: - Vertical Snaps (Y axis)

    private func findVerticalSnap(
        moving: CGRect,
        target: CGRect
    ) -> (CGFloat, SnapGuide)? {
        var bestSnap: (CGFloat, SnapGuide)?

        // Helper to check if new snap is better than current best
        func isBetter(_ delta: CGFloat) -> Bool {
            guard let current = bestSnap else { return true }
            return abs(delta) < abs(current.0)
        }

        // Top-to-top
        let topToTop = target.minY - moving.minY
        if abs(topToTop) <= threshold && isBetter(topToTop) {
            let guide = SnapGuide(
                axis: .horizontal,
                position: target.minY,
                start: min(moving.minX, target.minX),
                end: max(moving.maxX, target.maxX),
                type: .sameLevel
            )
            bestSnap = (topToTop, guide)
        }

        // Bottom-to-bottom
        let bottomToBottom = target.maxY - moving.maxY
        if abs(bottomToBottom) <= threshold && isBetter(bottomToBottom) {
            let guide = SnapGuide(
                axis: .horizontal,
                position: target.maxY,
                start: min(moving.minX, target.minX),
                end: max(moving.maxX, target.maxX),
                type: .sameLevel
            )
            bestSnap = (bottomToBottom, guide)
        }

        // Top-to-bottom (edge-to-edge)
        let topToBottom = target.maxY - moving.minY
        if abs(topToBottom) <= threshold && isBetter(topToBottom) {
            let guide = SnapGuide(
                axis: .horizontal,
                position: target.maxY,
                start: min(moving.minX, target.minX),
                end: max(moving.maxX, target.maxX),
                type: .edgeToEdge
            )
            bestSnap = (topToBottom, guide)
        }

        // Bottom-to-top (edge-to-edge)
        let bottomToTop = target.minY - moving.maxY
        if abs(bottomToTop) <= threshold && isBetter(bottomToTop) {
            let guide = SnapGuide(
                axis: .horizontal,
                position: target.minY,
                start: min(moving.minX, target.minX),
                end: max(moving.maxX, target.maxX),
                type: .edgeToEdge
            )
            bestSnap = (bottomToTop, guide)
        }

        // Center-to-center
        let centerToCenter = target.midY - moving.midY
        if abs(centerToCenter) <= threshold && isBetter(centerToCenter) {
            let guide = SnapGuide(
                axis: .horizontal,
                position: target.midY,
                start: min(moving.minX, target.minX),
                end: max(moving.maxX, target.maxX),
                type: .center
            )
            bestSnap = (centerToCenter, guide)
        }

        return bestSnap
    }
}

// MARK: - Snap Result

/// Result of snap calculation
public struct SnapResult {
    /// Delta to apply to make the snap
    public let delta: CGSize

    /// Visual guides to display
    public let guides: [SnapGuide]

    /// IDs of panes that were snapped to
    public let snappedPaneIds: Set<UUID>

    /// Whether any snap was found
    public var hasSnap: Bool {
        delta.width != 0 || delta.height != 0
    }
}

// MARK: - Snap Guide

/// Visual guide line to show snap alignment
public struct SnapGuide: Identifiable, Equatable {
    public let id = UUID()

    /// Axis of the guide line
    public let axis: Axis

    /// Position along the perpendicular axis (in canvas coordinates)
    public let position: CGFloat

    /// Start of the line (in canvas coordinates)
    public let start: CGFloat

    /// End of the line (in canvas coordinates)
    public let end: CGFloat

    /// Type of snap this guide represents
    public let type: SnapType

    public enum Axis {
        case horizontal // Line goes left-right, Y position is fixed
        case vertical   // Line goes up-down, X position is fixed
    }

    public enum SnapType {
        case edgeToEdge
        case sameLevel
        case center
    }
}
