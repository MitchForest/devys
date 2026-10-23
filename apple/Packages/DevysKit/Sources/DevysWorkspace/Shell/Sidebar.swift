import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One sidebar: Home, Projects, Team and the business's apps. Each row but an app opens a
/// conversation; an app opens as a layer beside the conversation on screen. The selection is
/// one white pill that springs between rows.
struct Sidebar: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(store.snapshot.businessName).font(DevysTypography.heading).foregroundStyle(DevysColors.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    SidebarIconButton(title: "Search (⌘K)", symbol: "magnifyingglass") { store.send(.paletteToggled(true)) }
                    NewMenu(store: store)
                }
                .padding(.leading, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)
                SidebarSections(store: store)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }
}

/// **New**: a project, a hire or a work item. A message needs nothing: the composer is always there.
struct NewMenu: View {
    let store: StoreOf<Workspace>

    var body: some View {
        Menu {
            Button("New project", systemImage: "square.grid.2x2") { store.send(.newProjectTapped) }
            Button("New work item", systemImage: "checklist") { store.send(.newWorkItemTapped()) }
            Button("Hire", systemImage: "person.badge.plus") { store.send(.hireTapped) }
        } label: {
            Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .foregroundStyle(DevysColors.ink2)
        .fixedSize()
        .help("New")
        .accessibilityLabel("New")
    }
}

/// The sidebar's sections, also the phone's lists. Headings appear only when they have rows.
struct SidebarSections: View {
    enum Part { case projects, team, apps }

