import SwiftUI
import AppKit

/// Wrapper that makes a pane draggable on the canvas.
///
/// Handles:
/// - Drag gesture for moving panes
/// - Snapping to other panes
/// - Group movement (all panes in group move together)
/// - Click to select (shift+click for multi-select)
/// - Brings pane to front on interaction
public struct DraggablePaneView: View {
    /// The pane ID (we use this to look up live data)
    let paneId: UUID

    /// Initial pane data (for rendering, but groupId etc. comes from live data)
    let pane: Pane

    @Environment(\.canvasState) private var _canvas

    // swiftlint:disable:next force_unwrapping
    private var canvas: CanvasState { _canvas! } // Safe: always injected by parent

    /// Get live pane data from canvas (includes updated groupId)
    private var livePane: Pane {
        canvas.pane(withId: paneId) ?? pane
    }

    /// Tracks drag offset during gesture (in screen coordinates)
    @State private var dragOffset: CGSize = .zero

    /// Whether we're currently dragging (moving the pane)
    @State private var isDragging: Bool = false

    /// Whether we're currently resizing (prevents drag from interfering)
    @State private var isResizing: Bool = false

    /// Start frame when drag began
    @State private var startFrame: CGRect = .zero

    /// Last snap result for auto-grouping
    @State private var lastSnapResult: SnapResult?

    public init(pane: Pane) {
        self.paneId = pane.id
        self.pane = pane
    }

    /// Effective offset - either from direct drag or from group being dragged
    private var effectiveOffset: CGSize {
        // If this pane is being directly dragged
        if isDragging {
            return dragOffset
        }

        // If this pane's group is being dragged by another pane
        if let groupId = livePane.groupId,
           canvas.draggingGroupId == groupId {
            return CGSize(
                width: canvas.groupDragOffset.width * canvas.scale,
                height: canvas.groupDragOffset.height * canvas.scale
            )
        }

        return .zero
    }

    public var body: some View {
        ZStack {
            // Group indicator (subtle background if in group)
            if livePane.groupId != nil {
                RoundedRectangle(cornerRadius: Layout.paneCornerRadius + 2)
                    .fill(Theme.groupBackground)
                    .padding(-4)
            }

            PaneContainerView(pane: livePane)

            // Resize handles (only visible when selected)
            // Uses binding to isResizing to prevent drag gesture interference
            PaneResizeHandles(pane: livePane, isResizing: $isResizing)
        }
        .offset(x: effectiveOffset.width, y: effectiveOffset.height)
        .gesture(dragGesture)
        .onTapGesture {
            handleTap()
        }
        .animation(isDragging ? nil : .easeOut(duration: 0.1), value: effectiveOffset)
    }

    // MARK: - Tap Handling

    private func handleTap() {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.shift) || modifiers.contains(.command) {
            // Shift+click or Cmd+click: toggle selection (multi-select)
            // This now handles entire groups automatically
            canvas.togglePaneSelection(paneId)
        } else {
            // Regular click: select this pane (and its group if grouped)
            canvas.selectPane(paneId)
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // Don't start dragging if we're resizing
                guard !isResizing else { return }

                if !isDragging {
                    // First drag event - capture start state
                    isDragging = true
                    startFrame = livePane.frame

                    // Select pane on drag start if not already selected
                    if !canvas.isPaneSelected(paneId) {
                        canvas.selectPane(paneId)
                    }

                    // If in a group, set up group dragging
                    if let groupId = livePane.groupId {
                        canvas.draggingGroupId = groupId
                    }
                }

                // Convert screen delta to canvas delta (accounting for zoom)
                let canvasDelta = CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                )

                // Calculate proposed frame
                let proposedFrame = CGRect(
                    x: startFrame.origin.x + canvasDelta.width,
                    y: startFrame.origin.y + canvasDelta.height,
                    width: startFrame.width,
                    height: startFrame.height
                )

                // For grouped panes, skip snapping (group already established)
                let snappedFrame: CGRect
                if livePane.groupId != nil {
                    snappedFrame = proposedFrame
                    canvas.activeSnapGuides = []
                } else {
                    // Calculate snap (this updates canvas.activeSnapGuides)
                    snappedFrame = canvas.calculateSnapForPane(paneId, proposedFrame: proposedFrame)

                    // Store snap result for potential auto-grouping
                    let otherPanes = canvas.panes.filter { $0.id != paneId }
                    lastSnapResult = canvas.snapEngine.calculateSnap(
                        movingFrame: snappedFrame,
                        otherPanes: otherPanes
                    )
                }

                // Calculate offset from current pane position to snapped position
                let offset = CGSize(
                    width: snappedFrame.origin.x - livePane.frame.origin.x,
                    height: snappedFrame.origin.y - livePane.frame.origin.y
                )

                // Update group drag offset for other panes in the group
                if livePane.groupId != nil {
                    canvas.groupDragOffset = offset
                }

                dragOffset = CGSize(
                    width: offset.width * canvas.scale,
                    height: offset.height * canvas.scale
                )
            }
            .onEnded { value in
                // If we were resizing, don't apply drag logic
                guard !isResizing else {
                    isDragging = false
                    dragOffset = .zero
                    startFrame = .zero
                    return
                }

                isDragging = false

                // Calculate final delta
                let canvasDelta = CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                )

                // Calculate final frame with snapping
                let proposedFrame = CGRect(
                    x: startFrame.origin.x + canvasDelta.width,
                    y: startFrame.origin.y + canvasDelta.height,
                    width: startFrame.width,
                    height: startFrame.height
                )
                let snappedFrame = canvas.calculateSnapForPane(paneId, proposedFrame: proposedFrame)

                // Get snap result for auto-grouping
                let otherPanes = canvas.panes.filter { $0.id != paneId }
                let snapResult = canvas.snapEngine.calculateSnap(
                    movingFrame: snappedFrame,
                    otherPanes: otherPanes
                )

                // Apply movement
                if let groupId = livePane.groupId {
                    // Move entire group by the same delta
                    let delta = CGSize(
                        width: snappedFrame.origin.x - startFrame.origin.x,
                        height: snappedFrame.origin.y - startFrame.origin.y
                    )
                    canvas.moveGroupBy(groupId, delta: delta)
                } else {
                    // Move just this pane
                    canvas.movePaneTo(paneId, position: snappedFrame.origin)

                    // Auto-group if snapped edge-to-edge
                    if snapResult.hasSnap && !snapResult.snappedPaneIds.isEmpty {
                        // Check if any snap was edge-to-edge
                        let hasEdgeSnap = snapResult.guides.contains { $0.type == .edgeToEdge }
                        if hasEdgeSnap {
                            canvas.autoGroupAfterSnap(paneId: paneId, snappedToIds: snapResult.snappedPaneIds)
                        }
                    }
                }

                // Clear snap guides and group drag state
                canvas.clearSnapGuides()
                canvas.draggingGroupId = nil
                canvas.groupDragOffset = .zero
                dragOffset = .zero
                startFrame = .zero
                lastSnapResult = nil
            }
    }
}

// MARK: - Preview

#Preview {
    let canvas = CanvasState()

    return ZStack {
        Color.gray.opacity(0.2)

        DraggablePaneView(
            pane: Pane(
                type: .browser(BrowserPaneState()),
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                title: "Browser"
            )
        )
        .frame(width: 400, height: 300)
    }
    .frame(width: 600, height: 500)
    .canvasState(canvas)
}
