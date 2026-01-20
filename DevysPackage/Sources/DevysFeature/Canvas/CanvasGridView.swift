import SwiftUI

/// Renders a dot grid background that responds to pan and zoom.
///
/// The grid provides visual reference for the infinite canvas,
/// similar to design tools like Figma or React Flow.
///
/// Performance considerations:
/// - Uses SwiftUI Canvas for efficient batch drawing
/// - Only renders dots within the visible viewport
/// - Skips rendering when zoomed out too far (dots too small)
/// - Uses drawingGroup() for Metal-backed rendering
public struct CanvasGridView: View {
    let offset: CGPoint
    let scale: CGFloat
    
    /// Base spacing between dots in canvas coordinates
    private let dotSpacing: CGFloat = Layout.dotSpacing
    
    /// Radius of each dot in screen points (constant regardless of zoom)
    private let dotRadius: CGFloat = Layout.dotRadius
    
    /// Minimum scale at which dots are rendered
    private let minVisibleScale: CGFloat = 0.15
    
    public init(offset: CGPoint, scale: CGFloat) {
        self.offset = offset
        self.scale = scale
    }
    
    public var body: some View {
        Canvas { context, size in
            drawDots(context: context, size: size)
        }
        .drawingGroup() // Flatten to single Metal layer for performance
    }
    
    private func drawDots(context: GraphicsContext, size: CGSize) {
        // Don't render if zoomed out too far
        guard scale >= minVisibleScale else { return }
        
        // Calculate spacing in screen points
        let screenSpacing = dotSpacing * scale
        
        // Don't render if dots would be too close together (performance)
        guard screenSpacing > 4 else { return }
        
        // Calculate the offset for the grid pattern
        // This makes dots appear to move with the canvas
        let offsetX = (offset.x * scale).truncatingRemainder(dividingBy: screenSpacing)
        let offsetY = (offset.y * scale).truncatingRemainder(dividingBy: screenSpacing)
        
        // Center-based offset (viewport center is canvas origin when offset is 0)
        let centerOffsetX = size.width.truncatingRemainder(dividingBy: screenSpacing) / 2
        let centerOffsetY = size.height.truncatingRemainder(dividingBy: screenSpacing) / 2
        
        let startX = offsetX + centerOffsetX
        let startY = offsetY + centerOffsetY
        
        // Calculate number of dots needed
        let cols = Int(ceil(size.width / screenSpacing)) + 2
        let rows = Int(ceil(size.height / screenSpacing)) + 2
        
        // Draw dots
        let dotColor = Theme.dotColor
        
        for row in -1..<rows {
            for col in -1..<cols {
                var x = startX + CGFloat(col) * screenSpacing
                var y = startY + CGFloat(row) * screenSpacing
                
                // Wrap negative positions
                if x < 0 { x += screenSpacing }
                if y < 0 { y += screenSpacing }
                
                // Skip if outside viewport
                guard x >= -dotRadius && x <= size.width + dotRadius &&
                      y >= -dotRadius && y <= size.height + dotRadius else {
                    continue
                }
                
                let dotRect = CGRect(
                    x: x - dotRadius,
                    y: y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
                
                context.fill(
                    Path(ellipseIn: dotRect),
                    with: .color(dotColor)
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Default Zoom") {
    CanvasGridView(offset: .zero, scale: 1.0)
        .background(Theme.canvasBackground)
        .frame(width: 400, height: 300)
}

#Preview("Zoomed In") {
    CanvasGridView(offset: .zero, scale: 2.0)
        .background(Theme.canvasBackground)
        .frame(width: 400, height: 300)
}

#Preview("Zoomed Out") {
    CanvasGridView(offset: .zero, scale: 0.5)
        .background(Theme.canvasBackground)
        .frame(width: 400, height: 300)
}

#Preview("Panned") {
    CanvasGridView(offset: CGPoint(x: 50, y: 30), scale: 1.0)
        .background(Theme.canvasBackground)
        .frame(width: 400, height: 300)
}
