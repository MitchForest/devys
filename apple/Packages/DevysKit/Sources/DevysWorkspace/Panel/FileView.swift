import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import DevysSurfaces
import PDFKit
import QuickLook
import SwiftUI
#if os(macOS)
import Quartz
#endif

/// Which viewer a file opens in, from its name.
enum FileKind {
    case markdown, pdf, office, sheet, whiteboard, image, text, other

    init(_ name: String) {
        let ext = name.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        switch ext {
        case "md", "markdown": self = .markdown
        case "pdf": self = .pdf
        case "xlsx", "xls", "csv": self = .sheet
        case "excalidraw": self = .whiteboard
        case "docx", "doc", "pptx", "ppt", "key", "pages", "numbers", "rtf": self = .office
        case "png", "jpg", "jpeg", "gif", "webp", "heic": self = .image
        case "txt", "json", "ts", "tsx", "js", "jsx", "css", "html", "yml", "yaml", "toml", "sql", "sh", "swift", "py", "rb", "go", "rs", "xml", "log":
            self = .text
        default: self = name.contains(".") ? .other : .text
        }
    }
}

/// A file as it was read: its text or bytes, and the revision a save goes over.
private enum Loaded: Equatable {
    case text(FileText)
    case bytes(FileBytes)

    var revision: String {
        switch self {
        case .text(let text): text.revision
        case .bytes(let bytes): bytes.revision
        }
    }
}

