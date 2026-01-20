import SwiftUI

/// Resize handles that appear on pane edges and corners.
///
/// Provides 8 handles: 4 corners + 4 edges.
/// Each handle allows dragging to resize the pane with live preview.
public struct PaneResizeHandles: View {
    let pane: Pane
    @Environment(\.canvasState) private var _canvas

    // swiftlint:disable:next force_unwrapping
    private var canvas: CanvasState { _canvas! } // Safe: always injected by parent

    /// Frame at the start of resize gesture
    @State private var startFrame: CGRect = .zero

    /// Whether this pane is selected (handles only show when selected)
    private var isSelected: Bool {
        canvas.isPaneSelected(pane.id)
    }

    public init(pane: Pane) {
        self.pane = pane
    }

    public var body: some View {
        GeometryReader { geometry in
            if isSelected {
                ZStack {
                    // Corner handles
                    cornerHandle(at: .topLeft, size: geometry.size)
                    cornerHandle(at: .topRight, size: geometry.size)
                    cornerHandle(at: .bottomLeft, size: geometry.size)
                    cornerHandle(at: .bottomRight, size: geometry.size)

                    // Edge handles
                    edgeHandle(at: .top, size: geometry.size)
                    edgeHandle(at: .bottom, size: geometry.size)
                    edgeHandle(at: .left, size: geometry.size)
                    edgeHandle(at: .right, size: geometry.size)
                }
            }
        }
    }

    // MARK: - Corner Handles

    @ViewBuilder
    private func cornerHandle(at corner: Corner, size: CGSize) -> some View {
        let position = cornerPosition(corner, in: size)

        ResizeHandleView(cursor: corner.cursor)
            .frame(width: Layout.resizeHandleSize, height: Layout.resizeHandleSize)
            .position(position)
            .gesture(cornerDragGesture(corner: corner))
    }

