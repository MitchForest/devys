import SwiftUI
import AppKit

/// A view modifier that adds scroll-wheel zoom support to the canvas.
///
/// On macOS, this captures scroll events and converts them to zoom actions.
/// Two-finger scroll on trackpad = zoom in/out (native macOS behavior).
public struct ScrollZoomModifier: ViewModifier {
    var canvas: CanvasState
    @State private var scrollMonitor: Any?

    /// Zoom sensitivity - how much scroll translates to zoom
    private let zoomSensitivity: CGFloat = 0.01

    public init(canvas: CanvasState) {
        self.canvas = canvas
    }

    public func body(content: Content) -> some View {
        content
            .onAppear {
                setupScrollMonitor()
            }
            .onDisappear {
                removeScrollMonitor()
            }
    }

    private func setupScrollMonitor() {
        // Use local event monitor to capture scroll wheel events
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [canvas] event in
            handleScrollEvent(event, canvas: canvas)
            return event // Return nil to consume, event to pass through
        }
    }

    private func removeScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    private func handleScrollEvent(_ event: NSEvent, canvas: CanvasState) {
        // Get scroll delta
        let deltaY = event.scrollingDeltaY

        // Skip tiny movements
        guard abs(deltaY) > 0.5 else { return }

        // Only zoom on two-finger scroll (not momentum)
        // Trackpad scroll has phase, mouse scroll wheel doesn't
        let isTrackpadScroll = event.phase != [] || event.momentumPhase != []
        let isMouseScrollWheel = event.phase == [] && event.momentumPhase == []

        // For trackpad: require ⌘ key OR use direct phase (not momentum)
        // For mouse: always zoom
        let shouldZoom: Bool
        if event.modifierFlags.contains(.command) {
            // ⌘+scroll always zooms
            shouldZoom = true
        } else if isMouseScrollWheel {
            // Mouse scroll wheel zooms
            shouldZoom = true
        } else if isTrackpadScroll && event.phase == .changed {
            // Direct trackpad scroll (not momentum) zooms
            shouldZoom = true
        } else {
            shouldZoom = false
        }

        guard shouldZoom else { return }

        // Calculate new scale
        let zoomFactor = 1.0 + (deltaY * zoomSensitivity)
        let newScale = canvas.scale * zoomFactor

        // Get viewport size and cursor location
        guard let window = event.window,
              let contentView = window.contentView else {
            Task { @MainActor in
                canvas.setScale(newScale)
            }
            return
        }

        let viewportSize = contentView.bounds.size
        let locationInWindow = event.locationInWindow
        // Flip Y coordinate (AppKit is bottom-left origin, SwiftUI is top-left)
        let location = CGPoint(
            x: locationInWindow.x,
            y: viewportSize.height - locationInWindow.y
        )

        // Zoom toward cursor position
        Task { @MainActor in
            canvas.zoom(to: newScale, toward: location, viewportSize: viewportSize)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds scroll-wheel zoom support to the view.
    public func scrollZoom(canvas: CanvasState) -> some View {
        modifier(ScrollZoomModifier(canvas: canvas))
    }
}
