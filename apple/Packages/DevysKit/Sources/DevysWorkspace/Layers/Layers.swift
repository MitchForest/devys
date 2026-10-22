import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The layer on top of the right panel.
struct LayerView: View {
    let store: StoreOf<Workspace>
    let layer: Layer

    var body: some View {
        switch layer {
        case .artifact(let id, let updatedBy):
            ArtifactLayer(store: store, artifactID: id, updatedBy: updatedBy)
        case .file(let path):
            // A finished turn reads the file again: an employee may have just changed it.
            FileView(store: store, file: FileEntry(name: (path as NSString).lastPathComponent, path: path, kind: .file))
                .id("\(path):\(store.turns)")
        case .app(let id):
            switch id {
            case "documents": DocumentsApp(store: store)
            case "code": CodeApp(store: store)
            // An app with no view on this client shows nothing of its own.
            default: EmptyNote(text: "This app has nothing to show here yet.").padding(14)
            }
        case .session(let workID, let sessionID):
            SessionLayer(store: store, workID: workID, sessionID: sessionID)
        case .browser(let workID):
            BrowserLayer(store: store, workID: workID)
        case .routine(let id):
            RoutineLayer(store: store, routineID: id)
        case .remoteApp(let id):
            RemoteAppLayer(store: store, appID: id)
        }
    }
}

/// A page an employee published, following its versions: a new version arriving in the
/// conversation replaces the one on screen and says who changed it.
private struct ArtifactLayer: View {
    let store: StoreOf<Workspace>
    let artifactID: String
    let updatedBy: String?

