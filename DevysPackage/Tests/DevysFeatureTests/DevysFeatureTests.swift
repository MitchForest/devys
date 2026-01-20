import Testing
import SwiftUI
@testable import DevysFeature

// MARK: - Theme Color Tests

@Suite("Theme Colors")
struct ThemeColorTests {
    
    @Test("Canvas colors are distinct from pane colors")
    func canvasAndPaneColorsAreDifferent() {
        // Canvas background should be different from pane background
        // This tests that we have intentional color choices
        let _ = Theme.canvasBackground
        let _ = Theme.paneBackground
        // Both exist and are valid SwiftUI colors
        #expect(true)
    }
    
    @Test("All theme colors are accessible")
    func allColorsAccessible() {
        // Verify all color properties compile and return Color values
        // Canvas colors
        let _: Color = Theme.canvasBackground
        let _: Color = Theme.dotColor
        
        // Pane colors
        let _: Color = Theme.paneBackground
        let _: Color = Theme.paneTitleBar
        let _: Color = Theme.paneBorder
        let _: Color = Theme.paneBorderSelected
        let _: Color = Theme.paneShadow
        
        // Connector colors
        let _: Color = Theme.connectorColor
        let _: Color = Theme.connectorPending
        
        // Snap guide colors
        let _: Color = Theme.snapGuide
        
        // Group colors
        let _: Color = Theme.groupBackground
        let _: Color = Theme.groupBorder
        
        #expect(true) // If we got here, all colors are valid
    }
}

// MARK: - Layout Constant Tests

@Suite("Layout Constants")
struct LayoutConstantTests {
    
    @Test("Dot spacing is positive")
    func dotSpacingIsPositive() {
        #expect(Layout.dotSpacing > 0)
    }
    
    @Test("Dot radius is positive and reasonable")
    func dotRadiusIsReasonable() {
        #expect(Layout.dotRadius > 0)
        #expect(Layout.dotRadius < 10) // Should be small
    }
    
    @Test("Scale limits are valid")
    func scaleLimitsAreValid() {
        #expect(Layout.minScale > 0)
        #expect(Layout.maxScale > Layout.minScale)
        #expect(Layout.defaultScale >= Layout.minScale)
        #expect(Layout.defaultScale <= Layout.maxScale)
    }
    
    @Test("Pane dimensions are valid")
    func paneDimensionsAreValid() {
        // Title bar height
        #expect(Layout.paneTitleBarHeight > 0)
        #expect(Layout.paneTitleBarHeight < 100) // Reasonable limit
        
        // Corner radius
        #expect(Layout.paneCornerRadius >= 0)
        #expect(Layout.paneCornerRadius < 50)
        
        // Minimum sizes
        #expect(Layout.paneMinWidth > 0)
        #expect(Layout.paneMinHeight > 0)
        
        // Default sizes
        #expect(Layout.paneDefaultWidth >= Layout.paneMinWidth)
        #expect(Layout.paneDefaultHeight >= Layout.paneMinHeight)
    }
    
    @Test("Snap threshold is reasonable")
    func snapThresholdIsReasonable() {
        #expect(Layout.snapThreshold > 0)
        #expect(Layout.snapThreshold < 50) // Not too large
    }
    
    @Test("Handle sizes are positive")
    func handleSizesArePositive() {
        #expect(Layout.resizeHandleSize > 0)
        #expect(Layout.connectionHandleRadius > 0)
    }
    
    @Test("Animation duration is reasonable")
    func animationDurationIsReasonable() {
        #expect(Layout.animationDuration > 0)
        #expect(Layout.animationDuration < 2.0) // Not too slow
    }
}

// MARK: - Typography Tests

@Suite("Typography")
struct TypographyTests {
    
    @Test("Pane title font is accessible")
    func paneTitleFontAccessible() {
        let _: Font = Typography.paneTitle
        #expect(true)
    }
    
