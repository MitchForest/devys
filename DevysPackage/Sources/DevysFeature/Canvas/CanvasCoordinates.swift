import Foundation
import CoreGraphics

// MARK: - Coordinate Transforms

extension CanvasState {

    /// Convert a screen point to canvas coordinates.
    ///
    /// The canvas uses a coordinate system where (0,0) is at the center of the viewport
    /// when offset is zero. Panning moves the offset, and zooming scales around center.
    ///
    /// - Parameters:
    ///   - screenPoint: Point in screen/window coordinates
    ///   - viewportSize: Size of the viewport (window content area)
    /// - Returns: Point in canvas coordinates
    public func canvasPoint(from screenPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (screenPoint.x - center.x) / scale - offset.x,
            y: (screenPoint.y - center.y) / scale - offset.y
        )
    }

    /// Convert a canvas point to screen coordinates.
    ///
    /// - Parameters:
    ///   - canvasPoint: Point in canvas coordinates
    ///   - viewportSize: Size of the viewport (window content area)
    /// - Returns: Point in screen/window coordinates
    public func screenPoint(from canvasPoint: CGPoint, viewportSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        return CGPoint(
            x: (canvasPoint.x + offset.x) * scale + center.x,
            y: (canvasPoint.y + offset.y) * scale + center.y
        )
    }

    /// Get the visible rectangle in canvas coordinates.
    ///
    /// This is useful for:
    /// - Culling: Only render objects that intersect this rect
    /// - Grid: Determine which grid lines/dots to draw
    ///
    /// - Parameter viewportSize: Size of the viewport
    /// - Returns: Rectangle representing the visible area in canvas coordinates
    public func visibleRect(viewportSize: CGSize) -> CGRect {
        let topLeft = canvasPoint(from: .zero, viewportSize: viewportSize)
        let bottomRight = canvasPoint(
            from: CGPoint(x: viewportSize.width, y: viewportSize.height),
            viewportSize: viewportSize
        )
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    /// Convert a size from screen to canvas coordinates.
    ///
    /// - Parameter screenSize: Size in screen points
    /// - Returns: Size in canvas units
    public func canvasSize(from screenSize: CGSize) -> CGSize {
        CGSize(
            width: screenSize.width / scale,
            height: screenSize.height / scale
        )
    }

    /// Convert a size from canvas to screen coordinates.
    ///
    /// - Parameter canvasSize: Size in canvas units
    /// - Returns: Size in screen points
    public func screenSize(from canvasSize: CGSize) -> CGSize {
        CGSize(
            width: canvasSize.width * scale,
            height: canvasSize.height * scale
        )
    }
}

// MARK: - Zoom Toward Point

extension CanvasState {

    /// Zoom toward a specific screen point (e.g., cursor position).
    ///
    /// This keeps the point under the cursor stationary while zooming,
    /// which feels more natural than zooming toward the center.
    ///
    /// - Parameters:
    ///   - newScale: Target scale value
    ///   - screenPoint: The point to zoom toward (in screen coordinates)
    ///   - viewportSize: Size of the viewport
    public func zoom(to newScale: CGFloat, toward screenPoint: CGPoint, viewportSize: CGSize) {
        let clampedScale = min(max(newScale, Layout.minScale), Layout.maxScale)

        // Get the canvas point under the cursor before zoom
        let canvasPointBeforeZoom = canvasPoint(from: screenPoint, viewportSize: viewportSize)

        // Apply new scale
        scale = clampedScale

        // Get where that canvas point would be on screen after zoom
        let screenPointAfterZoom = self.screenPoint(from: canvasPointBeforeZoom, viewportSize: viewportSize)

        // Adjust offset to keep the point stationary
        let deltaScreen = CGSize(
            width: screenPoint.x - screenPointAfterZoom.x,
            height: screenPoint.y - screenPointAfterZoom.y
        )
        pan(by: deltaScreen)
    }
}
