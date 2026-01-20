import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper for TerminalController.
///
/// This view embeds an AppKit `TerminalController` in a SwiftUI view hierarchy,
/// handling the bridge between SwiftUI state and the terminal controller.
public struct TerminalPaneView: NSViewControllerRepresentable {
    let paneId: UUID
    let state: TerminalState

    @Environment(\.canvasState) private var _canvas

    // swiftlint:disable:next force_unwrapping
    private var canvas: CanvasState { _canvas! }

    public init(paneId: UUID, state: TerminalState) {
        self.paneId = paneId
        self.state = state
    }

    public func makeNSViewController(context: Context) -> TerminalController {
        let controller = TerminalController(state: state)
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        return controller
    }

    public func updateNSViewController(_ controller: TerminalController, context: Context) {
        // State updates are handled via delegate callbacks
        // The terminal manages its own internal state
        context.coordinator.controller = controller
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(paneId: paneId, canvas: canvas)
    }

    // MARK: - Coordinator

    /// Coordinator handles delegate callbacks from the terminal controller
    /// and updates the canvas state accordingly.
    public class Coordinator: TerminalControllerDelegate {
        let paneId: UUID
        let canvas: CanvasState

        /// Reference to the controller for external access
        weak var controller: TerminalController?

        init(paneId: UUID, canvas: CanvasState) {
            self.paneId = paneId
            self.canvas = canvas
        }

        public func terminalTitleDidChange(_ title: String) {
            let paneId = self.paneId
            let canvas = self.canvas
            Task { @MainActor in
                canvas.updatePaneTitle(paneId, title: title)
            }
        }

        public func terminalDirectoryDidChange(_ directory: URL?) {
            // Could update pane subtitle or state in the future
        }

        public func terminalRunningStateDidChange(_ isRunning: Bool) {
            let paneId = self.paneId
            let canvas = self.canvas
            Task { @MainActor in
                canvas.updateTerminalRunningState(paneId, isRunning: isRunning)
            }
        }
    }
}
