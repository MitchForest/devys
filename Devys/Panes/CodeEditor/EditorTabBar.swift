import SwiftUI

/// Tab bar for switching between multiple open files in the code editor.
public struct EditorTabBar: View {
    let files: [OpenFile]
    let activeFileId: UUID?
    let onSelect: (UUID) -> Void
    let onClose: (UUID) -> Void

    public init(
        files: [OpenFile],
        activeFileId: UUID?,
        onSelect: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.files = files
        self.activeFileId = activeFileId
        self.onSelect = onSelect
        self.onClose = onClose
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(files) { file in
                    EditorTab(
                        file: file,
                        isActive: file.id == activeFileId,
                        onSelect: { onSelect(file.id) },
                        onClose: { onClose(file.id) }
                    )
                }
            }
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Editor Tab

/// Single tab representing an open file.
struct EditorTab: View {
    let file: OpenFile
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            // File icon
            Image(systemName: fileIcon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)

            // File name with dirty indicator
            Text(file.name)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? .primary : .secondary)

            // Dirty indicator or close button
            Button(action: onClose) {
                ZStack {
                    // Dirty dot (shown when not hovered)
                    if file.isDirty && !isHovered {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                    }

                    // Close button (shown on hover)
                    if isHovered {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tabBackground)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Close") { onClose() }
            Button("Close Others") {
                // TODO: Implement close others
            }
            Divider()
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(
                    file.url.path,
                    inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path
                )
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(file.url.path, forType: .string)
            }
        }
    }

    private var tabBackground: some View {
        Group {
            if isActive {
                Color(nsColor: .controlBackgroundColor)
            } else if isHovered {
                Color.gray.opacity(0.1)
            } else {
                Color.clear
            }
        }
    }

    private var fileIcon: String {
        switch file.fileExtension {
        case "swift": return "swift"
        case "js", "jsx", "ts", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces.square"
        case "md": return "doc.text"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        default: return "doc"
        }
    }

    private var iconColor: Color {
        switch file.fileExtension {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "py": return .green
        case "json": return .gray
        case "md": return .purple
        case "html", "htm": return .orange
        case "css", "scss": return .pink
        default: return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    let files = [
        OpenFile(url: URL(fileURLWithPath: "/test/App.swift"), content: ""),
        OpenFile(url: URL(fileURLWithPath: "/test/ContentView.swift"), content: "", isDirty: true),
        OpenFile(url: URL(fileURLWithPath: "/test/package.json"), content: "")
    ]

    VStack(spacing: 0) {
        EditorTabBar(
            files: files,
            activeFileId: files[1].id,
            onSelect: { _ in },
            onClose: { _ in }
        )

        Color.gray.opacity(0.2)
    }
    .frame(width: 500, height: 300)
}
