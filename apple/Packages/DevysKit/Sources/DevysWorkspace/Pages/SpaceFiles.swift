import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The space's files: saved files (markdown opens inline) and files on the Mac, which open in
/// Files. Each file keeps one home; the space only shows it.
struct SpaceFiles: View {
    let store: StoreOf<Workspace>
    let space: Space

    var body: some View {
        let refs = space.refs(.artifact)
        let files = store.artifacts.filter { refs.contains($0.id) }
        let others = store.artifacts.filter { !refs.contains($0.id) }
        let onMac = space.items.filter { $0.kind == .file }
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            HStack {
                SectionHeader("Files", count: files.count + onMac.count)
                Spacer()
                if !others.isEmpty {
                    Menu {
                        ForEach(others) { file in
                            Button(file.filename) { store.send(.spaceItemAdded(space.id, .artifact, file.id)) }
                        }
                    } label: {
                        Label("Add file", systemImage: "plus")
                    }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    .fixedSize()
                }
            }
            if files.isEmpty && onMac.isEmpty {
                EmptyNote(text: "Files your employees save can be shown here, and any file in Files through Save to space.")
            }
            ForEach(onMac) { item in
                Button { store.send(.pageSelected(.files(item.ref))) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((item.ref as NSString).lastPathComponent).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                            Text("On the Mac").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(DevysColors.sheetTint, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove from space", systemImage: "minus.circle") { store.send(.spaceItemRemoved(space.id, item.id)) }
                }
            }
            ForEach(files) { file in
                FileRow(store: store, file: file) {
                    if let entry = space.items.first(where: { $0.kind == .artifact && $0.ref == file.id }) {
                        store.send(.spaceItemRemoved(space.id, entry.id))
                    }
                }
            }
        }
    }
}

private struct FileRow: View {
    let store: StoreOf<Workspace>
    let file: Artifact
    let remove: () -> Void
    @State private var open = false

    private var isMarkdown: Bool { file.contentType.hasPrefix("text/markdown") || file.filename.hasSuffix(".md") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: isMarkdown ? "doc.richtext" : "doc").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(file.filename).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteLength), countStyle: .file))
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                }
                Spacer()
                if isMarkdown {
                    Button(open ? "Close" : "Open") {
                        open.toggle()
                        if open { store.send(.artifactOpened(file.id)) }
                    }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
            }
            if open {
                switch store.artifactTexts[file.id] {
                case .loaded(let text): MarkdownView(text)
                case .failed(let message): EmptyNote(text: message)
                default: ProgressView()
                }
            }
        }
        .padding(10)
        .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu { Button("Remove from space", systemImage: "minus.circle", action: remove) }
    }
}
