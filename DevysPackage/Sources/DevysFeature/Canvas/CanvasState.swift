import SwiftUI
import Observation

/// Central state object for the infinite canvas.
///
/// Manages:
/// - Viewport position (offset) and zoom level (scale)
/// - Coordinate transforms between screen and canvas space
/// - Panes, selection, and z-ordering
@MainActor
@Observable
public final class CanvasState {

    // MARK: - Viewport State

    /// Pan offset - the canvas position relative to viewport center.
    /// Positive X = canvas moved right, Positive Y = canvas moved down.
    public var offset: CGPoint = .zero

    /// Zoom scale factor. 1.0 = 100%, 0.5 = 50%, 2.0 = 200%.
    public var scale: CGFloat = Layout.defaultScale

    // MARK: - Pane State

    /// All panes on the canvas
    public var panes: [Pane] = []

    /// Currently selected pane IDs
    public var selectedPaneIds: Set<UUID> = []

    /// Currently hovered pane ID (for hover effects)
    public var hoveredPaneId: UUID?

    /// Next z-index to assign (ensures new panes are on top)
    private var nextZIndex: Int = 0

    // MARK: - Snapping State

    /// Current snap guides to display
    public var activeSnapGuides: [SnapGuide] = []

    /// Snap engine for calculating alignments
    public let snapEngine = SnapEngine()

    /// Next group ID to assign
    private var nextGroupId: Int = 0

    // MARK: - Group Drag State

    /// Group currently being dragged (if any)
    public var draggingGroupId: UUID?

    /// Current drag offset for the group being dragged (in canvas coordinates)
    public var groupDragOffset: CGSize = .zero

    // MARK: - Initialization

    public init() {}

    // MARK: - Pane Queries

    /// Get a pane by ID
    public func pane(withId id: UUID) -> Pane? {
        panes.first { $0.id == id }
    }

    /// Get the index of a pane by ID
    public func paneIndex(withId id: UUID) -> Int? {
        panes.firstIndex { $0.id == id }
    }

    /// Get panes sorted by z-index (for rendering)
    public var panesSortedByZIndex: [Pane] {
        panes.sorted { $0.zIndex < $1.zIndex }
    }

    /// Get visible panes within a viewport
    public func visiblePanes(in viewportRect: CGRect) -> [Pane] {
        panesSortedByZIndex.filter { pane in
            pane.frame.intersects(viewportRect)
        }
    }

    // MARK: - Pane Creation

    /// Create a new pane at the center of the current viewport
    public func createPane(type: PaneType, at position: CGPoint? = nil, title: String? = nil) {
        let pos = position ?? CGPoint(x: -offset.x, y: -offset.y)
        var pane = Pane.create(type: type, at: pos, title: title)
        pane.zIndex = nextZIndex
        nextZIndex += 1
        panes.append(pane)
        selectedPaneIds = [pane.id]
    }

    // MARK: - Pane Modification

    /// Delete a pane by ID
    public func deletePane(_ id: UUID) {
        panes.removeAll { $0.id == id }
        selectedPaneIds.remove(id)
        if hoveredPaneId == id {
            hoveredPaneId = nil
        }
    }

    /// Delete all selected panes
    public func deleteSelectedPanes() {
        for id in selectedPaneIds {
            panes.removeAll { $0.id == id }
        }
        selectedPaneIds.removeAll()
    }

