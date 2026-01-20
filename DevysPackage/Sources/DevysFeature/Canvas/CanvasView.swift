import SwiftUI

/// The main infinite canvas view that hosts all panes and handles navigation.
///
/// This view provides:
/// - Infinite pannable/zoomable workspace
/// - Dot grid background (when zoomed in enough)
/// - Container for all pane views (Sprint 3+)
/// - Connector rendering layer (Sprint 6+)
public struct CanvasView: View {
    @Bindable var canvas: CanvasState

    /// Tracks cumulative drag translation during pan gesture
    @State private var dragOffset: CGSize = .zero

    /// Tracks gesture scale for pinch-to-zoom
    @GestureState private var gestureScale: CGFloat = 1.0

    public init(canvas: CanvasState) {
        self.canvas = canvas
    }

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
                    .offset(x: dragOffset.width, y: dragOffset.height)

                // Panes layer - offset by drag delta for real-time movement
                panesLayer(viewportSize: geometry.size)
                    .offset(x: dragOffset.width, y: dragOffset.height)

                // Snap guides layer (above panes)
                SnapGuideView(guides: canvas.activeSnapGuides)

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
            .gesture(canvasBackgroundTapGesture)
            .gesture(panGesture)
            .gesture(zoomGesture)
            .scrollZoom(canvas: canvas) // Two-finger scroll to zoom
            .canvasState(canvas) // Inject canvas for child views
            .onAppear {
                addTestPanesIfEmpty()
            }
        }
    }

    // MARK: - Panes Layer

    /// Renders all visible panes on the canvas
    @ViewBuilder
    private func panesLayer(viewportSize: CGSize) -> some View {
        let visibleRect = canvas.visibleRect(viewportSize: viewportSize)

        ForEach(canvas.visiblePanes(in: visibleRect)) { pane in
            paneView(for: pane, viewportSize: viewportSize)
        }
    }

    /// Renders a single pane at its correct position
    @ViewBuilder
    private func paneView(for pane: Pane, viewportSize: CGSize) -> some View {
        let screenPos = canvas.screenPoint(from: pane.center, viewportSize: viewportSize)
        let screenSize = canvas.screenSize(from: pane.frame.size)

        // Adjust height if collapsed
        let height = pane.isCollapsed
            ? Layout.paneTitleBarHeight * canvas.scale
            : screenSize.height

        DraggablePaneView(pane: pane)
            .frame(width: screenSize.width, height: height)
            .position(x: screenPos.x, y: screenPos.y - (pane.isCollapsed ? (screenSize.height - height) / 2 : 0))
    }

    // MARK: - Test Panes

    /// Add test panes for development (only if canvas is empty)
    private func addTestPanesIfEmpty() {
        #if DEBUG
        guard canvas.panes.isEmpty else { return }

        // Add a few test panes
        canvas.createPane(
            type: .terminal(TerminalPaneState()),
            at: CGPoint(x: -250, y: -100),
            title: "Terminal"
        )

        canvas.createPane(
            type: .browser(BrowserPaneState(url: URL(string: "http://localhost:3000"))),
            at: CGPoint(x: 250, y: -100),
            title: "localhost:3000"
        )

        canvas.createPane(
            type: .fileExplorer(FileExplorerPaneState()),
            at: CGPoint(x: 0, y: 200),
            title: "Project Files"
        )

        // Clear selection after adding test panes
        canvas.clearSelection()
        #endif
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

    /// Tap on background to clear selection
    private var canvasBackgroundTapGesture: some Gesture {
        TapGesture()
            .onEnded {
                canvas.clearSelection()
            }
    }

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
    CanvasView(canvas: CanvasState())
        .frame(width: 800, height: 600)
}
