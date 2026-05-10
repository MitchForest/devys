// MarkdownReaderView.swift
// Markdown reading surface for .md / .mdx / .txt files in the mini IDE.

#if os(macOS)
import AppKit
import ComposableArchitecture
import Editor
import SwiftUI
import UI

struct ReaderTabRootView: View {
    let fileURL: URL
    let projectRootURL: URL?
    let session: EditorPreviewSession
    let store: StoreOf<ReaderTabFeature>
    let drawerStore: StoreOf<ProjectDrawerFeature>
    let appCommandSink: AppWindowCommandSink
    let onDirtyStateChange: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(
        fileURL: URL,
        projectRootURL: URL?,
        session: EditorPreviewSession,
        store: StoreOf<ReaderTabFeature>,
        drawerStore: StoreOf<ProjectDrawerFeature>,
        appCommandSink: AppWindowCommandSink,
        onDirtyStateChange: @escaping (Bool) -> Void
    ) {
        self.fileURL = fileURL
        self.projectRootURL = projectRootURL
        self.session = session
        self.store = store
        self.drawerStore = drawerStore
        self.appCommandSink = appCommandSink
        self.onDirtyStateChange = onDirtyStateChange
    }

    var body: some View {
        let theme = DevysThemeRegistry.theme(for: .system, systemColorScheme: colorScheme)

        ZStack {
            WindowVibrancyBackground()
                .ignoresSafeArea()
            theme.base.opacity(0.36)
                .ignoresSafeArea()

            ProjectDrawerRootView(projectRootURL: projectRootURL, store: drawerStore, appCommandSink: appCommandSink) {
                VStack(spacing: 0) {
                    readerHeader
                    Divider()
                    content(for: store.mode)
                }
            }
        }
        .environment(\.theme, theme)
        .background(modeShortcut)
        .task(id: fileURL) {
            session.open(fileURL)
        }
        .onChange(of: session.document?.isDirty == true, initial: true) { _, isDirty in
            store.send(.dirtyStateChanged(isDirty))
            onDirtyStateChange(isDirty)
        }
        .onChange(of: session.document?.content, initial: true) { _, content in
            guard let content else { return }
            store.send(.documentContentChanged(content))
        }
    }

    private var readerHeader: some View {
        HStack(spacing: Spacing.relaxed) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.fileURL.lastPathComponent.isEmpty ? store.fileURL.path : store.fileURL.lastPathComponent)
                    .font(Typography.body.weight(.semibold))
                    .lineLimit(1)
                Text(store.relativePath)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            if store.isDirty {
                HStack(spacing: Spacing.tight) {
                    StatusDot(.waiting, size: 7)
                    Text("Unsaved")
                        .font(Typography.caption)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Unsaved changes")
            }
            GlassSegmentedControl(
                selection: Binding(
                    get: { store.mode },
                    set: { store.send(.modeChanged($0)) }
                ),
                options: [
                    .init(value: .read, label: "Read", symbol: "text.alignleft"),
                    .init(value: .edit, label: "Edit", symbol: "curlybraces")
                ]
            )
            .frame(width: 190)
            Button {
                store.send(.revealInFinderRequested)
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal in Finder")
        }
        .padding(.horizontal, Spacing.relaxed)
        .padding(.vertical, Spacing.comfortable)
    }

    @ViewBuilder
    private func content(for mode: ReaderMode) -> some View {
        switch mode {
        case .read:
            renderedReader
        case .edit:
            editorReader
        }
    }

    private var renderedReader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.relaxed) {
                if session.document != nil {
                    if store.blocks.isEmpty {
                        Text("No content")
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.blocks) { block in
                            renderedBlock(block)
                        }
                    }
                } else if case .failed(let message) = session.phase {
                    Text(message)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.spacious)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, Spacing.spacious)
            .padding(.vertical, Spacing.spacious)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func renderedBlock(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level, let attributed):
            Text(attributed)
                .font(headingFont(for: level))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? Spacing.normal : Spacing.tight)

        case .prose(let attributed):
            Text(attributed)
                .font(Typography.body)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let attributed, let depth):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.normal) {
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth) * Spacing.relaxed)
                }
                Text("•")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .leading)
                Text(attributed)
                    .font(Typography.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .numbered(let marker, let attributed, let depth):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.normal) {
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth) * Spacing.relaxed)
                }
                Text(marker)
                    .font(Typography.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
                Text(attributed)
                    .font(Typography.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .blockquote(let attributed):
            HStack(alignment: .top, spacing: Spacing.normal) {
                RoundedRectangle(cornerRadius: Spacing.borderWidth, style: .continuous)
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(attributed)
                    .font(Typography.body.italic())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Spacing.tight)

        case .code(let body):
            Text(body)
                .font(Typography.Code.sm)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.relaxed)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.radius, style: .continuous)
                        .fill(.quaternary.opacity(0.4))
                )

        case .horizontalRule:
            Divider()
                .padding(.vertical, Spacing.tight)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return Typography.display
        case 2: return Typography.title
        case 3: return Typography.Chat.heading
        case 4: return Typography.heading
        default: return Typography.heading
        }
    }

    @ViewBuilder
    private var editorReader: some View {
        if let document = session.document {
            let codeViewDesign = CodeViewDesign.resolved(for: colorScheme)
            EditorView(
                document: document,
                isEditable: true,
                usesGlassBackground: codeViewDesign.surfaceDesign.usesGlassBackground
            )
            .padding(Spacing.comfortable)
        } else {
            switch session.phase {
            case .failed(let message):
                ContentUnavailableView("Cannot Open Markdown", systemImage: "exclamationmark.triangle", description: Text(message))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .preview(let preview) where preview.isBinary:
                ContentUnavailableView("Binary File", systemImage: "doc", description: Text(store.relativePath))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .preview(let preview) where preview.isTooLarge:
                ContentUnavailableView("File Too Large", systemImage: "doc.text.magnifyingglass", description: Text(tooLargeMessage(for: preview)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle, .loading, .preview, .loaded:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var modeShortcut: some View {
        Button {
            store.send(.toggleMode)
        } label: {
            EmptyView()
        }
        .keyboardShortcut("e", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func tooLargeMessage(for preview: LoadedDocumentPreview) -> String {
        guard let fileSize = preview.revision.fileSize else {
            return "\(store.relativePath) exceeds the preview limit."
        }
        let fileSizeLabel = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        let limitLabel = ByteCountFormatter.string(fromByteCount: Int64(preview.maxBytes), countStyle: .file)
        return "\(fileSizeLabel) exceeds \(limitLabel)."
    }
}

#endif
