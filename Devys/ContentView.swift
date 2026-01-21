import SwiftUI
import AppKit

/// Root content view for the Devys application.
///
/// This view serves as the main container and hosts:
/// - Project tab bar for switching between projects
/// - The infinite canvas with pan/zoom
/// - Overlay UI (zoom indicator, etc.)
public struct ContentView: View {
    @Environment(\.workspaceState) private var _workspace
    private var workspace: WorkspaceState { _workspace ?? WorkspaceState() }

    public init() {}

    public var body: some View {
        contentStack
            .frame(minWidth: 800, minHeight: 600)
            .modifier(ZoomCommandsModifier(canvas: activeCanvas))
            .modifier(PaneCommandsModifier(
                canvas: activeCanvas,
                onDuplicate: duplicateSelectedPanes,
                onClose: handleClosePane
            ))
            .modifier(PaneCreationModifier(
                canvas: activeCanvas,
                workspace: workspace
            ))
            .modifier(GroupCommandsModifier(canvas: activeCanvas))
            .modifier(TabCommandsModifier(
                workspace: workspace,
                onShowOpenDialog: showOpenProjectDialog,
                onCloseTab: closeActiveTab
            ))
            .modifier(ProjectCommandsModifier(
                onShowDialog: showOpenProjectDialog,
                onOpenURL: openProject
            ))
            .modifier(HotkeyCommandsModifier(canvas: activeCanvas))
            .modifier(DeleteKeyModifier(canvas: activeCanvas))
    }

    // MARK: - Content Stack

    private var contentStack: some View {
        VStack(spacing: 0) {
            if workspace.hasTabs {
                ProjectTabBar(onAddTab: showOpenProjectDialog)
            }
            mainContent
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if let canvasState = workspace.activeCanvasState {
            CanvasView(canvas: canvasState)
        } else {
            EmptyWorkspaceView(onOpenProject: showOpenProjectDialog)
        }
    }

    // MARK: - Computed Properties

    private var activeCanvas: CanvasState? {
        workspace.activeCanvasState
    }

    // MARK: - Actions

    private func duplicateSelectedPanes() {
        guard let canvas = activeCanvas else { return }
        let ids = canvas.selectedPaneIds
        for id in ids {
            canvas.duplicatePane(id)
        }
    }

    private func handleClosePane() {
        guard let canvas = activeCanvas else { return }
        if canvas.selectedPaneIds.isEmpty {
            closeActiveTab()
        } else {
            canvas.deleteSelectedPanes()
        }
    }

    private func closeActiveTab() {
        guard let tabId = workspace.activeTabId else { return }
        workspace.closeTab(tabId)
    }

    private func showOpenProjectDialog() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose a project folder to open"
        panel.prompt = "Open"

        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    openProject(at: url)
                }
            }
        }
    }

    private func openProject(at url: URL) {
        do {
            try workspace.openProject(at: url)
        } catch {
            print("Failed to open project: \(error.localizedDescription)")
        }
    }
}

// MARK: - Command Modifiers

/// Zoom commands (⌘+, ⌘-, ⌘0, ⌘1)
private struct ZoomCommandsModifier: ViewModifier {
    let canvas: CanvasState?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
                canvas?.zoomIn()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
                canvas?.zoomOut()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomToFit)) { _ in
                canvas?.zoomToFit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomTo100)) { _ in
                canvas?.zoomTo100()
            }
    }
}

/// Pane action commands (duplicate, close)
private struct PaneCommandsModifier: ViewModifier {
    let canvas: CanvasState?
    let onDuplicate: () -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .duplicatePane)) { _ in
                onDuplicate()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closePane)) { _ in
                onClose()
            }
    }
}

/// Pane creation commands
private struct PaneCreationModifier: ViewModifier {
    let canvas: CanvasState?
    let workspace: WorkspaceState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTerminal)) { _ in
                // Auto-set working directory to project root if available
                let workingDir = workspace.activeProject?.rootURL ?? FileManager.default.homeDirectoryForCurrentUser
                canvas?.createPane(type: .terminal(TerminalState(workingDirectory: workingDir)))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newBrowser)) { _ in
                canvas?.createPane(type: .browser(BrowserPaneState()))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newFileExplorer)) { _ in
                let rootURL = workspace.activeProject?.rootURL
                canvas?.createPane(type: .fileExplorer(FileExplorerPaneState(rootURL: rootURL)))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newCodeEditor)) { _ in
                canvas?.createPane(type: .codeEditor(CodeEditorPaneState()))
            }
            .onReceive(NotificationCenter.default.publisher(for: .newGit)) { _ in
                let rootURL = workspace.activeProject?.rootURL
                canvas?.createPane(type: .git(GitPaneState(repositoryURL: rootURL)))
            }
    }
}

/// Group commands (⌘G, ⌘⇧U)
private struct GroupCommandsModifier: ViewModifier {
    let canvas: CanvasState?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .groupPanes)) { _ in
                canvas?.groupSelectedPanes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ungroupPanes)) { _ in
                canvas?.ungroupSelectedPanes()
            }
    }
}

/// Tab navigation commands
private struct TabCommandsModifier: ViewModifier {
    let workspace: WorkspaceState
    let onShowOpenDialog: () -> Void
    let onCloseTab: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTab)) { _ in
                onShowOpenDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .closeTab)) { _ in
                onCloseTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nextTab)) { _ in
                workspace.switchToNextTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .previousTab)) { _ in
                workspace.switchToPreviousTab()
            }
    }
}

/// Project commands (open project)
private struct ProjectCommandsModifier: ViewModifier {
    let onShowDialog: () -> Void
    let onOpenURL: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .showOpenProjectDialog)) { _ in
                onShowDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProjectAtURL)) { notification in
                if let url = notification.object as? URL {
                    onOpenURL(url)
                }
            }
    }
}

/// Pane hotkey commands (⌘2-9)
private struct HotkeyCommandsModifier: ViewModifier {
    let canvas: CanvasState?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .focusPaneByHotkey)) { notification in
                if let index = notification.object as? Int {
                    canvas?.focusPaneByHotkey(index)
                }
            }
    }
}

/// Delete key handlers
private struct DeleteKeyModifier: ViewModifier {
    let canvas: CanvasState?

    func body(content: Content) -> some View {
        content
            .onKeyPress(.delete) {
                canvas?.deleteSelectedPanes()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                canvas?.deleteSelectedPanes()
                return .handled
            }
    }
}

// MARK: - Preview

#Preview("With Tabs") {
    let workspace = WorkspaceState()
    let _ = workspace.addTab(for: Project(rootURL: URL(fileURLWithPath: "/Users/dev/my-app"), gitBranch: "main"))

    return ContentView()
        .workspaceState(workspace)
}

#Preview("Empty") {
    ContentView()
        .workspaceState(WorkspaceState())
}
