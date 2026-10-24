import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The sidebar is people, work and projects, as Messages lays out a list: pinned tiles, Work while
/// any is going, Projects while one is active, then Chats, most recent first; the owner's face (Settings) and Connect apps at
/// the bottom. Search and New are ⌘K and the menu bar (the title bar's search on the Mac).
struct Sidebar: View {
    let store: StoreOf<Workspace>

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                SidebarList(store: store)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
            .scrollIndicators(.never)
            SidebarFooter(store: store)
        }
    }
}

/// The list itself, the sidebar's and the phone's: tiles, Work (only while any is going), Projects
/// (only while one is active) and Chats. `opened` runs after a row opens something, so the phone
/// can leave its list.
struct SidebarList: View {
    let store: StoreOf<Workspace>
    var opened: () -> Void = {}
    @State private var renaming: Employee?
    @State private var retiring: Employee?
    @State private var name = ""

    var body: some View {
        let layout = store.state.sidebar
        let work = store.state.activeWork()
        VStack(alignment: .leading, spacing: 2) {
            if !layout.pinned.isEmpty { tiles(layout.pinned) }
            if !work.isEmpty {
                heading("Work")
                ForEach(work) { item in
                    WorkSidebarRow(store: store, item: item) {
                        store.send(.workOpened(item.id))
                        opened()
                    }
                    .contextMenu { WorkActions(store: store, item: item) }
                }
            }
            if !layout.projects.isEmpty {
                heading("Projects")
                ForEach(layout.projects) { row($0) }
            }
            if !work.isEmpty || !layout.projects.isEmpty { heading("Chats") }
            ForEach(layout.chats) { row($0) }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { employee in
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                store.send(.employeeRenamed(employee.id, name))
                renaming = nil
            }
            .keyboardShortcut(.defaultAction)
        }
        .sheet(item: $retiring) { employee in
            RetireSheet(store: store, employee: employee) { retiring = nil }
        }
    }