    /// Move a pane by a delta (in canvas coordinates)
    public func movePaneBy(_ id: UUID, delta: CGSize) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].frame.origin.x += delta.width
        panes[index].frame.origin.y += delta.height
    }

    /// Move a pane to an absolute position
    public func movePaneTo(_ id: UUID, position: CGPoint) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].frame.origin = position
    }

    /// Resize a pane to a new size (enforcing min/max)
    public func resizePane(_ id: UUID, to size: CGSize) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].frame.size = CGSize(
            width: clampWidth(size.width),
            height: clampHeight(size.height)
        )
    }

    /// Update a pane's frame with proper clamping
    /// This version handles origin adjustment when size hits limits
    public func updatePaneFrame(_ id: UUID, frame: CGRect) {
        guard let index = paneIndex(withId: id) else { return }

        let clampedWidth = clampWidth(frame.size.width)
        let clampedHeight = clampHeight(frame.size.height)

        panes[index].frame = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: clampedWidth,
            height: clampedHeight
        )
    }

    /// Clamp width to min/max bounds
    private func clampWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, Layout.paneMinWidth), Layout.paneMaxWidth)
    }

    /// Clamp height to min/max bounds
    private func clampHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, Layout.paneMinHeight), Layout.paneMaxHeight)
    }

    /// Bring a pane to the front
    public func bringToFront(_ id: UUID) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].zIndex = nextZIndex
        nextZIndex += 1
    }

    /// Toggle collapse state of a pane
    public func togglePaneCollapse(_ id: UUID) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].isCollapsed.toggle()
    }

    /// Update pane title
    public func updatePaneTitle(_ id: UUID, title: String) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].title = title
    }

    /// Duplicate a pane
    public func duplicatePane(_ id: UUID) {
        guard let original = pane(withId: id) else { return }
        var newPane = original
        newPane = Pane(
            id: UUID(),
            type: original.type,
            frame: original.frame.offsetBy(dx: 30, dy: 30),
            zIndex: nextZIndex,
            groupId: nil,
            title: original.title,
            isCollapsed: original.isCollapsed
        )
        nextZIndex += 1
        panes.append(newPane)
        selectedPaneIds = [newPane.id]
    }

    // MARK: - Selection

    /// Select a pane (and its entire group if grouped)
    public func selectPane(_ id: UUID) {
        selectedPaneIds = [id]
        bringToFront(id)

        // If this pane is in a group, select all group members
        if let gid = groupId(for: id) {
            for pane in panesInGroup(gid) {
                selectedPaneIds.insert(pane.id)
            }
        }
    }

    /// Toggle selection of a pane (for multi-select with ⌘/⇧)
    /// If pane is in a group, toggles the entire group
    public func togglePaneSelection(_ id: UUID) {
        // Check if this pane (or its group) is already selected
        let isCurrentlySelected = selectedPaneIds.contains(id)

        if isCurrentlySelected {
            // Deselect this pane and its group
            selectedPaneIds.remove(id)
            if let gid = groupId(for: id) {
                for pane in panesInGroup(gid) {
                    selectedPaneIds.remove(pane.id)
                }
            }
        } else {
            // Select this pane and its group
            selectedPaneIds.insert(id)
            bringToFront(id)
            if let gid = groupId(for: id) {
                for pane in panesInGroup(gid) {
                    selectedPaneIds.insert(pane.id)
                }
            }
        }
    }

    /// Clear all selection
    public func clearSelection() {
        selectedPaneIds.removeAll()
    }

    /// Check if a pane is selected
    public func isPaneSelected(_ id: UUID) -> Bool {
        selectedPaneIds.contains(id)
    }

    // MARK: - Zoom Actions

    /// Zoom in by a fixed factor.
    public func zoomIn() {
        let newScale = scale * 1.25
        scale = min(newScale, Layout.maxScale)
    }

    /// Zoom out by a fixed factor.
    public func zoomOut() {
        let newScale = scale / 1.25
        scale = max(newScale, Layout.minScale)
    }

    /// Reset to default zoom and center position.
    public func zoomToFit() {
        scale = Layout.defaultScale
        offset = .zero
    }

    /// Reset to 100% zoom, keeping current position.
    public func zoomTo100() {
        scale = 1.0
    }

    /// Set zoom to a specific scale, clamped to valid range.
    public func setScale(_ newScale: CGFloat) {
        scale = min(max(newScale, Layout.minScale), Layout.maxScale)
    }

    // MARK: - Pan Actions

    /// Move the canvas by a delta (in screen points).
    /// Converts screen delta to canvas delta accounting for current scale.
    public func pan(by screenDelta: CGSize) {
        offset.x += screenDelta.width / scale
        offset.y += screenDelta.height / scale
    }

    /// Set absolute offset position.
    public func setOffset(_ newOffset: CGPoint) {
        offset = newOffset
    }

    // MARK: - Snapping

    /// Calculate snap for a moving pane and return adjusted position
    public func calculateSnapForPane(
        _ id: UUID,
        proposedFrame: CGRect
    ) -> CGRect {
        let otherPanes = panes.filter { $0.id != id }
        let result = snapEngine.calculateSnap(
            movingFrame: proposedFrame,
            otherPanes: otherPanes
        )

        // Update active guides for display
        activeSnapGuides = result.guides

        // Return adjusted frame
        return CGRect(
            x: proposedFrame.origin.x + result.delta.width,
            y: proposedFrame.origin.y + result.delta.height,
            width: proposedFrame.width,
            height: proposedFrame.height
        )
    }

    /// Clear snap guides (call when drag ends)
    public func clearSnapGuides() {
        activeSnapGuides = []
    }

    // MARK: - Group Management

    /// Get all panes in a group
    public func panesInGroup(_ groupId: UUID) -> [Pane] {
        panes.filter { $0.groupId == groupId }
    }

    /// Get group ID for a pane (if any)
    public func groupId(for paneId: UUID) -> UUID? {
        pane(withId: paneId)?.groupId
    }

    /// Group selected panes together
    /// If any selected panes are already in groups, merges all those groups
    public func groupSelectedPanes() {
        guard selectedPaneIds.count >= 2 else { return }

        // Collect all panes that should be in the new group:
        // 1. All selected panes
        // 2. All panes in any groups that selected panes belong to
        var allPaneIdsToGroup: Set<UUID> = selectedPaneIds
        var existingGroupIds: Set<UUID> = []

        for id in selectedPaneIds {
            if let gid = groupId(for: id) {
                existingGroupIds.insert(gid)
            }
        }

        // Add all panes from existing groups
        for gid in existingGroupIds {
            for pane in panesInGroup(gid) {
                allPaneIdsToGroup.insert(pane.id)
            }
        }

        // Use first existing group ID or create new one
        let targetGroupId = existingGroupIds.first ?? UUID()

        // Assign all panes to the target group
        for id in allPaneIdsToGroup {
            if let index = paneIndex(withId: id) {
                panes[index].groupId = targetGroupId
            }
        }

        // Update selection to include all grouped panes
        selectedPaneIds = allPaneIdsToGroup
    }

    /// Ungroup selected panes
    public func ungroupSelectedPanes() {
        for id in selectedPaneIds {
            if let index = paneIndex(withId: id) {
                panes[index].groupId = nil
            }
        }
    }

    /// Ungroup a specific group
    public func ungroupPanes(groupId: UUID) {
        for index in panes.indices where panes[index].groupId == groupId {
            panes[index].groupId = nil
        }
    }

    /// Move all panes in a group by a delta
    public func moveGroupBy(_ groupId: UUID, delta: CGSize) {
        for index in panes.indices where panes[index].groupId == groupId {
            panes[index].frame.origin.x += delta.width
            panes[index].frame.origin.y += delta.height
        }
    }

    /// Check if a pane is in a group
    public func isInGroup(_ paneId: UUID) -> Bool {
        pane(withId: paneId)?.groupId != nil
    }

    /// Select all panes in the same group as the given pane
    public func selectGroup(containing paneId: UUID) {
        guard let gid = groupId(for: paneId) else { return }
        let groupPanes = panesInGroup(gid)
        for pane in groupPanes {
            selectedPaneIds.insert(pane.id)
        }
    }

    /// Auto-group panes that are snapped edge-to-edge
    public func autoGroupAfterSnap(paneId: UUID, snappedToIds: Set<UUID>) {
        guard !snappedToIds.isEmpty else { return }

        // If the moved pane is already in a group, add snapped panes to that group
        // Otherwise, if any snapped pane is in a group, join that group
        // Otherwise, create a new group

        var targetGroupId: UUID?

        if let existingGroupId = groupId(for: paneId) {
            targetGroupId = existingGroupId
        } else {
            for snappedId in snappedToIds {
                if let gid = groupId(for: snappedId) {
                    targetGroupId = gid
                    break
                }
            }
        }

        if targetGroupId == nil {
            targetGroupId = UUID()
        }

        // Add moved pane to group
        if let index = paneIndex(withId: paneId) {
            panes[index].groupId = targetGroupId
        }

        // Add snapped panes to group
        for snappedId in snappedToIds {
            if let index = paneIndex(withId: snappedId) {
                panes[index].groupId = targetGroupId
            }
        }
    }
}
