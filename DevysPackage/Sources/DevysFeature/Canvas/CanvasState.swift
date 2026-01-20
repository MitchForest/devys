import SwiftUI
import Combine

/// Central state object for the infinite canvas.
///
/// Manages:
/// - Viewport position (offset) and zoom level (scale)
/// - Coordinate transforms between screen and canvas space
/// - Panes, selection, and z-ordering
@MainActor
public final class CanvasState: ObservableObject {
    
    // MARK: - Viewport State
    
    /// Pan offset - the canvas position relative to viewport center.
    /// Positive X = canvas moved right, Positive Y = canvas moved down.
    @Published public var offset: CGPoint = .zero
    
    /// Zoom scale factor. 1.0 = 100%, 0.5 = 50%, 2.0 = 200%.
    @Published public var scale: CGFloat = Layout.defaultScale
    
    // MARK: - Pane State
    
    /// All panes on the canvas
    @Published public var panes: [Pane] = []
    
    /// Currently selected pane IDs
    @Published public var selectedPaneIds: Set<UUID> = []
    
    /// Currently hovered pane ID (for hover effects)
    @Published public var hoveredPaneId: UUID?
    
    /// Next z-index to assign (ensures new panes are on top)
    private var nextZIndex: Int = 0
    
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
    
    /// Resize a pane to a new size (enforcing minimum)
    public func resizePane(_ id: UUID, to size: CGSize) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].frame.size = CGSize(
            width: max(size.width, Layout.paneMinWidth),
            height: max(size.height, Layout.paneMinHeight)
        )
    }
    
    /// Update a pane's frame
    public func updatePaneFrame(_ id: UUID, frame: CGRect) {
        guard let index = paneIndex(withId: id) else { return }
        panes[index].frame = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(frame.size.width, Layout.paneMinWidth),
            height: max(frame.size.height, Layout.paneMinHeight)
        )
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
    
    /// Select a single pane (deselecting others)
    public func selectPane(_ id: UUID) {
        selectedPaneIds = [id]
        bringToFront(id)
    }
    
    /// Toggle selection of a pane (for multi-select with ⌘)
    public func togglePaneSelection(_ id: UUID) {
        if selectedPaneIds.contains(id) {
            selectedPaneIds.remove(id)
        } else {
            selectedPaneIds.insert(id)
            bringToFront(id)
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
}
