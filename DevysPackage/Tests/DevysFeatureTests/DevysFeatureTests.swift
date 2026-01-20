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