    /// One tile alone fills the width with a large face; several share two columns.
    private func tiles(_ entries: [SidebarEntry]) -> some View {
        let single = entries.count == 1
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: single ? 1 : 2), spacing: 8) {
            ForEach(entries) { entry in
                PinnedTile(store: store, entry: entry, faceSize: single ? 88 : 52) { open(entry) }
                    .contextMenu { menu(entry) }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func row(_ entry: SidebarEntry) -> some View {
        ChatRow(store: store, entry: entry) { open(entry) }
            .contextMenu { menu(entry) }
    }

    private func open(_ entry: SidebarEntry) {
        store.send(.placeSelected(entry.place))
        opened()
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(DevysTypography.label)
            .foregroundStyle(DevysColors.ink3)
            .padding(.horizontal, 10)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// The row's menu, as Messages draws one: Pin, Mark as Unread, Rename, Pause, Hide, Retire.
    @ViewBuilder private func menu(_ entry: SidebarEntry) -> some View {
        Button(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin") {
            store.send(.sidebarMarked(entry.key, SidebarMark(pinned: !entry.isPinned)))
        }
        if entry.unread == 0 {
            Button("Mark as Unread", systemImage: "bell.badge") { store.send(.sidebarMarked(entry.key, SidebarMark(unread: true))) }
        } else {
            Button("Mark as Read", systemImage: "bell") { store.send(.sidebarMarked(entry.key, SidebarMark(unread: false))) }
        }
        if case .employee(let id) = entry.subject, let employee = store.state.employee(id) {
            Button("Rename…", systemImage: "square.and.pencil") {
                name = employee.name
                renaming = employee
            }
            Button(employee.paused ? "Resume" : "Pause", systemImage: employee.paused ? "play" : "pause") {
                store.send(.pauseToggled(employee.id))
            }
            if !employee.isChiefOfStaff {
                Button("Hide from Sidebar", systemImage: "eye.slash") { store.send(.sidebarMarked(entry.key, SidebarMark(hidden: true))) }
                Divider()
                Button("Retire…", systemImage: "trash", role: .destructive) { retiring = employee }
            }
        } else {
            Button("Hide from Sidebar", systemImage: "eye.slash") { store.send(.sidebarMarked(entry.key, SidebarMark(hidden: true))) }
        }
    }
}

/// A pinned conversation: a big face (or project tile) on a light rounded square with the name
/// under it. The Chief of Staff's carries a star.
private struct PinnedTile: View {
    let store: StoreOf<Workspace>
    let entry: SidebarEntry
    let faceSize: CGFloat
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selected = store.place == entry.place
        Button {
            withAnimation(DevysMotion.select(reduceMotion: reduceMotion)) { action() }
        } label: {
            VStack(spacing: 8) {
                SidebarFace(store: store, entry: entry, size: faceSize)
                    .overlay(alignment: .topTrailing) {
                        if needsYou > 0 {
                            NeedsYouBadge(count: needsYou).offset(x: 6, y: -6)
                        } else if entry.unread > 0, !selected {
                            UnreadDot().offset(x: 2, y: -2)
                        }
                    }
                Text(entry.title)
                    .font(DevysTypography.control.weight(entry.unread > 0 || selected ? .semibold : .medium))
                    .foregroundStyle(DevysColors.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, faceSize > 60 ? 16 : 12)
            .padding(.horizontal, 8)
            // As in Messages: the face and name alone; being pinned is the place and size.
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.unread > 0 ? "\(entry.title), unread" : entry.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What waits on the owner counts on the Chief of Staff's face, Home's badge.
    private var needsYou: Int { entry.place == .home ? store.home.value?.needsYou.count ?? 0 : 0 }
}

/// A chat row as Messages draws one: the face, the name in bold, the newest line in grey, the
/// time, and a blue dot while unread.
private struct ChatRow: View {
    let store: StoreOf<Workspace>
    let entry: SidebarEntry
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let selected = store.place == entry.place
        Button {
            withAnimation(DevysMotion.select(reduceMotion: reduceMotion)) { action() }
        } label: {
            HStack(spacing: 10) {
                SidebarFace(store: store, entry: entry, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.title).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink).lineLimit(1)
                        if paused { Image(systemName: "pause.fill").font(.system(size: 9)).foregroundStyle(DevysColors.ink3).accessibilityLabel("paused") }
                        Spacer(minLength: 4)
                        if let date = entry.date {
                            Text(SidebarTime.text(date)).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                        }
                    }
                    // A second line only when there is something to say: the name centres otherwise.
                    let needsYou = entry.place == .home ? store.home.value?.needsYou.count ?? 0 : 0
                    if !line.isEmpty || needsYou > 0 || (entry.unread > 0 && !selected) {
                        HStack(spacing: 4) {
                            Text(line)
                                .font(DevysTypography.secondary)
                                .foregroundStyle(working ? DevysColors.indigo : DevysColors.ink3)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if needsYou > 0 {
                                NeedsYouBadge(count: needsYou)
                            } else if entry.unread > 0, !selected {
                                UnreadDot()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DevysColors.sheet).devysElevation(.resting)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DevysColors.track.opacity(0.45))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.unread > 0 ? "\(entry.title), unread, \(line)" : "\(entry.title), \(line)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var employeeID: String? {
        if case .employee(let id) = entry.subject { id } else { nil }
    }

    private var paused: Bool { employeeID.flatMap { store.state.employee($0) }?.paused ?? false }
    private var working: Bool { employeeID.map(store.state.isWorking) ?? false }

    /// The newest line; while working, that it is; nothing yet when nothing has been said.
    private var line: String {
        if working { return "Working…" }
        if let preview = entry.preview { return preview }
        return employeeID == nil ? store.state.project(entry.key.ref)?.goal ?? "" : ""
    }
}

/// An entry's picture: an employee's face, or a project's lettered tile.
private struct SidebarFace: View {
    let store: StoreOf<Workspace>
    let entry: SidebarEntry
    let size: CGFloat

    var body: some View {
        switch entry.subject {
        case .employee(let id):
            if let employee = store.state.employee(id) {
                Portrait(store.state.portrait(for: employee), size: size, mood: store.state.mood(for: employee), isAnimated: size > 60)
            }
        case .project(let id):
            BusinessTile(String(entry.title.prefix(1)), tint: store.state.projectTint(id), size: size)
        }
    }
}

extension Workspace.State {
    /// A project's tile color, from its place in the list, the same everywhere it shows.
    func projectTint(_ id: String) -> BusinessTile.Tint {
        let tints: [BusinessTile.Tint] = [.blue, .orange, .green, .purple, .pink]
        let index = projects.value?.firstIndex { $0.id == id } ?? 0
        return tints[(index + 1) % tints.count]
    }
}

/// "9:41", "Yesterday", "Mon" or "Oct 3", as Messages times a row.
enum SidebarTime {
    static func text(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// The blue dot of an unread conversation.
struct UnreadDot: View {
    var body: some View {
        Circle().fill(DevysColors.indigo).frame(width: 9, height: 9).accessibilityLabel("unread")
    }
}

/// How many things wait on the owner, in amber.
private struct NeedsYouBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(DevysColors.amber, in: Capsule())
            .accessibilityLabel(count == 1 ? "1 needs you" : "\(count) need you")
    }
}

/// The bottom of the sidebar: the owner's face (Settings) and Connect apps.
private struct SidebarFooter: View {
    let store: StoreOf<Workspace>

    var body: some View {
        HStack(spacing: 10) {
            OwnerButton(store: store)
            ConnectAppsButton(store: store)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// The owner's round photo: Settings.
struct OwnerButton: View {
    let store: StoreOf<Workspace>

    var body: some View {
        #if os(macOS)
            SettingsLink { face }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
        #else
            Button { store.send(.preferencesToggled(true)) } label: { face }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
        #endif
    }

    private var face: some View {
        Portrait(store.state.ownerPortrait, size: 34, isAnimated: false)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(DevysColors.hairline, lineWidth: 1) }
    }
}

/// A wide white pill with a few app logos overlapping: opens the Connect apps sheet.
struct ConnectAppsButton: View {
    let store: StoreOf<Workspace>
    @State private var hovering = false

    var body: some View {
        Button { store.send(.connectAppsToggled(true)) } label: {
            HStack(spacing: 8) {
                Text("Connect apps").font(DevysTypography.control).foregroundStyle(DevysColors.ink)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 4)
                HStack(spacing: -7) {
                    ForEach(Array(store.state.connectLogos.enumerated()), id: \.offset) { _, app in
                        AppLogo(path: app.logo, name: app.name, size: 20)
                            .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DevysColors.sheet, lineWidth: 1.5) }
                    }
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(hovering ? DevysColors.sheetTint : DevysColors.sheet, in: Capsule())
            .overlay { Capsule().strokeBorder(DevysColors.hairline, lineWidth: 1) }
            .devysElevation(.resting)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Connect apps")
    }
}

/// A work item in the sidebar: who is on it, its title and where it stands ("Your turn: Connect
/// Ramp" in amber, "Opening godaddy.com…" while it runs). It opens beside whatever conversation is
/// on screen.
private struct WorkSidebarRow: View {
    let store: StoreOf<Workspace>
    let item: WorkItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let status = store.state.workStatus(item)
        let open = store.state.workInPanel == item.id
        Button(action: action) {
            HStack(spacing: 10) {
                if let owner = store.state.employee(item.ownerEmployeeID) {
                    Portrait(store.state.portrait(for: owner), size: 28, mood: store.state.mood(for: owner), isAnimated: false)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(DevysTypography.control.weight(status.tone == .you ? .semibold : .medium))
                        .foregroundStyle(DevysColors.ink)
                        .lineLimit(1)
                    Text(status.text)
                        .font(DevysTypography.secondary)
                        .foregroundStyle(status.tone.color)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if open {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DevysColors.sheet).devysElevation(.resting)
                } else if hovering {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DevysColors.track.opacity(0.45))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(status.text)")
        .accessibilityAddTraits(open ? .isSelected : [])
    }
}
