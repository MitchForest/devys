import SwiftUI
import AppKit

/// A view modifier that adds scroll-wheel zoom support to the canvas.
///
/// On macOS, this captures scroll events and converts them to zoom actions.
/// Two-finger scroll on trackpad = zoom in/out (native macOS behavior).
public struct ScrollZoomModifier: ViewModifier {
    @ObservedObject var canvas: CanvasState
    
    /// Zoom sensitivity - how much scroll translates to zoom
    private let zoomSensitivity: CGFloat = 0.01
    
    public init(canvas: CanvasState) {
        self.canvas = canvas
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                ScrollZoomCaptureView(canvas: canvas, sensitivity: zoomSensitivity)
            )
    }
}

/// NSViewRepresentable that captures scroll events for zooming.
struct ScrollZoomCaptureView: NSViewRepresentable {
    let canvas: CanvasState
    let sensitivity: CGFloat
    
    func makeNSView(context: Context) -> ScrollCaptureNSView {
        let view = ScrollCaptureNSView()
        view.onScroll = { event, locationInView in
            handleScroll(event: event, location: locationInView)
        }
        return view
    }
    
    func updateNSView(_ nsView: ScrollCaptureNSView, context: Context) {
        nsView.onScroll = { event, locationInView in
            handleScroll(event: event, location: locationInView)
        }
    }
    
    private func handleScroll(event: NSEvent, location: CGPoint) {
        // Get scroll delta (trackpad gives smooth values, mouse gives discrete)
        let deltaY = event.scrollingDeltaY
        
        // Skip tiny movements
        guard abs(deltaY) > 0.1 else { return }
        
        // Calculate new scale
        let zoomFactor = 1.0 + (deltaY * sensitivity)
        let newScale = canvas.scale * zoomFactor
        
        // Get viewport size from the view
        guard let viewSize = event.window?.contentView?.bounds.size else {
            canvas.setScale(newScale)
            return
        }
        
        // Zoom toward cursor position for natural feel
        Task { @MainActor in
            canvas.zoom(to: newScale, toward: location, viewportSize: viewSize)
        }
    }
}

/// Custom NSView that captures scroll wheel events.
class ScrollCaptureNSView: NSView {
    var onScroll: ((NSEvent, CGPoint) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Make view layer-backed for proper event handling
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Convert location to view coordinates
        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)
        
        // Check if this is a zoom gesture (pinch) or regular scroll
        // Pinch gestures have phase, regular scroll doesn't (or has different behavior)
        
        // For trackpad: scrollingDeltaY is vertical scroll
        // For zoom, we use this directly
        // The MagnificationGesture handles actual pinch, this handles scroll-to-zoom
        
        if event.modifierFlags.contains(.command) {
            // ⌘ + scroll = zoom (explicit zoom mode)
            onScroll?(event, locationInView)
        } else if event.phase == .changed || event.momentumPhase == .changed {
            // Regular trackpad scroll without modifier
            // For now, let's make two-finger scroll also zoom
            // This matches apps like Figma
            onScroll?(event, locationInView)
        } else if event.phase == [] && event.momentumPhase == [] {
            // Mouse scroll wheel (discrete events)
            onScroll?(event, locationInView)
        }
        
        // Don't call super - we're handling the event
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - View Extension

extension View {
    /// Adds scroll-wheel zoom support to the view.
    public func scrollZoom(canvas: CanvasState) -> some View {
        modifier(ScrollZoomModifier(canvas: canvas))
    }
}
