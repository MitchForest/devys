import SwiftUI

/// Root content view for the Devys application.
///
/// This view serves as the main container and hosts:
/// - The infinite canvas with pan/zoom
/// - Overlay UI (zoom indicator, etc.)
public struct ContentView: View {
    @StateObject private var canvasState = CanvasState()
    
    public init() {}
    
    public var body: some View {
        CanvasView()
            .environmentObject(canvasState)
            .frame(minWidth: 800, minHeight: 600)
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                canvasState.zoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                canvasState.zoomOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomToFit)) { _ in
                canvasState.zoomToFit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomTo100)) { _ in
                canvasState.zoomTo100()
            }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
