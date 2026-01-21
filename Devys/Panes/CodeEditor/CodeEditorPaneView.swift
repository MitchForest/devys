import SwiftUI
import AppKit
import CodeEditSourceEditor
import CodeEditLanguages

/// Code editor pane with syntax highlighting using CodeEditSourceEditor.
///
/// Supports multiple open files via tabs, dirty state tracking, and cursor position.
public struct CodeEditorPaneView: View {
    /// Pane ID for focus handling
    let paneId: UUID

    /// Editor state with open files
    @Binding var state: CodeEditorState

    /// Editor state object for cursor position etc.
    @State private var editorState = SourceEditorState()

    /// Editor configuration
    private var configuration: SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: DevysEditorTheme.theme,
                font: .monospacedSystemFont(ofSize: 12, weight: .regular),
                lineHeightMultiple: 1.3,
                wrapLines: false
            )
        )
    }

    public init(paneId: UUID, state: Binding<CodeEditorState>) {
        self.paneId = paneId
        self._state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Editor tab bar
            if state.fileCount > 1 {
                EditorTabBar(
                    files: state.openFiles,
                    activeFileId: state.activeFileId,
                    onSelect: { id in state.switchToFile(id) },
                    onClose: { id in state.closeFile(id) }
                )
            }

            // Editor content
            if let activeFile = state.activeFile,
               let fileIndex = state.activeFileIndex {
                editorView(for: activeFile, at: fileIndex)
            } else {
                emptyState
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusPane)) { notification in
            if let id = notification.object as? UUID, id == paneId {
                // Request focus for the editor
            }
        }
    }

    // MARK: - Editor View

    @ViewBuilder
    private func editorView(for file: OpenFile, at index: Int) -> some View {
        SourceEditor(
            Binding(
                get: { state.openFiles[index].content },
                set: { newValue in
                    state.updateContent(file.id, content: newValue)
                }
            ),
            language: file.language,
            configuration: configuration,
            state: $editorState
        )
        .overlay(alignment: .bottomTrailing) {
            statusBar(for: file)
        }
    }

    // MARK: - Status Bar

    private func statusBar(for file: OpenFile) -> some View {
        HStack(spacing: 12) {
            // Language indicator
            Text(file.language.id.rawValue.capitalized)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            // Cursor position
            if let positions = editorState.cursorPositions,
               let cursor = positions.first {
                Text("Ln \(cursor.start.line), Col \(cursor.start.column)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Dirty indicator
            if file.isDirty {
                Text("Modified")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No File Open")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Open a file from the File Explorer")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Devys Editor Theme

/// Provides a default editor theme for Devys
/// Uses explicit RGB colors to avoid crashes with NSColor.brightnessComponent
public enum DevysEditorTheme {
    public static var theme: EditorTheme {
        // Use explicit RGB colors - catalog colors like .textColor crash MinimapView
        let textColor = NSColor(calibratedRed: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
        let backgroundColor = NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
        let selectionColor = NSColor(calibratedRed: 0.3, green: 0.4, blue: 0.6, alpha: 0.5)
        let lineHighlightColor = NSColor(calibratedRed: 0.2, green: 0.2, blue: 0.25, alpha: 0.3)

        return EditorTheme(
            text: .init(color: textColor),
            insertionPoint: NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 1.0),
            invisibles: .init(color: NSColor(calibratedRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.3)),
            background: backgroundColor,
            lineHighlight: lineHighlightColor,
            selection: selectionColor,
            keywords: .init(color: NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.6, alpha: 1.0), bold: true),
            commands: .init(color: NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)),
            types: .init(color: NSColor(calibratedRed: 0.4, green: 0.8, blue: 0.8, alpha: 1.0)),
            attributes: .init(color: NSColor(calibratedRed: 0.8, green: 0.6, blue: 0.4, alpha: 1.0)),
            variables: .init(color: textColor),
            values: .init(color: NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)),
            numbers: .init(color: NSColor(calibratedRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)),
            strings: .init(color: NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)),
            characters: .init(color: NSColor(calibratedRed: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)),
            comments: .init(color: NSColor(calibratedRed: 0.4, green: 0.7, blue: 0.4, alpha: 1.0), italic: true)
        )
    }
}

// MARK: - Preview

#Preview("With File") {
    struct PreviewWrapper: View {
        @State var state = CodeEditorState(
            fileURL: URL(fileURLWithPath: "/test.swift"),
            content: """
            import Foundation

            struct Hello {
                let message: String

                func greet() {
                    print(message)
                }
            }
            """
        )

        var body: some View {
            CodeEditorPaneView(paneId: UUID(), state: $state)
                .frame(width: 600, height: 400)
        }
    }

    return PreviewWrapper()
}

#Preview("Empty") {
    struct PreviewWrapper: View {
        @State var state = CodeEditorState()

        var body: some View {
            CodeEditorPaneView(paneId: UUID(), state: $state)
                .frame(width: 600, height: 400)
        }
    }

    return PreviewWrapper()
}
