import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The draft an approval shows (an email, a post, an invoice), drawn by its layer's own view in a
/// short, inert frame: what the owner approves, as it is now. Tapping it opens the layer.
struct DraftPreview: View {
    let store: StoreOf<Workspace>
    let ref: Ref

    /// A page shows its latest version: publishing again under its name changes the draft.
    private var current: Ref {
        guard case .artifact(let id) = ref, let page = store.artifacts.first(where: { $0.id == id }) else { return ref }
        return .artifact(page.latestID)
    }

    private var title: String {
        switch current {
        case .artifact(let id): store.artifacts.first { $0.id == id }?.filename ?? "Page"
        default: (current.id as NSString).lastPathComponent
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").foregroundStyle(DevysColors.indigo).accessibilityHidden(true)
                    Text(title).foregroundStyle(DevysColors.ink2).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("Open").foregroundStyle(DevysColors.ink3)
                }
                .font(DevysTypography.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
            ZStack {
                content.allowsHitTesting(false).accessibilityHidden(true)
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: open)
            }
            .frame(height: 160)
            .clipped()
        }
        .background(DevysColors.sheet)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DevysColors.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Draft: \(title)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var content: some View {
        switch current {
        case .artifact(let id):
            PublishedPage(businessID: store.businessID, artifactID: id).id(id)
        case .file(let path):
            FileView(store: store, file: FileEntry(name: (path as NSString).lastPathComponent, path: path, kind: .file))
        default:
            EmptyView()
        }
    }

    private func open() {
        if let layer = Layer(ref: current) { store.send(.layerOpened(layer)) }
    }
}

/// A file request's answer: the owner picks a file (a photo, on iPhone and iPad, when only images
/// will do), which goes into the business folder and answers the request with it.
struct ChooseFileButton: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    let accept: [String]
    let compact: Bool
    @State private var importing = false
    @State private var photo: PhotosPickerItem?

    /// The types the request accepts, as the system's file chooser names them.
    private var types: [UTType] {
        guard !accept.isEmpty else { return [.item] }
        return accept.map { type in
            switch type {
            case "image/*": .image
            case "video/*": .movie
            case "audio/*": .audio
            case "text/*": .text
            default: UTType(mimeType: type) ?? .item
            }
        }
    }

    private var onlyImages: Bool { !accept.isEmpty && accept.allSatisfy { $0.hasPrefix("image/") } }

    var body: some View {
        Group {
            #if os(iOS)
                if onlyImages {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }
                } else {
                    chooser
                }
            #else
                chooser
            #endif
        }
        .buttonStyle(DevysButtonStyle(.aurora, compact: compact))
        .help("Your file goes into the business's folder for this work.")
        .fileImporter(isPresented: $importing, allowedContentTypes: types) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            store.send(.fileChosen(decision.id, ChosenFile(name: url.lastPathComponent, type: type, data: data)))
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                defer { photo = nil }
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let kind = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
                let name = "Photo.\(kind.preferredFilenameExtension ?? "jpg")"
                store.send(.fileChosen(decision.id, ChosenFile(name: name, type: kind.preferredMIMEType ?? "image/jpeg", data: data)))
            }
        }
    }

    private var chooser: some View {
        Button("Choose file", systemImage: "doc.badge.plus") { importing = true }
    }
}
