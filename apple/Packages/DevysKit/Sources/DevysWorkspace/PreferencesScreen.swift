import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings: in the Settings window on macOS (`SettingsWindow`), a sheet on iPhone and iPad.
struct PreferencesScreen: View {
    let store: StoreOf<Preferences>
    var onDone: (() -> Void)?
    #if os(iOS)
        @State private var path: [PreferencesSection] = []
    #endif

    init(store: StoreOf<Preferences>) {
        self.store = store
    }

    init(store: StoreOf<Preferences>, onDone: @escaping () -> Void) {
        self.store = store
        self.onDone = onDone
    }

    var body: some View {
        #if os(macOS)
            TabView(selection: Binding(get: { store.section }, set: { store.send(.sectionSelected($0)) })) {
                ForEach(PreferencesSection.allCases, id: \.self) { section in
                    Tab(section.rawValue, systemImage: section.symbol, value: section) {
                        pane(section).frame(width: 640, height: 480)
                    }
                }
            }
            .scenePadding()
        #else
            NavigationStack(path: $path) {
                List {
                    ForEach(PreferencesSection.allCases, id: \.self) { section in
                        NavigationLink(value: section) {
                            Label(section.rawValue, systemImage: section.symbol)
                        }
                    }
                }
                .navigationDestination(for: PreferencesSection.self) { section in
                    ScrollView { pane(section).padding(DevysSpacing.roomy) }
                        .background(DevysColors.sheet)
                        .navigationTitle(section.rawValue)
                }
                // Opened at a section ("Apps & connections…"), it starts there.
                .onAppear { if path.isEmpty, store.section != .account { path = [store.section] } }
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone?() } }
                }
            }
        #endif
    }

    @ViewBuilder private func pane(_ section: PreferencesSection) -> some View {
        switch section {
        case .account: AccountPane(store: store)
        case .team: TeamPane(store: store)
        case .businesses: BusinessesPane(store: store)
        case .apps: AppsPane(store: store)
        case .devices: DevicesPane(store: store)
        case .voice: VoicePane(store: store)
        case .appearance: AppearancePane()
        }
    }
}

private struct AccountPane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
            HStack(spacing: DevysSpacing.regular) {
                Portrait(
                    store.ownerPhoto.map(PortraitSource.photo) ?? .initials(store.ownerName?.prefix(1).uppercased() ?? "·", tint: .purple),
                    size: 72,
                    label: store.ownerName
                )
                .overlay { if store.isUploading { ProgressView().controlSize(.small) } }
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.ownerName ?? "You").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                    HStack(spacing: 8) {
                        PhotoChooser(title: store.ownerPhoto == nil ? "Add photo" : "Change photo") { store.send(.ownerPhotoPicked($0)) }
                        if store.ownerPhoto != nil {
                            Button("Remove") { store.send(.ownerPhotoRemoved) }.buttonStyle(.quiet)
                        }
                    }
                }
            }
            if let error = store.errorText {
                Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
            }
            Spacer()
            Button("Sign out of this device", role: .destructive) { store.send(.signOutTapped) }.buttonStyle(.raised)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DevysSpacing.roomy)
    }
}

private struct TeamPane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        HStack(alignment: .top, spacing: DevysSpacing.roomy) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.businesses) { business in
                        Text(business.name).font(DevysTypography.label).foregroundStyle(DevysColors.ink3).padding(.top, 10).padding(.horizontal, 8)
                        ForEach(store.teams[business.id] ?? []) { employee in
                            Button { store.send(.employeeSelected(employee.id)) } label: {
                                HStack(spacing: 10) {
                                    Portrait(source(employee), size: 24, isAnimated: false)
                                    Text(employee.name).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .font(DevysTypography.control)
                                .foregroundStyle(DevysColors.ink)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(store.selectedEmployeeID == employee.id ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 200)
            if let employee = store.allEmployees.first(where: { $0.id == store.selectedEmployeeID }) {
                LookEditor(
                    title: employee.name,
                    current: employee.look,
                    preview: source(employee),
                    fallback: employee.avatar,
                    kind: .employee,
                    set: { look in store.state.target(forEmployee: employee.id).map { store.send(.lookSet($0, look)) } },
                    photo: { data in store.state.target(forEmployee: employee.id).map { store.send(.photoPicked($0, data)) } }
                )
            }
        }
        .padding(DevysSpacing.regular)
    }

    private func source(_ employee: Employee) -> PortraitSource {
        guard let target = store.state.target(forEmployee: employee.id) else { return .face(employee.avatar) }
        return Workspace.State.portrait(for: employee, target: target, photos: store.lookPhotos)
    }
}

private struct VoicePane: View {
    let store: StoreOf<Preferences>

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.roomy) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Reply voice").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                HStack(spacing: 8) {
                    Picker("Reply voice", selection: binding(\.voiceID)) {
                        Text("Best available").tag(String?.none)
                        ForEach(store.voices) { voice in
                            Text("\(voice.name) · \(voice.quality)").tag(Optional(voice.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 280)
                    Button("Preview", systemImage: "play.fill") { store.send(.previewVoiceTapped) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
                if !store.voices.contains(where: { $0.quality != "Default" }) {
                    Text("Better voices download in System Settings › Accessibility › Spoken Content.")
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Speaking rate").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                HStack(spacing: 10) {
                    Image(systemName: "tortoise").foregroundStyle(DevysColors.ink3)
                    Slider(value: binding(\.rate), in: 0.5...1.5, step: 0.05).frame(maxWidth: 260)
                    Image(systemName: "hare").foregroundStyle(DevysColors.ink3)
                }
            }
            Toggle("Read replies aloud", isOn: binding(\.speaksReplies))
                .font(DevysTypography.control)
                .toggleStyle(.switch)
            Text("Speech stays on this device.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DevysSpacing.roomy)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<VoiceSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.voiceSettings[keyPath: keyPath] },
            set: { value in
                var settings = store.voiceSettings
                settings[keyPath: keyPath] = value
                store.send(.voiceSettingsChanged(settings))
            }
        )
    }
}

private struct AppearancePane: View {
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.regular) {
            Text("Appearance").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
            SegmentedTabs(
                selection: $appearance,
                options: [(value: "system", title: "System"), (value: "light", title: "Light"), (value: "dark", title: "Dark")]
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DevysSpacing.roomy)
    }
}

/// Edits one look: the Face (shape and color), an emoji on a tile, or a photo.
struct LookEditor: View {
    enum Kind {
        case employee
        case business(initial: String, tint: BusinessTile.Tint)
    }

