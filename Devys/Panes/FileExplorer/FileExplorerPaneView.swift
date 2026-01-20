import SwiftUI
import AppKit

/// SwiftUI wrapper for FileExplorerController.
///
/// Bridges the NSOutlineView-based file explorer into SwiftUI
/// and handles delegate callbacks.
public struct FileExplorerPaneView: NSViewControllerRepresentable {
    /// Pane ID for focus handling
    let paneId: UUID

    /// Root URL to display
    let rootURL: URL?

    /// Callback when a file should be opened
    var onOpenFile: ((URL) -> Void)?

    /// Callback when selection changes
    var onSelectionChange: (([URL]) -> Void)?

    public init(
        paneId: UUID,
        rootURL: URL?,
        onOpenFile: ((URL) -> Void)? = nil,
        onSelectionChange: (([URL]) -> Void)? = nil
    ) {
        self.paneId = paneId
        self.rootURL = rootURL
        self.onOpenFile = onOpenFile
        self.onSelectionChange = onSelectionChange
    }

    public func makeNSViewController(context: Context) -> FileExplorerController {
        let controller = FileExplorerController()
        controller.rootURL = rootURL
        controller.delegate = context.coordinator
        return controller
    }

    public func updateNSViewController(_ controller: FileExplorerController, context: Context) {
        // Update root URL if changed
        if controller.rootURL != rootURL {
            controller.rootURL = rootURL
        }

        // Update coordinator callbacks
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.onSelectionChange = onSelectionChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onOpenFile: onOpenFile, onSelectionChange: onSelectionChange)
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, FileExplorerDelegate {
        var onOpenFile: ((URL) -> Void)?
        var onSelectionChange: (([URL]) -> Void)?

        init(onOpenFile: ((URL) -> Void)?, onSelectionChange: (([URL]) -> Void)?) {
            self.onOpenFile = onOpenFile
            self.onSelectionChange = onSelectionChange
        }

        public func fileExplorer(_ controller: FileExplorerController, didRequestOpen url: URL) {
            onOpenFile?(url)
        }

        public func fileExplorer(_ controller: FileExplorerController, didSelectItems urls: [URL]) {
            onSelectionChange?(urls)
        }
    }
}

// MARK: - Empty State View

/// Shown when no root URL is set
struct FileExplorerEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No Folder Selected")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Open a project to browse files")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Wrapper with Empty State

/// File explorer with built-in empty state handling
public struct FileExplorerView: View {
    let paneId: UUID
    let state: FileExplorerPaneState

    @Environment(\.canvasState) private var _canvas

    public init(paneId: UUID, state: FileExplorerPaneState) {
        self.paneId = paneId
        self.state = state
    }

    public var body: some View {
        Group {
            if let rootURL = state.rootURL {
                FileExplorerPaneView(
                    paneId: paneId,
                    rootURL: rootURL,
                    onOpenFile: handleOpenFile,
                    onSelectionChange: handleSelectionChange
                )
            } else {
                FileExplorerEmptyView()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPane)) { notification in
            if let id = notification.object as? UUID, id == paneId {
                // Handle focus request
                // The NSOutlineView will become first responder
            }
        }
    }

    private func handleOpenFile(_ url: URL) {
        // Create a code editor pane for this file
        guard let canvas = _canvas else { return }

        // Read file content
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""

        let editorState = CodeEditorPaneState(fileURL: url, content: content)
        canvas.createPane(type: .codeEditor(editorState), title: url.lastPathComponent)
    }

    private func handleSelectionChange(_ urls: [URL]) {
        // Could update status bar or other UI elements
    }
}

// MARK: - Preview

#Preview("With Root") {
    FileExplorerView(
        paneId: UUID(),
        state: FileExplorerPaneState(rootURL: URL(fileURLWithPath: NSHomeDirectory()))
    )
    .frame(width: 300, height: 400)
}

#Preview("Empty") {
    FileExplorerView(
        paneId: UUID(),
        state: FileExplorerPaneState()
    )
    .frame(width: 300, height: 400)
}