/// Where a deck's PowerPoint copy goes: beside it, with the same name (as on the web).
func pptxPath(_ path: String) -> String {
    path.replacingOccurrences(of: #"(\.slides)?\.(md|markdown)$"#, with: "", options: [.regularExpression, .caseInsensitive]) + ".pptx"
}

/// A file in the business's folder on the owner's Mac, as a layer. Documents, decks, spreadsheets
/// and whiteboards edit in place through the web surfaces and save over the revision they were
/// opened at; PDFs open in PDFKit, Office and iWork files in QuickLook. Comments on a text range
/// or a PDF selection go to an employee.
struct FileView: View {
    let store: StoreOf<Workspace>
    let file: FileEntry
    @Dependency(\.filesClient) private var files
    @State private var loaded: Loaded?
    // Changes when the file is replaced from outside, as after a conflict, so editors reload.
    @State private var version = "first"
    /// The edited markdown; spreadsheets and whiteboards are written out only on Save.
    @State private var draft: String?
    @State private var edited = false
    @State private var deck = false
    @State private var conflict = false
    @State private var problem: String?
    /// A save, reload or export that failed; the file stays open.
    @State private var actionError: String?
    @State private var selection: FileAnchor?
    @State private var comments: [FileComment] = []
    @State private var saved: String?
    @State private var surface = SurfaceHandle()

    private var kind: FileKind { FileKind(file.name) }
    private var editable: Bool { kind == .markdown || kind == .sheet || kind == .whiteboard }

    var body: some View {
        VStack(spacing: 0) {
            // What can be done to the file; the layer's header already names it.
            if editable || deck {
                HStack(spacing: 8) {
                    if editable {
                        Text(edited ? "Edited" : saved.map { "Saved \($0)" } ?? "Saved on the Mac")
                            .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    }
                    Spacer(minLength: 4)
                    if deck {
                        Button("Export .pptx", systemImage: "rectangle.on.rectangle") { Task { await exportDeck() } }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    }
                    if editable {
                        Button("Save", systemImage: "square.and.arrow.down") { Task { await save() } }
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                            .disabled(!edited)
                            .keyboardShortcut("s", modifiers: .command)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            if let actionError {
                Text(actionError)
                    .font(DevysTypography.caption).foregroundStyle(DevysColors.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            if conflict {
                HStack(spacing: 8) {
                    Text("This file changed on the Mac since you opened it.").font(DevysTypography.body)
                    Button("Load the newer version") { Task { await reload() } }
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    Button("Keep mine") { Task { await save(overwrite: true) } }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DevysColors.sheetTint)
            }
            Divider()
            viewer.frame(maxWidth: .infinity, maxHeight: .infinity)
            if (kind == .markdown && !deck) || kind == .pdf {
                Divider()
                CommentBar(store: store, path: file.path, selection: $selection, comments: $comments).padding(10)
            }
        }
        .task(id: file.path) { await load() }
    }

    @ViewBuilder private var viewer: some View {
        if let problem {
            EmptyNote(text: problem).padding(20)
        } else {
            switch (kind, loaded) {
            case (.markdown, .text(let text)):
                SurfaceView(
                    .markdown(text.content, name: file.name, version: version),
                    onChange: { next in
                        draft = next == text.content ? nil : next
                        edited = draft != nil
                    },
                    onSelectText: { picked in selection = picked.map { .text(start: $0.start, end: $0.end, quote: $0.quote) } },
                    onDeck: { deck = true },
                    handle: surface
                )
            case (.text, .text(let text)):
                SurfaceView(.code(name: file.name, contents: text.content))
            case (.whiteboard, .text(let text)):
                SurfaceView(.whiteboard(text.content, version: version), onEdited: { edited = true }, handle: surface)
            case (.sheet, .bytes(let bytes)):
                SurfaceView(.sheet(bytes.data, name: file.name, version: version), onEdited: { edited = true }, handle: surface)
            case (.pdf, .bytes(let bytes)):
                PDFDocumentView(data: bytes.data) { selection = $0 }
            case (.image, .bytes(let bytes)):
                ImageView(data: bytes.data)
            case (.office, .bytes(let bytes)), (.other, .bytes(let bytes)):
                QuickLookView(data: bytes.data, name: file.name)
            default:
                EmptyView()
            }
        }
    }

    private func read() async throws -> Loaded {
        switch kind {
        case .markdown, .text, .whiteboard: .text(try await files.text(store.businessID, file.path))
        default: .bytes(try await files.bytes(store.businessID, file.path))
        }
    }

    private func load() async {
        do {
            loaded = try await read()
        } catch {
            problem = failure("This file couldn't be opened.", error)
        }
    }

    private func reload() async {
        guard let newer = try? await read() else {
            actionError = "The newer version couldn't be loaded."
            return
        }
        actionError = nil
        loaded = newer
        draft = nil
        edited = false
        conflict = false
        version = newer.revision
    }

    /// The edited file: the markdown draft, or what the editor writes out.
    private func written() async -> SurfaceFile? {
        if kind == .markdown { return draft.map(SurfaceFile.text) }
        return await surface.serialize()
    }

    private func save(overwrite: Bool = false) async {
        guard let loaded, let content = await written() else { return }
        // Keeping mine saves over whatever is on the Mac now.
        let revision = overwrite ? ((try? await read())?.revision ?? loaded.revision) : loaded.revision
        let result: FileSave?
        switch content {
        case .text(let text): result = try? await files.save(store.businessID, file.path, text, revision)
        case .bytes(let data): result = try? await files.saveBytes(store.businessID, file.path, data, .revision(revision))
        }
        switch result {
        case .saved(let revision):
            switch content {
            case .text(let text): self.loaded = .text(FileText(path: file.path, content: text, revision: revision))
            case .bytes(let data): self.loaded = .bytes(FileBytes(data: data, revision: revision))
            }
            draft = nil
            edited = false
            conflict = false
            saved = Date.now.formatted(date: .omitted, time: .shortened)
            actionError = nil
        case .conflict:
            conflict = true
        case nil:
            actionError = "The file couldn't be saved. Your changes are still here."
        }
    }

    private func exportDeck() async {
        guard let data = await surface.exportDeck() else {
            actionError = "The deck couldn't be exported."
            return
        }
        let target = pptxPath(file.path)
        if case .saved = try? await files.saveBytes(store.businessID, target, data, .overwrite) {
            saved = "· exported \((target as NSString).lastPathComponent)"
            actionError = nil
        } else {
            actionError = "The PowerPoint copy couldn't be saved."
        }
    }
}

/// Comments in progress on a file and who they go to.
private struct CommentBar: View {
    let store: StoreOf<Workspace>
    let path: String
    @Binding var selection: FileAnchor?
    @Binding var comments: [FileComment]
    @Dependency(\.filesClient) private var files
    @State private var text = ""
    @State private var recipient: String?
    @State private var problem: String?

    var body: some View {
        let employees = store.snapshot.employees
        VStack(alignment: .leading, spacing: 8) {
            if let selection {
                HStack(spacing: 8) {
                    Text(describe(selection)).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    FieldBox { TextField("Comment on this", text: $text).onSubmit(add) }
                    Button("Add", action: add).buttonStyle(DevysButtonStyle(.raised, compact: true))
                    // The owner edits by asking: the passage goes into the conversation's composer.
                    if case .text(_, _, let quote) = selection {
                        Button("Ask", systemImage: "quote.bubble") {
                            store.send(.askTapped(quote))
                            self.selection = nil
                        }
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    }
                }
            }
            if !comments.isEmpty {
                HStack(spacing: 8) {
                    Text("\(comments.count) comment\(comments.count == 1 ? "" : "s") for").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    Picker("Send to", selection: Binding(get: { recipient ?? employees.first?.id ?? "" }, set: { recipient = $0 })) {
                        ForEach(employees) { Text($0.name).tag($0.id) }
                        // Or a work item's thread, addressed to its owner.
                        ForEach((store.work.value ?? []).filter(\.state.isOpen)) { item in
                            Text("Thread: \(item.title)").tag("work:\(item.id)")
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Send", systemImage: "paperplane") { send(defaultTo: employees.first?.id) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
            }
            if let problem { Text(problem).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2) }
        }
    }

    private func send(defaultTo first: String?) {
        guard let employee = recipient ?? first else { return }
        let sending = comments
        Task {
            do {
                try await files.comment(store.businessID, path, employee, sending)
                comments = []
                problem = nil
            } catch {
                problem = "The comments couldn't be sent. They're still here."
            }
        }
    }

    private func add() {
        guard let selection, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        comments.append(FileComment(anchor: selection, text: text))
        text = ""
        self.selection = nil
    }

    private func describe(_ anchor: FileAnchor) -> String {
        switch anchor {
        case .text(_, _, let quote): "“\(quote.prefix(60))”"
        case .pdf(let page, _): "Page \(page) selection"
        }
    }
}

/// A PDF in PDFKit. Selecting text marks it for a comment, as page regions in points from the
/// page's top left, the same as on the web.
private struct PDFDocumentView {
    let data: Data
    let onSelect: (FileAnchor?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeView(_ coordinator: Coordinator) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        NotificationCenter.default.addObserver(coordinator, selector: #selector(Coordinator.selectionChanged(_:)), name: .PDFViewSelectionChanged, object: view)
        return view
    }

    final class Coordinator: NSObject {
        let onSelect: (FileAnchor?) -> Void
        init(onSelect: @escaping (FileAnchor?) -> Void) { self.onSelect = onSelect }

        @objc func selectionChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let selection = view.currentSelection,
                  let page = selection.pages.first, let document = view.document
            else { return onSelect(nil) }
            let height = page.bounds(for: .mediaBox).height
            let bounds = selection.bounds(for: page)
            // PDF space starts at the bottom left; comments measure from the top left.
            let rect = CGRect(x: bounds.minX, y: height - bounds.maxY, width: bounds.width, height: bounds.height)
            onSelect(.pdf(page: document.index(for: page) + 1, rects: [rect]))
        }
    }
}

#if os(macOS)
extension PDFDocumentView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView { makeView(context.coordinator) }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#else
extension PDFDocumentView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView { makeView(context.coordinator) }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#endif

/// Office, iWork and other documents, read-only, through QuickLook from a temporary copy.
private struct QuickLookView {
    let data: Data
    let name: String

    var url: URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "devys-files", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(abs(data.hashValue))-\(name)")
        if !FileManager.default.fileExists(atPath: file.path) { try? data.write(to: file) }
        return file
    }
}

#if os(macOS)
extension QuickLookView: NSViewRepresentable {
    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        return view
    }
    func updateNSView(_ view: QLPreviewView, context: Context) {}
}
#else
extension QuickLookView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Source { Source(url: url) }

    final class Source: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
#endif

private struct ImageView: View {
    let data: Data

    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit().padding() }
        #else
        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().padding() }
        #endif
    }
}
