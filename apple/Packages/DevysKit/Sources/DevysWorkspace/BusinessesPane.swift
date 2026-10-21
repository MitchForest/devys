import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Businesses: each business's name, brief and look, and new businesses.
struct BusinessesPane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        ListAndDetail {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(store.businesses) { business in
                    Button { store.send(.businessSelected(business.id)) } label: {
                        HStack(spacing: 10) {
                            Portrait(source(business), size: 24, isAnimated: false)
                            Text(business.name)
                            Spacer(minLength: 0)
                        }
                        .font(DevysTypography.control)
                        .foregroundStyle(DevysColors.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(store.selectedBusinessID == business.id ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button("New business…", systemImage: "plus") { store.send(.newBusinessTapped) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    .padding(.top, 8)
            }
        } detail: {
            if let business = store.businesses.first(where: { $0.id == store.selectedBusinessID }) {
                PaneScroll {
                    VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                        BusinessDetails(store: store, business: business)
                        LookEditor(
                            title: business.name,
                            current: business.look,
                            preview: source(business),
                            fallback: nil,
                            kind: .business(initial: business.initial, tint: business.tileTint),
                            set: { store.send(.lookSet(.business(business.id), $0)) },
                            photo: { store.send(.photoPicked(.business(business.id), $0)) }
                        )
                        ExportBusiness(business: business)
                    }
                }
            }
        }
        .padding(DevysSpacing.regular)
        .sheet(isPresented: Binding(get: { store.newBusiness != nil }, set: { if !$0 { store.send(.newBusinessCancelled) } })) {
            NewBusinessSheet(store: store)
        }
    }

    private func source(_ business: Business) -> PortraitSource {
        Workspace.State.portrait(for: business, photos: store.lookPhotos)
    }
}

/// A business's name and brief; every employee's instructions include the brief.
private struct BusinessDetails: View {
    let store: StoreOf<Preferences>
    let business: Business
    @State private var name = ""
    @State private var brief = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            FieldBox { TextField("Name", text: $name) }
            Text("Brief").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            FieldBox {
                TextField("Brief", text: $brief, axis: .vertical).lineLimit(4...10)
            }
            HStack {
                Text("What it does, its goals and constraints. Every employee reads it.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                Spacer()
                if name != business.name || brief != business.brief {
                    Button("Revert") { reset() }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    Button("Save") { store.send(.businessSaved(business.id, name: name, brief: brief)) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error = store.errorText {
                Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
            }
        }
        .onAppear(perform: reset)
        .onChange(of: business) { reset() }
    }

    private func reset() {
        name = business.name
        brief = business.brief
    }
}

/// Downloads everything the business has said and knows (`GET …/export`) and saves it where the
/// owner chooses.
private struct ExportBusiness: View {
    let business: Business
    @Dependency(\.runtimeClient) private var runtime
    @State private var file: ExportFile?
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your data").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            Button(busy ? "Exporting…" : "Export business data", systemImage: "square.and.arrow.down", action: export)
                .buttonStyle(DevysButtonStyle(.raised, compact: true))
                .disabled(busy)
            Text("\(business.name)'s conversations, memory and file index as one file. Credentials are left out, and saved files download separately.")
                .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                .fixedSize(horizontal: false, vertical: true)
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
            }
        }
        .fileExporter(
            isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
            document: file,
            contentType: ExportFile.type,
            defaultFilename: "devys-export.ndjson"
        ) { result in
            if case .failure(let error) = result { problem = error.localizedDescription }
        }
    }

    private func export() {
        busy = true
        problem = nil
        let id = business.id
        Task {
            do {
                file = ExportFile(data: try await runtime.exportBusiness(id))
            } catch {
                problem = failure("The export couldn't be downloaded.", error)
            }
            busy = false
        }
    }
}

/// A business export as a file to save.
private struct ExportFile: FileDocument {
    static let type = UTType(filenameExtension: "ndjson", conformingTo: .plainText) ?? .plainText
    static let readableContentTypes = [type]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// New business: a name, a brief, and the starting team hired with the Head of Operations.
/// The first business (`isFirst`) cannot be cancelled: there is nothing to go back to.
struct NewBusinessSheet: View {
    let store: StoreOf<Preferences>
    var isFirst = false

    var body: some View {
        if let draft = store.newBusiness {
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                Text(isFirst ? "Start your business" : "New business").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                FieldBox { TextField("Name", text: binding(\.name)) }
                FieldBox {
                    TextField("Brief: what it does, its goals and constraints", text: binding(\.brief), axis: .vertical).lineLimit(3...8)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Starting team").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                    Text("A Head of Operations always joins. Hire the others now or later.")
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                    ForEach(RoleTemplate.startingTeam, id: \.self) { template in
                        Toggle(RoleTemplate.displayName(template), isOn: Binding(
                            get: { draft.team.contains(template) },
                            set: { isOn in edit { if isOn { $0.team.insert(template) } else { $0.team.remove(template) } } }
                        ))
                        .toggleStyle(.switch)
                        .font(DevysTypography.control)
                    }
                }
                if let error = draft.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    if !isFirst {
                        Button("Cancel") { store.send(.newBusinessCancelled) }.buttonStyle(.quiet)
                    }
                    Button(draft.isSubmitting ? "Creating…" : "Create") { store.send(.createBusinessTapped) }
                        .buttonStyle(.aurora)
                        .disabled(!draft.canCreate)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DevysSpacing.roomy)
            .sheetFrame(width: 420, height: 440)
            .background(DevysColors.sheet)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<NewBusinessDraft, String>) -> Binding<String> {
        Binding(get: { store.newBusiness?[keyPath: keyPath] ?? "" }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func edit(_ change: (inout NewBusinessDraft) -> Void) {
        guard var draft = store.newBusiness else { return }
        change(&draft)
        store.send(.newBusinessEdited(draft))
    }
}

/// The Mac's Settings window has a fixed size, so tall panes scroll; on iPhone and iPad
/// the whole pane already scrolls.
/// A settings pane's list beside the selected item's details; where there isn't room for both
/// (a phone), the list sits above them.
struct ListAndDetail<List: View, Detail: View>: View {
    @ViewBuilder var list: List
    @ViewBuilder var detail: Detail

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DevysSpacing.roomy) {
                ScrollView { list }.frame(width: 200)
                detail.frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
                list
                detail
            }
        }
    }
}

struct PaneScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
            ScrollView { content }
        #else
            content
        #endif
    }
}
