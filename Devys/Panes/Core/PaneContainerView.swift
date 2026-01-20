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
            CodeEditorPlaceholderView(state: state)
        case .git:
            PlaceholderContent(
                icon: "arrow.triangle.branch",
                title: "Git",
                subtitle: "Sprint 10"
            )
        }
    }
}

// MARK: - Code Editor Placeholder

/// Temporary placeholder for code editor (full implementation in Sprint 10)
struct CodeEditorPlaceholderView: View {
    let state: CodeEditorPaneState

    var body: some View {
        VStack(spacing: 0) {
            if let url = state.fileURL {
                // Show file path bar
                HStack {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(url.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))

                Divider()
            }

            // Show content as read-only text
            ScrollView {
                Text(state.content.isEmpty ? "Empty file" : state.content)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