    private func cornerPosition(_ corner: Corner, in size: CGSize) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .topRight: return CGPoint(x: size.width, y: 0)
        case .bottomLeft: return CGPoint(x: 0, y: size.height)
        case .bottomRight: return CGPoint(x: size.width, y: size.height)
        }
    }

    private func cornerDragGesture(corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // Capture start frame on first drag event
                if value.translation == .zero || startFrame == .zero {
                    startFrame = pane.frame
                }

                let delta = CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                )
                applyCornerResize(corner, delta: delta)
            }
            .onEnded { _ in
                startFrame = .zero
            }
    }

    private func applyCornerResize(_ corner: Corner, delta: CGSize) {
        guard let index = canvas.paneIndex(withId: pane.id) else { return }
        guard startFrame != .zero else { return }

        var newFrame = startFrame

        switch corner {
        case .topLeft:
            let proposedWidth = startFrame.width - delta.width
            let proposedHeight = startFrame.height - delta.height
            let clampedWidth = clamp(proposedWidth, min: Layout.paneMinWidth, max: Layout.paneMaxWidth)
            let clampedHeight = clamp(proposedHeight, min: Layout.paneMinHeight, max: Layout.paneMaxHeight)
            // Anchor bottom-right corner
            newFrame.origin.x = startFrame.maxX - clampedWidth
            newFrame.origin.y = startFrame.maxY - clampedHeight
            newFrame.size.width = clampedWidth
            newFrame.size.height = clampedHeight

        case .topRight:
            let proposedWidth = startFrame.width + delta.width
            let proposedHeight = startFrame.height - delta.height
            let clampedWidth = clamp(proposedWidth, min: Layout.paneMinWidth, max: Layout.paneMaxWidth)
            let clampedHeight = clamp(proposedHeight, min: Layout.paneMinHeight, max: Layout.paneMaxHeight)
            // Anchor bottom-left corner
            newFrame.origin.y = startFrame.maxY - clampedHeight
            newFrame.size.width = clampedWidth
            newFrame.size.height = clampedHeight

        case .bottomLeft:
            let proposedWidth = startFrame.width - delta.width
            let proposedHeight = startFrame.height + delta.height
            let clampedWidth = clamp(proposedWidth, min: Layout.paneMinWidth, max: Layout.paneMaxWidth)
            let clampedHeight = clamp(proposedHeight, min: Layout.paneMinHeight, max: Layout.paneMaxHeight)
            // Anchor top-right corner
            newFrame.origin.x = startFrame.maxX - clampedWidth
            newFrame.size.width = clampedWidth
            newFrame.size.height = clampedHeight

        case .bottomRight:
            let proposedWidth = startFrame.width + delta.width
            let proposedHeight = startFrame.height + delta.height
            // Anchor top-left corner (origin stays same)
            newFrame.size.width = clamp(proposedWidth, min: Layout.paneMinWidth, max: Layout.paneMaxWidth)
            newFrame.size.height = clamp(proposedHeight, min: Layout.paneMinHeight, max: Layout.paneMaxHeight)
        }

        canvas.panes[index].frame = newFrame
    }

    // MARK: - Edge Handles

    @ViewBuilder
    private func edgeHandle(at edge: Edge, size: CGSize) -> some View {
        let (frame, position) = edgeFrameAndPosition(edge, in: size)

        ResizeHandleView(cursor: edge.cursor, isEdge: true)
            .frame(width: frame.width, height: frame.height)
            .position(position)
            .gesture(edgeDragGesture(edge: edge))
    }

    private func edgeFrameAndPosition(_ edge: Edge, in size: CGSize) -> (CGSize, CGPoint) {
        let cornerSize = Layout.resizeHandleSize
        let edgeThickness = Layout.resizeEdgeThickness

        switch edge {
        case .top:
            return (
                CGSize(width: size.width - cornerSize * 2, height: edgeThickness),
                CGPoint(x: size.width / 2, y: 0)
            )
        case .bottom:
            return (
                CGSize(width: size.width - cornerSize * 2, height: edgeThickness),
                CGPoint(x: size.width / 2, y: size.height)
            )
        case .left:
            return (
                CGSize(width: edgeThickness, height: size.height - cornerSize * 2),
                CGPoint(x: 0, y: size.height / 2)
            )
        case .right:
            return (
                CGSize(width: edgeThickness, height: size.height - cornerSize * 2),
                CGPoint(x: size.width, y: size.height / 2)
            )
        }
    }

    private func edgeDragGesture(edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // Capture start frame on first drag event
                if value.translation == .zero || startFrame == .zero {
                    startFrame = pane.frame
                }

                let delta = CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                )
                applyEdgeResize(edge, delta: delta)
            }
            .onEnded { _ in
                startFrame = .zero
            }
    }

    private func applyEdgeResize(_ edge: Edge, delta: CGSize) {
        guard let index = canvas.paneIndex(withId: pane.id) else { return }
        guard startFrame != .zero else { return }

        var newFrame = startFrame

        switch edge {
        case .top:
            let proposedHeight = startFrame.height - delta.height
            let clampedHeight = clamp(proposedHeight, min: Layout.paneMinHeight, max: Layout.paneMaxHeight)
            // Anchor bottom edge
            newFrame.origin.y = startFrame.maxY - clampedHeight
            newFrame.size.height = clampedHeight

        case .bottom:
            let proposedHeight = startFrame.height + delta.height
            // Anchor top edge (origin.y stays same)
            newFrame.size.height = clamp(proposedHeight, min: Layout.paneMinHeight, max: Layout.paneMaxHeight)

        case .left:
            let proposedWidth = startFrame.width - delta.width
            let clampedWidth = clamp(proposedWidth, min: Layout.paneMinWidth, max: Layout.paneMaxWidth)
            // Anchor right edge
            newFrame.origin.x = startFrame.maxX - clampedWidth
            newFrame.size.width = clampedWidth

        case .right:
            let proposedWidth = startFrame.width + delta.width
            // Anchor left edge (origin.x stays same)
            newFrame.size.width = clamp(proposedWidth, min: Layout.paneMinWidth, max: Layout.paneMaxWidth)
        }

        canvas.panes[index].frame = newFrame
    }

    // MARK: - Helpers

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}

// MARK: - Handle View

/// Visual representation of a resize handle
private struct ResizeHandleView: View {
    let cursor: NSCursor
    let isEdge: Bool

    @State private var isHovered = false

    init(cursor: NSCursor, isEdge: Bool = false) {
        self.cursor = cursor
        self.isEdge = isEdge
    }

    var body: some View {
        Rectangle()
            .fill(isHovered ? Theme.resizeHandleActive : Theme.resizeHandle)
            .cornerRadius(isEdge ? 1 : 2)
            .opacity(isHovered ? 1.0 : 0.6)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

// MARK: - Corner Enum

private enum Corner {
    case topLeft, topRight, bottomLeft, bottomRight

    var cursor: NSCursor {
        // macOS doesn't have diagonal resize cursors built-in, use crosshair
        switch self {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        }
    }
}

// MARK: - Edge Enum

private enum Edge {
    case top, bottom, left, right

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        }
    }
}