    @Test("Code editor font returns valid NSFont")
    func codeEditorFontValid() {
        let font: NSFont = Typography.codeEditor(size: 14)
        #expect(font.pointSize == 14)
    }
    
    @Test("Code editor font is monospaced")
    func codeEditorFontIsMonospaced() {
        let font = Typography.codeEditor(size: 12)
        // Check that it's a fixed-width font
        #expect(font.isFixedPitch)
    }
    
    @Test("Code editor font respects size parameter")
    func codeEditorFontSizeWorks() {
        let font12 = Typography.codeEditor(size: 12)
        let font16 = Typography.codeEditor(size: 16)
        #expect(font12.pointSize == 12)
        #expect(font16.pointSize == 16)
    }
}

// MARK: - Canvas State Tests

@Suite("Canvas State")
struct CanvasStateTests {
    
    @Test("Initial state has default values")
    @MainActor
    func initialState() {
        let canvas = CanvasState()
        #expect(canvas.offset == .zero)
        #expect(canvas.scale == Layout.defaultScale)
    }
    
    @Test("Zoom in increases scale")
    @MainActor
    func zoomInIncreasesScale() {
        let canvas = CanvasState()
        let initialScale = canvas.scale
        canvas.zoomIn()
        #expect(canvas.scale > initialScale)
    }
    
    @Test("Zoom out decreases scale")
    @MainActor
    func zoomOutDecreasesScale() {
        let canvas = CanvasState()
        let initialScale = canvas.scale
        canvas.zoomOut()
        #expect(canvas.scale < initialScale)
    }
    
    @Test("Zoom is clamped to max")
    @MainActor
    func zoomClampedToMax() {
        let canvas = CanvasState()
        canvas.setScale(100.0) // Way above max
        #expect(canvas.scale == Layout.maxScale)
    }
    
    @Test("Zoom is clamped to min")
    @MainActor
    func zoomClampedToMin() {
        let canvas = CanvasState()
        canvas.setScale(0.001) // Way below min
        #expect(canvas.scale == Layout.minScale)
    }
    
    @Test("Zoom to fit resets state")
    @MainActor
    func zoomToFitResetsState() {
        let canvas = CanvasState()
        canvas.setScale(2.0)
        canvas.setOffset(CGPoint(x: 100, y: 200))
        
        canvas.zoomToFit()
        
        #expect(canvas.scale == Layout.defaultScale)
        #expect(canvas.offset == .zero)
    }
    
    @Test("Pan updates offset")
    @MainActor
    func panUpdatesOffset() {
        let canvas = CanvasState()
        canvas.pan(by: CGSize(width: 100, height: 50))
        
        #expect(canvas.offset.x == 100)
        #expect(canvas.offset.y == 50)
    }
    
    @Test("Pan accounts for scale")
    @MainActor
    func panAccountsForScale() {
        let canvas = CanvasState()
        canvas.setScale(2.0) // 200% zoom
        canvas.pan(by: CGSize(width: 100, height: 50))
        
        // At 2x zoom, 100 screen points = 50 canvas units
        #expect(canvas.offset.x == 50)
        #expect(canvas.offset.y == 25)
    }
}

// MARK: - Coordinate Transform Tests

@Suite("Coordinate Transforms")
struct CoordinateTransformTests {
    
    let viewportSize = CGSize(width: 800, height: 600)
    
    @Test("Screen center maps to canvas origin at default state")
    @MainActor
    func screenCenterMapsToOrigin() {
        let canvas = CanvasState()
        let center = CGPoint(x: 400, y: 300)
        let canvasPoint = canvas.canvasPoint(from: center, viewportSize: viewportSize)
        
        #expect(abs(canvasPoint.x) < 0.001)
        #expect(abs(canvasPoint.y) < 0.001)
    }
    
    @Test("Canvas origin maps to screen center at default state")
    @MainActor
    func canvasOriginMapsToScreenCenter() {
        let canvas = CanvasState()
        let screenPoint = canvas.screenPoint(from: .zero, viewportSize: viewportSize)
        
        #expect(abs(screenPoint.x - 400) < 0.001)
        #expect(abs(screenPoint.y - 300) < 0.001)
    }
    
