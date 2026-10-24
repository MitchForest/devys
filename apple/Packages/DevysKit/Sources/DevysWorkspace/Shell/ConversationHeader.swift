import ComposableArchitecture2
import Dependencies
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
    import PhotosUI
#endif

/// The conversation's header: a centred pill with the face (or project tile) and name, which
/// opens the employee's desk or the project's details as a popover; under a project's pill, the
/// records it keeps.
struct ConversationHeader: View {
    let store: StoreOf<Workspace>
    @State private var showsDetails = false

    var body: some View {
        VStack(spacing: 8) {
            HeaderPill(store: store) { showsDetails = true }
                .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                    PlaceDetails(store: store) { showsDetails = false }
                        .frame(width: 380, height: 560)
                        .background(DevysColors.sheet)
                }
            if case .project(let id) = store.place, let project = store.state.project(id), !project.items.isEmpty {
                ProjectPins(store: store, project: project)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }
}

/// The face and name of the conversation in a pill.
struct HeaderPill: View {
    let store: StoreOf<Workspace>
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let title = store.state.title(of: store.place)
        let opens = store.state.hasDetails
        Button(action: action) {
            HStack(spacing: 8) {
                picture
                Text(title).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink).lineLimit(1)
                    .contentTransition(.opacity)
                if opens {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                }
            }
            .padding(.leading, 5)
            .padding(.trailing, 12)
            .frame(height: 34)
            .background(hovering && opens ? DevysColors.sheetTint : DevysColors.sheet, in: Capsule())
            .overlay { Capsule().strokeBorder(DevysColors.hairline, lineWidth: 1) }
            .devysElevation(.resting)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!opens)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(opens ? "Shows the details" : "")
    }

    @ViewBuilder private var picture: some View {
        switch store.place {
        case .home:
            if let chief = store.chiefOfStaff {
                Portrait(store.state.portrait(for: chief), size: 24, mood: store.state.voiceMood ?? store.chiefOfStaffMood, isAnimated: false)
            }
        case .direct(let id):
            if let employee = store.state.employee(id) {
                Portrait(store.state.portrait(for: employee), size: 24, mood: store.state.mood(for: employee), isAnimated: false)
            }
        case .project(let id):
            BusinessTile(String(store.state.title(of: store.place).prefix(1)), tint: store.state.projectTint(id), size: 24)
        }
    }
}

extension Workspace.State {
    /// The header opens a desk (an employee's chat, Home's is the Chief of Staff's) or a project's
    /// details.
    package var hasDetails: Bool {
        switch place {
        case .home: chiefOfStaff != nil
        case .direct, .project: true
        }
    }
}

/// What the header opens: the employee's desk or the project's details.
struct PlaceDetails: View {
    let store: StoreOf<Workspace>
    let close: () -> Void

    var body: some View {
        switch store.place {
        case .home:
            if let chief = store.chiefOfStaff { Desk(store: store, employeeID: chief.id, close: close).id(chief.id) }
        case .direct(let id): Desk(store: store, employeeID: id, close: close).id(id)
        case .project(let id): Overview(store: store, projectID: id, close: close).id(id)
        }
    }
}

/// A project's kept records in a slim row under its pill, as Slack pins them; each opens as a layer.
private struct ProjectPins: View {
    let store: StoreOf<Workspace>
    let project: Project

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(project.items) { item in
                    let ref = store.state.currentRef(item.ref)
                    Button {
                        if let target = Records.open(ref) {
                            switch target {
                            case .layer(let layer): store.send(.layerOpened(layer))
                            case .place(let place): store.send(.placeSelected(place))
                            }
                        }
                    } label: {
                        Label(store.state.recordTitle(ref), systemImage: ref.recordKind == "documents/artifact" ? "doc.richtext" : "doc")
                            .font(DevysTypography.caption)
                            .foregroundStyle(DevysColors.ink2)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(DevysColors.sheetTint, in: Capsule())
                            .overlay { Capsule().strokeBorder(DevysColors.hairline, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from \(project.name)", systemImage: "pin.slash") { store.send(.projectItemRemoved(project.id, item.id)) }
                    }
                }
            }
            .padding(.horizontal, DevysSpacing.regular)
        }
        .scrollIndicators(.never)
        .frame(maxWidth: 760)
    }
}

