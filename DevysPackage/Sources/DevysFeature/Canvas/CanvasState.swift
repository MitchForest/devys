import SwiftUI
import Combine

/// Central state object for the infinite canvas.
///
/// Manages:
/// - Viewport position (offset) and zoom level (scale)
/// - Coordinate transforms between screen and canvas space
/// - Future: panes, connectors, groups, selection
@MainActor
public final class CanvasState: ObservableObject {
    
    // MARK: - Viewport State
    
    /// Pan offset - the canvas position relative to viewport center.
    /// Positive X = canvas moved right, Positive Y = canvas moved down.
    @Published public var offset: CGPoint = .zero
    
    /// Zoom scale factor. 1.0 = 100%, 0.5 = 50%, 2.0 = 200%.
    @Published public var scale: CGFloat = Layout.defaultScale
    
    // MARK: - Initialization
    
    public init() {}
    
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
