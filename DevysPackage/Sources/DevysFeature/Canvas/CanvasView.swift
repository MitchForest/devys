import SwiftUI

/// The main infinite canvas view that hosts all panes and handles navigation.
///
/// This view provides:
/// - Infinite pannable/zoomable workspace
/// - Dot grid background (when zoomed in enough)
/// - Container for all pane views (Sprint 3+)
/// - Connector rendering layer (Sprint 6+)
public struct CanvasView: View {
    @EnvironmentObject private var canvas: CanvasState
    
    /// Tracks cumulative drag translation during pan gesture
    @State private var dragOffset: CGSize = .zero
    
    /// Tracks gesture scale for pinch-to-zoom
    @GestureState private var gestureScale: CGFloat = 1.0
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background color
                Theme.canvasBackground
                    .ignoresSafeArea()
                
                // Dot grid
                CanvasGridView(
                    offset: effectiveOffset,
                    scale: effectiveScale
                )
                
                // Canvas origin marker (for debugging/reference)
                canvasOriginMarker(viewportSize: geometry.size)
                
                // Future: Panes will be rendered here (Sprint 3+)
                
                // Zoom indicator
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZoomIndicator(canvas: canvas)
                            .padding(12)
                    }
                }
            }
            .contentShape(Rectangle()) // Make entire area interactive
            .gesture(panGesture)
            .gesture(zoomGesture)
            .onAppear {
                setupScrollWheelZoom()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Effective offset including active drag gesture
    private var effectiveOffset: CGPoint {
        CGPoint(
            x: canvas.offset.x + dragOffset.width / canvas.scale,
            y: canvas.offset.y + dragOffset.height / canvas.scale
        )
    }
    
    /// Effective scale including active pinch gesture
    private var effectiveScale: CGFloat {
        let newScale = canvas.scale * gestureScale
        return min(max(newScale, Layout.minScale), Layout.maxScale)
    }
    
    // MARK: - Gestures
    
    /// Pan gesture - drag to move the canvas
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                canvas.pan(by: value.translation)
                dragOffset = .zero
            }
    }
    
    /// Zoom gesture - pinch to zoom
    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                let newScale = canvas.scale * value
                canvas.setScale(newScale)
            }
    }
    
    // MARK: - Scroll Wheel Zoom
    
    /// Set up scroll wheel zoom using NSEvent monitoring
    private func setupScrollWheelZoom() {
        // Note: This requires AppKit integration for scroll wheel events
        // Will be implemented via NSViewRepresentable or NSEvent.addLocalMonitorForEvents
        // For now, pinch gesture works on trackpad
    }
    
    // MARK: - Debug Views
    
    /// Shows a small marker at the canvas origin (0,0)
    @ViewBuilder
    private func canvasOriginMarker(viewportSize: CGSize) -> some View {
        let screenPos = canvas.screenPoint(from: .zero, viewportSize: viewportSize)
        
        // Only show if origin is visible on screen
        if screenPos.x > -20 && screenPos.x < viewportSize.width + 20 &&
           screenPos.y > -20 && screenPos.y < viewportSize.height + 20 {
            Circle()
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 8, height: 8)
                .position(screenPos)
        }
    }
}

// MARK: - Preview

#Preview {
    CanvasView()
        .environmentObject(CanvasState())
        .frame(width: 800, height: 600)
}
