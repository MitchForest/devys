import SwiftUI

/// Visual container for a pane with title bar, borders, and resize handles.
///
/// This view wraps the actual pane content and provides:
/// - Title bar with icon, title, and control buttons
/// - Visual feedback for selection and hover states
/// - Collapse/expand functionality
public struct PaneContainerView: View {
    let pane: Pane
    @Environment(\.canvasState) private var _canvas

    // swiftlint:disable:next force_unwrapping
    private var canvas: CanvasState { _canvas! } // Safe: always injected by parent

    /// Whether this pane is currently selected
    private var isSelected: Bool {
        canvas.isPaneSelected(pane.id)
    }

    /// Whether this pane is currently hovered
    private var isHovered: Bool {
        canvas.hoveredPaneId == pane.id
    }

    /// Whether terminal has a running command
    private var isTerminalRunning: Bool {
        if case .terminal = pane.type {
            return canvas.isTerminalRunning(pane.id)
        }
        return false
    }

    public init(pane: Pane) {
        self.pane = pane
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            // Content area (hidden when collapsed)
            if !pane.isCollapsed {
                contentArea
            }
        }
        .background(Theme.paneBackground)
        .clipShape(RoundedRectangle(cornerRadius: Layout.paneCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.paneCornerRadius)
                .stroke(
                    isSelected ? Theme.paneBorderSelected : Theme.paneBorder,
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .shadow(
            color: Theme.paneShadow,
            radius: isSelected ? Layout.paneShadowRadius + 2 : Layout.paneShadowRadius,
            x: 0,
            y: Layout.paneShadowOffsetY
        )
        .onHover { hovering in
            canvas.hoveredPaneId = hovering ? pane.id : nil
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
            // Hotkey badge
            if let hotkeyIndex = pane.hotkeyIndex {
                HotkeyBadge(index: hotkeyIndex)
            }

            // Running indicator for terminals
            if case .terminal = pane.type {
                TerminalStatusIndicator(isRunning: isTerminalRunning)
            }

            // Pane type icon
            Image(systemName: pane.type.iconName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            // Title
            Text(pane.title)
                .font(Typography.paneTitle)
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            // Control buttons
            HStack(spacing: 4) {
                // Collapse/expand button
                Button(action: { canvas.togglePaneCollapse(pane.id) }) {
                    Image(systemName: pane.isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(pane.isCollapsed ? "Expand" : "Collapse")

                // Close button
                Button(action: { canvas.deletePane(pane.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .opacity(isHovered || isSelected ? 1 : 0.5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: Layout.paneTitleBarHeight)
        .background(Theme.paneTitleBar)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ZStack {
            // Placeholder content based on pane type
            paneContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch pane.type {
        case .terminal(let terminalState):
            TerminalPaneView(paneId: pane.id, state: terminalState)
        case .browser(let state):
            BrowserPaneView(paneId: pane.id, state: state)
        case .fileExplorer(let state):
            FileExplorerView(paneId: pane.id, state: state)
        case .codeEditor(let state):
            CodeEditorWrapperView(paneId: pane.id, initialState: state)
        case .git(let state):
            GitPaneView(paneId: pane.id, repositoryURL: state.repositoryURL)
        case .diff(let state):
            DiffPaneView(paneId: pane.id, state: state)
        }
    }
}

// MARK: - Code Editor Wrapper

/// Wrapper that converts initial state to @State for the code editor
struct CodeEditorWrapperView: View {
    let paneId: UUID
    let initialState: CodeEditorPaneState

    @State private var editorState: CodeEditorState

    init(paneId: UUID, initialState: CodeEditorPaneState) {
        self.paneId = paneId
        self.initialState = initialState
        self._editorState = State(initialValue: CodeEditorState(
            fileURL: initialState.fileURL,
            content: initialState.content
        ))
    }

    var body: some View {
        CodeEditorPaneView(paneId: paneId, state: $editorState)
            .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
                saveActiveFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveAllFiles)) { _ in
                saveAllFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openFileInEditor)) { notification in
                handleOpenFileRequest(notification)
            }
    }

    private func handleOpenFileRequest(_ notification: Notification) {
        guard let request = notification.object as? OpenFileRequest,
              request.editorPaneId == paneId else { return }

        // Load file content
        let content = (try? String(contentsOf: request.fileURL, encoding: .utf8)) ?? ""

        // Open file in editor
        editorState.openFile(request.fileURL, content: content)
    }

    private func saveActiveFile() {
        guard let activeId = editorState.activeFileId else { return }
        do {
            try editorState.saveFile(activeId)
        } catch {
            print("Failed to save file: \(error.localizedDescription)")
        }
    }

    private func saveAllFiles() {
        do {
            try editorState.saveAllFiles()
        } catch {
            print("Failed to save files: \(error.localizedDescription)")
        }
    }
}

// MARK: - Hotkey Badge

/// Small badge showing the keyboard shortcut to focus this pane
struct HotkeyBadge: View {
    let index: Int

    var body: some View {
        Text("⌘\(index)")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .help("Press ⌘\(index) to focus this pane")
    }
}

// MARK: - Terminal Status Indicator

/// Shows running/idle status for terminal panes
/// - Green: Agent is running (generating output)
/// - Red: Needs input (waiting for you)
struct TerminalStatusIndicator: View {
    let isRunning: Bool

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .help(isRunning ? "Agent running" : "Needs input")
    }
}

// MARK: - Placeholder Content

/// Placeholder view for pane content before implementation
struct PlaceholderContent: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.2)

        PaneContainerView(
            pane: Pane(
                type: .terminal(TerminalState()),
                frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                title: "Terminal"
            )
        )
        .frame(width: 400, height: 300)
        .canvasState(CanvasState())
    }
    .frame(width: 500, height: 400)
}