    var body: some View {
        let current = store.artifacts.first { $0.id == artifactID }
        let versions = current.map { page in store.artifacts.filter { $0.filename == page.filename }.sorted { $0.createdAt < $1.createdAt } } ?? []
        let index = versions.firstIndex { $0.id == artifactID } ?? 0
        VStack(spacing: 0) {
            if versions.count > 1 || updatedBy != nil {
                HStack(spacing: 6) {
                    if versions.count > 1 {
                        Button("Earlier version", systemImage: "chevron.left") { store.send(.layerReplaced(.artifact(versions[index - 1].id))) }
                            .disabled(index == 0)
                        Text("v\(index + 1) of \(versions.count)").monospacedDigit()
                        Button("Later version", systemImage: "chevron.right") { store.send(.layerReplaced(.artifact(versions[index + 1].id))) }
                            .disabled(index >= versions.count - 1)
                    }
                    if let updatedBy {
                        Text("Updated by \(updatedBy)").foregroundStyle(DevysColors.indigo).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(DevysTypography.caption)
                .foregroundStyle(DevysColors.ink3)
                .padding(.horizontal, 12)
                .frame(height: 36)
                Rectangle().fill(DevysColors.hairline).frame(height: 1)
            }
            PublishedPage(businessID: store.businessID, artifactID: artifactID).id(artifactID)
        }
    }
}

/// The business folder's machine folders, hidden at its root: repositories the Code app shows and
/// coding worktrees nobody browses (the Mac host lays them out: src/apps/code/host/worktree.ts).
/// The same list as the web's Documents app.
private let repositoriesFolder = "repos"
private let machineFolders: Set<String> = [repositoriesFolder, "worktrees"]

/// The Documents app: the business's pages and documents, filterable by project. Repositories
/// belong to Code and never show here.
private struct DocumentsApp: View {
    let store: StoreOf<Workspace>
    @Dependency(\.filesClient) private var files
    @State private var projectID: String?
    @State private var folder: String?
    @State private var listing: (root: String, entries: [FileEntry])?
    @State private var problem: String?

    var body: some View {
        let projects = store.projects.value ?? []
        let chosen = projects.first { $0.id == projectID }
        VStack(spacing: 0) {
            if !projects.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        chip("All", selected: projectID == nil) { projectID = nil }
                        ForEach(projects) { project in chip(project.name, selected: projectID == project.id) { projectID = project.id } }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.never)
                Rectangle().fill(DevysColors.hairline).frame(height: 1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pages(chosen)
                    if let chosen { kept(chosen) } else { folderGroup }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
        }
        .task(id: "\(store.businessID):\(folder ?? "")") { await load() }
    }

    @ViewBuilder private func pages(_ chosen: Project?) -> some View {
        let artifacts = store.artifacts
        // One row per page: its latest version, kept in the chosen project when there is one.
        let pages = artifacts
            .filter { page in page.contentType == "text/html" && page.latestID == page.id }
            .filter { page in chosen.map { store.state.keptEntry(of: .artifact(page.id), in: $0) != nil } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
        if !pages.isEmpty {
            group("Pages") {
                ForEach(pages) { page in
                    EntryRow(symbol: "doc.richtext", tint: DevysColors.indigo, title: store.state.artifactName(page.id), detail: ServerDate.parse(page.createdAt)?.formatted(date: .abbreviated, time: .omitted)) {
                        store.send(.layerOpened(.artifact(page.id)))
                    }
                }
            }
        }
    }

    @ViewBuilder private func kept(_ project: Project) -> some View {
        let files = project.items.compactMap { item in if case .file(let path) = Layer(ref: item.ref) { (id: item.id, path: path) } else { nil } }
        if !files.isEmpty {
            group("Files") {
                ForEach(files, id: \.id) { item in
                    EntryRow(symbol: "doc", title: (item.path as NSString).lastPathComponent, detail: item.path) { store.send(.layerOpened(.file(item.path))) }
                }
            }
        }
    }

    private var folderGroup: some View {
        let root = listing?.root ?? ""
        let atRoot = folder == nil
        let entries = (listing?.entries ?? []).filter { entry in
            entry.kind != .repository && !entry.name.hasPrefix(".") && !(atRoot && machineFolders.contains(entry.name))
        }
        let title = folder.map { String($0.dropFirst(root.count + 1)) }.flatMap { $0.isEmpty ? nil : $0 } ?? "Files"
        return group(title, parent: folder.map { current in
            {
                let parent = (current as NSString).deletingLastPathComponent
                folder = parent.count > root.count ? parent : nil
            }
        }) {
            if let problem {
                EmptyNote(text: problem)
            } else if listing == nil {
                ProgressView().controlSize(.small)
            } else if entries.isEmpty {
                Text("Documents your employees write appear here.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            ForEach(entries) { entry in
                EntryRow(symbol: entry.kind == .directory ? "folder" : FileKind(entry.name).symbol, title: entry.name) {
                    if entry.kind == .directory { folder = entry.path } else { store.send(.layerOpened(.file(entry.path))) }
                }
            }
        }
    }

    /// Lists the folder on screen; a failure says why instead of showing an empty folder.
    private func load() async {
        problem = nil
        do {
            listing = try await files.list(store.businessID, folder)
        } catch DevysHTTPError.rejected(_, let message) where !message.isEmpty {
            // The server says why, e.g. files run in local mode only.
            listing = nil
            problem = message
        } catch {
            listing = nil
            problem = failure("The business's files couldn't be listed.", error)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DevysTypography.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? DevysColors.sheet : DevysColors.ink2)
                .background(selected ? DevysColors.ink : DevysColors.sheetTint, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The Code app: repositories, the work being coded (each opening its thread), terminals,
/// and a coding session the owner drives from the start.
private struct CodeApp: View {
    let store: StoreOf<Workspace>
    @Dependency(\.filesClient) private var files
    @Dependency(\.codingClient) private var coding
    @State private var repositories: [FileEntry] = []
    @State private var withSessions: [String] = []
    @State private var starting = false

    var body: some View {
        let work = (store.work.value ?? []).filter { withSessions.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button("New coding session", systemImage: "chevron.left.forwardslash.chevron.right") { starting = true }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    .fixedSize()
                if !repositories.isEmpty {
                    group("Repositories") {
                        ForEach(repositories) { EntryRow(symbol: "arrow.triangle.branch", title: $0.name, detail: $0.path) }
                    }
                }
                if !work.isEmpty {
                    group("Work") {
                        ForEach(work) { item in
                            EntryRow(symbol: item.state.isOpen ? "circle.fill" : "circle", tint: item.state.isOpen ? DevysColors.indigo : DevysColors.gray, title: item.title) {
                                store.send(.threadOpened(item.id))
                            } trailing: {
                                item.state.chip(size: .small)
                            }
                        }
                    }
                }
                TerminalsSection(businessID: store.businessID)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .sheet(isPresented: $starting) { NewCodingSessionSheet(store: store, isPresented: $starting) }
        .task(id: store.businessID) {
            let businessID = store.businessID
            async let coded = coding.work(businessID)
            // Repositories are created in `<root>/repos`.
            if let root = try? await files.list(businessID, nil).root {
                repositories = ((try? await files.list(businessID, "\(root)/\(repositoriesFolder)"))?.entries ?? []).filter { $0.kind == .repository }
            }
            withSessions = (try? await coded) ?? []
        }
    }
}

private func group(_ title: String, parent: (() -> Void)? = nil, @ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
            if let parent {
                Button("Up a folder", systemImage: "chevron.left", action: parent).labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(DevysColors.ink3)
            }
            Text(title).font(DevysTypography.label).foregroundStyle(DevysColors.ink3).lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        content()
    }
}

/// One record in an app's layer; rows without an action are listed only.
private struct EntryRow<Trailing: View>: View {
    let symbol: String
    var tint = DevysColors.ink3
    let title: String
    var detail: String?
    var open: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        Button { open?() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(tint).frame(width: 16).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink).lineLimit(1)
                    if let detail { Text(detail).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1).truncationMode(.head) }
                }
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering && open != nil ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(open == nil)
        .onHover { hovering = $0 }
    }
}

extension EntryRow where Trailing == EmptyView {
    init(symbol: String, tint: Color = DevysColors.ink3, title: String, detail: String? = nil, open: (() -> Void)? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail, open: open) { EmptyView() }
    }
}

extension FileKind {
    var symbol: String {
        switch self {
        case .markdown: "doc.richtext"
        case .pdf: "doc.text"
        case .image: "photo"
        case .office: "doc"
        case .sheet: "tablecells"
        case .whiteboard: "scribble"
        case .text: "chevron.left.forwardslash.chevron.right"
        case .other: "doc"
        }
    }
}
