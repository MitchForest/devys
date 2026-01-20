import SwiftUI

/// Wrapper that makes a pane draggable on the canvas.
///
/// Handles:
/// - Drag gesture for moving panes
/// - Click to select
/// - ⌘+click for multi-select
/// - Brings pane to front on interaction
public struct DraggablePaneView: View {
    let pane: Pane
    @EnvironmentObject private var canvas: CanvasState
    
    /// Tracks drag offset during gesture
    @State private var dragOffset: CGSize = .zero
    
    /// Whether we're currently dragging
    @State private var isDragging: Bool = false
    
    public init(pane: Pane) {
        self.pane = pane
    }
    
    public var body: some View {
        PaneContainerView(pane: pane)
            .offset(x: dragOffset.width, y: dragOffset.height)
            .gesture(dragGesture)
            .onTapGesture {
                // Regular click selects this pane only
                canvas.selectPane(pane.id)
            }
            .animation(isDragging ? nil : .easeOut(duration: 0.1), value: dragOffset)
    }
    
    // MARK: - Gestures
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                isDragging = true
                
                // Select pane on drag start if not already selected
                if !canvas.isPaneSelected(pane.id) {
                    canvas.selectPane(pane.id)
                }
                
                // Convert screen delta to canvas delta (accounting for zoom)
                dragOffset = CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                )
            }
            .onEnded { value in
                isDragging = false
                // Apply the final movement
                let delta = CGSize(
                    width: value.translation.width / canvas.scale,
                    height: value.translation.height / canvas.scale
                )
                canvas.movePaneBy(pane.id, delta: delta)
                dragOffset = .zero
            }
    }
}

// MARK: - Preview

#Preview {
    let canvas = CanvasState()
    
    return ZStack {
        Color.gray.opacity(0.2)
        
        DraggablePaneView(
            pane: Pane(
                type: .browser(BrowserPaneState()),
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                title: "Browser"
            )
        )
        .frame(width: 400, height: 300)
    }
    .frame(width: 600, height: 500)
    .environmentObject(canvas)
}
