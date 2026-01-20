import SwiftUI

/// Root content view for the Devys application.
///
/// This view serves as the main container and hosts:
/// - The infinite canvas with pan/zoom
/// - Overlay UI (zoom indicator, etc.)
public struct ContentView: View {
    @State private var canvasState = CanvasState()

    public init() {}

    public var body: some View {
        CanvasView(canvas: canvasState)
            .frame(minWidth: 800, minHeight: 600)
            // Zoom commands
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
            // Pane commands
            .onReceive(NotificationCenter.default.publisher(for: .duplicatePane)) { _ in
                duplicateSelectedPanes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closePane)) { _ in
                canvasState.deleteSelectedPanes()
            }
            // Pane creation commands
            .onReceive(NotificationCenter.default.publisher(for: .newTerminal)) { _ in
                canvasState.createPane(type: .terminal(TerminalPaneState()))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newBrowser)) { _ in
                canvasState.createPane(type: .browser(BrowserPaneState()))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newFileExplorer)) { _ in
                canvasState.createPane(type: .fileExplorer(FileExplorerPaneState()))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newCodeEditor)) { _ in
                canvasState.createPane(type: .codeEditor(CodeEditorPaneState()))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newGit)) { _ in
                canvasState.createPane(type: .git(GitPaneState()))
            }
            // Group commands
            .onReceive(NotificationCenter.default.publisher(for: .groupPanes)) { _ in
                canvasState.groupSelectedPanes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ungroupPanes)) { _ in
                canvasState.ungroupSelectedPanes()
            }
            // Delete key handler
            .onKeyPress(.delete) {
                canvasState.deleteSelectedPanes()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                canvasState.deleteSelectedPanes()
                return .handled
            }
    }

    // MARK: - Actions

    private func duplicateSelectedPanes() {
        let ids = canvasState.selectedPaneIds
        for id in ids {
            canvasState.duplicatePane(id)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
