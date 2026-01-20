import SwiftUI

/// The main infinite canvas view that hosts all panes and handles navigation.
///
/// This view provides:
/// - Infinite pannable/zoomable workspace
/// - Dot grid background (when zoomed in enough)
/// - Container for all pane views
/// - Connector rendering layer
public struct CanvasView: View {
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Theme.canvasBackground
                    .ignoresSafeArea()
                
                // Placeholder content - will be replaced in Sprint 2+
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.3x3")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("Devys Canvas")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Sprint 2: Dot grid, pan & zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("Viewport: \(Int(geometry.size.width)) × \(Int(geometry.size.height))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#Preview {
    CanvasView()
        .frame(width: 800, height: 600)
}