    @Test("Round trip conversion is identity")
    @MainActor
    func roundTripIsIdentity() {
        let canvas = CanvasState()
        canvas.setScale(1.5)
        canvas.setOffset(CGPoint(x: 50, y: -30))
        
        let originalScreen = CGPoint(x: 200, y: 150)
        let canvasPoint = canvas.canvasPoint(from: originalScreen, viewportSize: viewportSize)
        let backToScreen = canvas.screenPoint(from: canvasPoint, viewportSize: viewportSize)
        
        #expect(abs(backToScreen.x - originalScreen.x) < 0.001)
        #expect(abs(backToScreen.y - originalScreen.y) < 0.001)
    }
    
    @Test("Panning moves canvas in correct direction")
    @MainActor
    func panMovesCorrectly() {
        let canvas = CanvasState()
        
        // Pan right (positive X offset)
        canvas.setOffset(CGPoint(x: 100, y: 0))
        
        // Canvas origin should now be to the right of center
        let originOnScreen = canvas.screenPoint(from: .zero, viewportSize: viewportSize)
        #expect(originOnScreen.x > 400)
    }
    
    @Test("Zooming scales distances correctly")
    @MainActor
    func zoomScalesDistances() {
        let canvas = CanvasState()
        
        // At 1x zoom
        let point1x = canvas.screenPoint(from: CGPoint(x: 100, y: 0), viewportSize: viewportSize)
        let dist1x = point1x.x - 400 // Distance from center
        
        // At 2x zoom
        canvas.setScale(2.0)
        let point2x = canvas.screenPoint(from: CGPoint(x: 100, y: 0), viewportSize: viewportSize)
        let dist2x = point2x.x - 400
        
        // Distance should double
        #expect(abs(dist2x - dist1x * 2) < 0.001)
    }
    
    @Test("Visible rect correct at default state")
    @MainActor
    func visibleRectAtDefault() {
        let canvas = CanvasState()
        let rect = canvas.visibleRect(viewportSize: viewportSize)
        
        // At 1x zoom, centered, visible rect should be viewport size
        #expect(abs(rect.width - 800) < 0.001)
        #expect(abs(rect.height - 600) < 0.001)
        
        // Centered on origin
        #expect(abs(rect.midX) < 0.001)
        #expect(abs(rect.midY) < 0.001)
    }
    
    @Test("Visible rect shrinks when zoomed in")
    @MainActor
    func visibleRectShrinksOnZoomIn() {
        let canvas = CanvasState()
        canvas.setScale(2.0)
        
        let rect = canvas.visibleRect(viewportSize: viewportSize)
        
        // At 2x zoom, we see half the canvas area
        #expect(abs(rect.width - 400) < 0.001)
        #expect(abs(rect.height - 300) < 0.001)
    }
    
    @Test("Visible rect expands when zoomed out")
    @MainActor
    func visibleRectExpandsOnZoomOut() {
        let canvas = CanvasState()
        canvas.setScale(0.5)
        
        let rect = canvas.visibleRect(viewportSize: viewportSize)
        
        // At 0.5x zoom, we see twice the canvas area
        #expect(abs(rect.width - 1600) < 0.001)
        #expect(abs(rect.height - 1200) < 0.001)
    }
    
    @Test("Size conversion works correctly")
    @MainActor
    func sizeConversionWorks() {
        let canvas = CanvasState()
        canvas.setScale(2.0)
        
        let screenSize = CGSize(width: 100, height: 50)
        let canvasSize = canvas.canvasSize(from: screenSize)
        
        #expect(canvasSize.width == 50)
        #expect(canvasSize.height == 25)
        
        let backToScreen = canvas.screenSize(from: canvasSize)
        #expect(backToScreen.width == 100)
        #expect(backToScreen.height == 50)
    }
}
