import SwiftUI

/// Root content view for the Devys application.
///
/// This view serves as the main container and will host:
/// - The infinite canvas
/// - Any overlay UI (zoom indicator, etc.)
public struct ContentView: View {
    public init() {}
    
    public var body: some View {
        CanvasView()
            .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