/// The composer's +: a file from this device (uploaded into the business folder's Uploads) or a
/// business file or page, attached to the message being written.
struct AttachButton: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey
    @State private var choosing = false
    @State private var importing = false
    #if os(iOS)
        @State private var pickingPhoto = false
        @State private var photo: PhotosPickerItem?
    #endif

    var body: some View {
        let uploading = store.state.conversation(key)?.isUploading ?? false
        Menu {
            Button("Upload a file…", systemImage: "square.and.arrow.up") { importing = true }
            #if os(iOS)
                Button("Upload a photo…", systemImage: "photo") { pickingPhoto = true }
            #endif
            Button("A business file or page…", systemImage: "folder") { choosing = true }
        } label: {
            Group {
                if uploading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(DevysColors.ink2)
                }
            }
            .frame(width: 26, height: 26)
            .background(DevysColors.sheet, in: Circle())
            .overlay { Circle().strokeBorder(DevysColors.hairline, lineWidth: 1) }
            .contentShape(Circle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(uploading)
        .help("Attach a file")
        .accessibilityLabel("Attach a file")
        .sheet(isPresented: $choosing) {
            AttachFileSheet(store: store) { ref in
                choosing = false
                if let ref { store.send(.attachmentSet(key, ref)) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            store.send(.uploadChosen(key, ChosenFile(name: url.lastPathComponent, type: type, data: data)))
        }
        #if os(iOS)
            .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    defer { photo = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                    let kind = item.supportedContentTypes.first { $0.conforms(to: .image) } ?? .jpeg
                    let name = "Photo.\(kind.preferredFilenameExtension ?? "jpg")"
                    store.send(.uploadChosen(key, ChosenFile(name: name, type: kind.preferredMIMEType ?? "image/jpeg", data: data)))
                }
            }
        #endif
    }
}

/// Picks a page or a file in the business's folder to attach.
private struct AttachFileSheet: View {
    let store: StoreOf<Workspace>
    let done: (Ref?) -> Void
    @Dependency(\.filesClient) private var files
    @State private var folder: String?
    @State private var listing: (root: String, entries: [FileEntry])?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let folder, let root = listing?.root {
                    Button("Back", systemImage: "chevron.left") {
                        let parent = (folder as NSString).deletingLastPathComponent
                        self.folder = parent.count > root.count ? parent : nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
                Text("Attach a file").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                Spacer()
                Button("Cancel") { done(nil) }.buttonStyle(.quiet)
            }
            .padding(16)
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if folder == nil {
                        ForEach(pages) { page in
                            row(symbol: "doc.richtext", title: store.state.artifactName(page.id)) { done(.artifact(page.id)) }
                        }
                    }
                    if let problem {
                        EmptyNote(text: problem).padding(.top, 8)
                    } else if listing == nil {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 20)
                    }
                    ForEach(entries) { entry in
                        row(symbol: entry.kind == .directory ? "folder" : FileKind(entry.name).symbol, title: entry.name) {
                            if entry.kind == .directory { folder = entry.path } else { done(.file(entry.path)) }
                        }
                    }
                    if listing != nil, entries.isEmpty, pages.isEmpty {
                        Text("No files yet.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).padding(12)
                    }
                }
                .padding(8)
            }
        }
        .sheetFrame(width: 420, height: 460)
        .background(DevysColors.sheet)
        .task(id: folder ?? "") { await load() }
    }

    private var pages: [Artifact] {
        store.artifacts.filter { $0.contentType == "text/html" && $0.latestID == $0.id }.sorted { $0.createdAt > $1.createdAt }
    }

    private var entries: [FileEntry] {
        let atRoot = folder == nil
        return (listing?.entries ?? []).filter { entry in
            entry.kind != .repository && !entry.name.hasPrefix(".") && !(atRoot && machineFolders.contains(entry.name))
        }
    }

    private func row(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(DevysColors.ink2).accessibilityHidden(true)
                Text(title).font(DevysTypography.control).foregroundStyle(DevysColors.ink).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        problem = nil
        do {
            listing = try await files.list(store.businessID, folder)
        } catch DevysHTTPError.rejected(_, let message) where !message.isEmpty {
            listing = nil
            problem = message
        } catch {
            listing = nil
            problem = "The business's files couldn't be listed."
        }
    }
}