    enum Mode: String, Hashable {
        case face = "Face"
        case initials = "Initials"
        case emoji = "Emoji"
        case photo = "Photo"
    }

    let title: String
    let current: Look?
    let preview: PortraitSource
    let fallback: AvatarSpec?
    let kind: Kind
    let set: (Look?) -> Void
    let photo: (Data) -> Void
    @State private var mode: Mode?
    @State private var customEmoji = ""
    @FocusState private var customFocused: Bool

    private static let emojiGroups: [(title: String, emoji: [String])] = [
        ("Work", ["🧭", "🛠️", "📈", "📊", "💼", "🤝", "🧠", "📣", "🗂️", "💡", "🧾", "🎯", "📬", "🔍", "🗓️", "🚀", "🧮", "📝", "📦", "🏗️", "⚙️", "🔧", "💬", "📞"]),
        ("People", ["🙂", "😎", "🤓", "🧐", "🤖", "👩‍💼", "👨‍💼", "🧑‍💻", "👩‍🔬", "🧑‍🎨", "🧑‍🏫", "🧑‍🔧", "🕵️", "🦸", "🧙", "👋", "👍", "🙌", "💪", "🫶"]),
        ("Animals", ["🦉", "🐝", "🦊", "🐙", "🐢", "🦁", "🐼", "🐧", "🦄", "🐬", "🦅", "🐺", "🐨", "🐸", "🦋", "🐳", "🐯", "🦒", "🐘", "🦔"]),
        ("Nature", ["🌱", "🌿", "🍀", "🌻", "🌲", "🌊", "⛰️", "🌙", "☀️", "⭐️", "🔥", "⚡️", "❄️", "🌈", "🍎", "🍋", "🌵", "🍄", "🪴", "🌸"]),
        ("Objects", ["🎨", "📚", "✏️", "🖋️", "📐", "🔬", "🔭", "💎", "🧲", "🎧", "📷", "🎬", "🎵", "🏆", "🎁", "🔑", "🧩", "♟️", "🪁", "🛰️"]),
        ("Symbols", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "✨", "💫", "✅", "➕", "♾️", "🔷", "🔶", "🟣", "🟢", "🔴", "⚪️", "🔺", "🔵"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.regular) {
            HStack(spacing: DevysSpacing.regular) {
                Portrait(preview, size: 84, mood: .idle, label: title)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first, let data = try? Data(contentsOf: url) else { return false }
                        photo(data)
                        return true
                    }
                    .help("Drop an image to use it")
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                    if current != nil {
                        Button("Reset") { set(nil) }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    }
                }
            }
            SegmentedTabs(selection: Binding(get: { resolvedMode }, set: { choose($0) }), options: modes.map { (value: $0, title: $0.rawValue) })
            switch resolvedMode {
            case .face: facePicker
            case .initials: EmptyView()
            case .emoji: emojiPicker
            case .photo:
                PhotoChooser(title: "Choose photo", action: photo)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Choosing a mode applies it at once; a photo waits until one is chosen.
    private func choose(_ next: Mode) {
        mode = next
        switch next {
        case .face: set(.face(currentSpec))
        case .initials: set(nil)
        case .emoji: set(.emoji(currentEmoji, tint: currentTint.rawValue))
        case .photo: break
        }
    }

    private var modes: [Mode] {
        switch kind {
        case .employee: [.face, .emoji, .photo]
        case .business: [.initials, .emoji, .photo]
        }
    }

    private var resolvedMode: Mode {
        if let mode { return mode }
        switch current {
        case .emoji: return .emoji
        case .photo: return .photo
        case .face, nil:
            if case .business = kind { return .initials }
            return .face
        }
    }

    private var currentSpec: AvatarSpec {
        if case .face(let spec) = current { return spec }
        return fallback ?? AvatarSpec(palette: .blue, shape: .roundedSquare, seed: 1)
    }

    private var currentTint: BusinessTile.Tint {
        if case .emoji(_, let tint) = current { return BusinessTile.Tint(rawValue: tint) ?? .blue }
        if case .business(_, let tint) = kind { return tint }
        return .blue
    }

    private var facePicker: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 10), count: 8), spacing: 10) {
                ForEach(AvatarShape.allCases, id: \.self) { shape in
                    option(selected: currentSpec.shape == shape) {
                        set(.face(AvatarSpec(palette: currentSpec.palette, shape: shape, seed: currentSpec.seed)))
                    } content: {
                        DevysAvatar(AvatarSpec(palette: currentSpec.palette, shape: shape, seed: currentSpec.seed), size: 38, isAnimated: false)
                    }
                }
            }
            HStack(spacing: 8) {
                ForEach(AvatarPalette.allCases, id: \.self) { palette in
                    let rgb = palette.eyeInk
                    Button { set(.face(AvatarSpec(palette: palette, shape: currentSpec.shape, seed: currentSpec.seed))) } label: {
                        Circle()
                            .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                            .frame(width: 20, height: 20)
                            .overlay { Circle().strokeBorder(DevysColors.sheet, lineWidth: currentSpec.palette == palette ? 2.5 : 0) }
                            .overlay { Circle().strokeBorder(DevysColors.ink, lineWidth: currentSpec.palette == palette ? 1 : 0).padding(-2) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(palette.rawValue.capitalized)
                }
            }
        }
    }

    private var currentEmoji: String {
        if case .emoji(let emoji, _) = current { return emoji }
        return "🙂"
    }

    private func setEmoji(_ emoji: String) {
        set(.emoji(emoji, tint: currentTint.rawValue))
    }

    private var emojiPicker: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            // Color applies at once: it recolors the current emoji, or starts with 🙂.
            HStack(spacing: 8) {
                ForEach(BusinessTile.Tint.allCases, id: \.self) { tint in
                    Button { set(.emoji(currentEmoji, tint: tint.rawValue)) } label: {
                        Circle()
                            .fill(BusinessTile.colors(for: tint).light)
                            .frame(width: 20, height: 20)
                            .overlay { Circle().strokeBorder(DevysColors.sheet, lineWidth: isEmojiTint(tint) ? 2.5 : 0) }
                            .overlay { Circle().strokeBorder(DevysColors.ink, lineWidth: isEmojiTint(tint) ? 1 : 0).padding(-2) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tint.rawValue.capitalized)
                }
                Spacer(minLength: 12)
                TextField("Any emoji", text: $customEmoji)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .multilineTextAlignment(.center)
                    .frame(width: 64)
                    .padding(.vertical, 5)
                    .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .focused($customFocused)
                    .onChange(of: customEmoji) { _, value in
                        guard let emoji = value.last(where: { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x238C } }) else { return }
                        setEmoji(String(emoji))
                        customEmoji = ""
                    }
                    .help("Type or paste any emoji")
                #if os(macOS)
                    Button("All emoji", systemImage: "face.smiling") {
                        customFocused = true
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DevysColors.ink2)
                    .help("Open the emoji viewer")
                #endif
            }
            ScrollView {
                VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                    ForEach(Self.emojiGroups, id: \.title) { group in
                        Text(group.title).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 10), alignment: .leading, spacing: 6) {
                            ForEach(group.emoji, id: \.self) { emoji in
                                option(selected: current == .emoji(emoji, tint: currentTint.rawValue)) { setEmoji(emoji) } content: {
                                    Text(emoji).font(.system(size: 22))
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 260)
        }
    }

    private func isEmojiTint(_ tint: BusinessTile.Tint) -> Bool {
        if case .emoji(_, let selected) = current { return selected == tint.rawValue }
        return false
    }

    private func option(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> some View) -> some View {
        Button(action: action) {
            content()
                .frame(width: 40, height: 40)
                .background(selected ? DevysColors.well : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? DevysColors.indigo : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
    }
}

/// Photos library picker, plus a file chooser on macOS.
struct PhotoChooser: View {
    let title: String
    let action: (Data) -> Void
    @State private var item: PhotosPickerItem?
    @State private var importing = false

    var body: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $item, matching: .images) {
                Label(title, systemImage: "photo")
            }
            .buttonStyle(.raised)
            #if os(macOS)
                Button("Choose file…") { importing = true }
                    .buttonStyle(.quiet)
                    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                        guard case .success(let url) = result else { return }
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        if let data = try? Data(contentsOf: url) { action(data) }
                    }
            #endif
        }
        .onChange(of: item) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { action(data) }
                self.item = nil
            }
        }
    }
}