    let store: StoreOf<Workspace>
    /// The phone's tabs each show one section; the sidebar shows them all.
    var only: Part?
    /// Called after a row opens something, so the phone can leave its list.
    var opened: () -> Void = {}
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if only == nil || only == .team { team }
            if only == nil || only == .projects { projects }
            if only == nil || only == .apps { apps }
        }
    }

    @ViewBuilder private var projects: some View {
        let projects = store.projects.value ?? []
        if !projects.isEmpty {
            label("Projects", add: ("New project", { store.send(.newProjectTapped) }))
        }
        ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
            placeRow(.project(project.id), project.name, unread: store.state.unread(.project(project.id))) {
                BusinessTile(String(project.name.prefix(1)), tint: Self.tint(index), size: 20)
            }
            ForEach(nestedThreads(project.id)) { threadRow($0) }
        }
    }

    @ViewBuilder private var team: some View {
        label("Team", add: ("Hire", { store.send(.hireTapped) }))
        // The Chief of Staff leads the team: their chat is Home, where the workspace opens.
        if let chief = store.chiefOfStaff {
            let trailing: SidebarTrailing = chief.paused ? .paused : store.state.isWorking(chief.id) ? .working : .none
            placeRow(.home, chief.name, unread: store.state.unread(.direct(chief.id)), needsYou: store.home.value?.needsYou.count ?? 0, trailing: trailing) {
                Portrait(store.state.portrait(for: chief), size: 20, mood: store.state.mood(for: chief), isAnimated: false)
            }
        }
        if only == nil { ForEach(nestedThreads(nil)) { threadRow($0) } }
        ForEach(store.snapshot.employees.filter { $0.id != store.chiefOfStaff?.id }) { employee in
            placeRow(.direct(employee.id), employee.name, unread: store.state.unread(.direct(employee.id)), trailing: trailing(for: employee)) {
                Portrait(store.state.portrait(for: employee), size: 20, mood: store.state.mood(for: employee), isAnimated: false)
            }
        }
    }

    @ViewBuilder private var apps: some View {
        let shown = (store.apps.value ?? []).filter { $0.visible && $0.pinned }
        if !shown.isEmpty, only == nil { label("Apps") }
        ForEach(shown) { app in
            // A remote app opens its card; a Devys app its records.
            let layer: Layer = app.state == nil ? .app(app.id) : .remoteApp(app.id)
            let selected = store.state.topLayer == layer
            SidebarRow(title: app.name, selected: selected, pill: pill, leading: AppIcon(app: app)) {
                store.send(selected ? .layersClosed : .layerOpened(layer))
                opened()
            }
        }
    }

    /// Threads the owner follows or that need the owner, under their project (or under Home when
    /// they have none). Everything else stays in its channel.
    private func nestedThreads(_ projectID: String?) -> [WorkItem] {
        let waiting = Set(store.state.decisions.compactMap(\.workItemID))
        return (store.work.value ?? []).filter { item in
            item.state.isOpen && item.projectID == projectID
                && (store.state.isFollowing(item.id) || item.state == .needsDecision || waiting.contains(item.id))
        }
    }

    private func trailing(for employee: Employee) -> SidebarTrailing {
        if employee.paused { return .paused }
        if store.state.isWorking(employee.id) { return .working }
        return store.state.decisions.contains { $0.employeeID == employee.id } ? .needsYou : .none
    }

    /// A project's tile color, from its place in the list, the same everywhere it shows.
    static func tint(_ index: Int) -> BusinessTile.Tint {
        let tints: [BusinessTile.Tint] = [.blue, .orange, .green, .purple, .pink]
        return tints[(index + 1) % tints.count]
    }

    private func label(_ text: String, add: (title: String, action: () -> Void)? = nil) -> some View {
        HStack {
            Text(text)
                .font(DevysTypography.label)
                .foregroundStyle(DevysColors.ink3)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let add {
                Button(add.title, systemImage: "plus", action: add.action)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DevysColors.ink3)
                    .help(add.title)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func placeRow(
        _ place: Place,
        _ title: String,
        unread: Int = 0,
        needsYou: Int = 0,
        trailing: SidebarTrailing = .none,
        @ViewBuilder leading: () -> some View
    ) -> some View {
        SidebarRow(title: title, needsYou: needsYou, unread: unread, trailing: trailing, selected: store.place == place, pill: pill, leading: leading()) {
            store.send(.placeSelected(place))
            opened()
        }
    }

    private func threadRow(_ item: WorkItem) -> some View {
        SidebarRow(
            title: item.title,
            unread: store.state.unread(.work(item.id)),
            trailing: item.state == .needsDecision ? .needsYou : .none,
            selected: store.place == .thread(item.id),
            isNested: true,
            pill: pill,
            leading: EmptyView()
        ) {
            store.send(.threadOpened(item.id))
            opened()
        }
    }
}

enum SidebarTrailing: Equatable {
    case none
    case working
    case needsYou
    case paused
}

/// The symbol an app names in its manifest.
private struct AppIcon: View {
    let app: AppEntry

    var body: some View {
        if app.state != nil {
            AppLogo(path: app.logo, name: app.name, size: 18).frame(width: 20)
        } else {
            Image(systemName: Self.symbols[app.id] ?? "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 20)
                .accessibilityHidden(true)
        }
    }

    static let symbols = ["documents": "doc.text", "code": "chevron.left.forwardslash.chevron.right"]
}

private struct SidebarRow<Leading: View>: View {
    let title: String
    /// Things waiting on the owner: an amber count.
    var needsYou = 0
    /// Unread messages in the row's conversation.
    var unread = 0
    var trailing = SidebarTrailing.none
    let selected: Bool
    /// A thread under its project: indented, smaller.
    var isNested = false
    let pill: Namespace.ID
    let leading: Leading
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(DevysMotion.select(reduceMotion: reduceMotion)) { action() }
        } label: {
            HStack(spacing: 10) {
                leading
                Text(title).fontWeight(unread > 0 ? .semibold : nil).lineLimit(1)
                    .font(isNested ? DevysTypography.secondary : DevysTypography.control)
                Spacer(minLength: 6)
                switch trailing {
                case .none: EmptyView()
                case .working:
                    Circle().fill(DevysColors.indigo).frame(width: 6, height: 6).accessibilityLabel("working")
                case .needsYou:
                    Circle().fill(DevysColors.amber).frame(width: 6, height: 6).accessibilityLabel("needs you")
                case .paused:
                    Text("Paused").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                if needsYou > 0 { CountBadge(count: needsYou, color: DevysColors.amber) }
                if unread > 0 { UnreadBadge(count: unread) }
            }
            .font(DevysTypography.control)
            .foregroundStyle(selected || hovering || unread > 0 ? DevysColors.ink : DevysColors.ink2)
            .padding(.leading, isNested ? 38 : 10)
            .padding(.trailing, 10)
            .padding(.vertical, isNested ? 5 : 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DevysColors.sheet)
                        .devysElevation(.resting)
                        .matchedGeometryEffect(id: "selection", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(unread > 0 ? "\(title), \(unread) unread" : needsYou > 0 ? "\(title), \(needsYou)" : title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The number of unread messages in a conversation.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        CountBadge(count: count, color: DevysColors.indigo).accessibilityLabel("\(count) unread")
    }
}

private struct CountBadge: View {
    let count: Int
    let color: Color
    @ScaledMetric(relativeTo: .caption2) private var size = 10.5

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(color, in: Capsule())
    }
}

/// A small icon button in the sidebar's header.
private struct SidebarIconButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DevysColors.ink2)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .help(title)
    }
}
