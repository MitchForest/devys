import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

#if os(iOS)
/// iPhone and compact iPad: a floating glass tab bar of Home, Projects, Team and Apps. The
/// conversation is always full screen; its header (or the details button) shows the permanent
/// view as a sheet, and layers open as sheets over the conversation.
struct CompactShell: View {
    let store: StoreOf<Workspace>
    /// A tab's list shows until the owner opens something from it.
    @State private var list: CompactTab?
    @State private var showsDetails = false

    var body: some View {
        TabView(selection: Binding(get: { list ?? CompactTab(store.place) }, set: select)) {
            ForEach(CompactTab.allCases, id: \.self) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    NavigationStack {
                        content(tab)
                            .background(DevysColors.sheet)
                            .toolbar { toolbar }
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(list == nil && store.place != .home ? .hidden : .visible, for: .tabBar)
                    }
                }
            }
        }
        .tint(DevysColors.indigo)
        #if DEBUG
            // DEVYS_PANEL=open: the phone shows the permanent view as its sheet.
            .task(id: store.isOverlayOpen) { if store.isOverlayOpen { showsDetails = true } }
        #endif
        .sheet(isPresented: Binding(
            get: { showsDetails || !store.layers.isEmpty },
            set: { shown in
                guard !shown else { return }
                showsDetails = false
                store.send(.layersClosed)
            }
        )) {
            RightPanel(store: store) { showsDetails = false }
                .background(DevysColors.sheet)
                .presentationDetents([.large])
        }
        .sheet(isPresented: Binding(get: { store.preferences != nil }, set: { if !$0 { store.send(.preferencesToggled(false)) } })) {
            if let preferences = store.spawn(\.preferences) {
                PreferencesScreen(store: preferences) { store.send(.preferencesToggled(false)) }
            }
        }
    }

    private func select(_ tab: CompactTab) {
        if tab == .home {
            list = nil
            store.send(.placeSelected(.home))
        } else {
            list = tab
        }
    }

    @ViewBuilder private func content(_ tab: CompactTab) -> some View {
        if list == tab {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    switch tab {
                    case .projects:
                        if (store.projects.value ?? []).isEmpty {
                            EmptyNote(text: "No projects yet. A project is one goal with its own channel and work.")
                        }
                        Button("New project", systemImage: "plus") { store.send(.newProjectTapped) }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                            .padding(.vertical, 6)
                        SidebarSections(store: store, only: .projects) { list = nil }
                    case .team:
                        SidebarSections(store: store, only: .team) { list = nil }
                    case .apps:
                        CompactApps(store: store)
                    case .home:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 24)
            }
        } else {
            ConversationPane(store: store)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if list == nil, store.place != .home {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    if store.history.isEmpty { list = CompactTab(store.place) } else { store.send(.backTapped) }
                }
            }
            ToolbarItem(placement: .principal) {
                Button { showsDetails = true } label: {
                    HStack(spacing: 8) {
                        if case .direct(let id) = store.place, let employee = store.state.employee(id) {
                            Portrait(store.state.portrait(for: employee), size: 26, mood: store.state.mood(for: employee), isAnimated: false)
                        }
                        Text(store.state.title(of: store.place).title).font(DevysTypography.heading).foregroundStyle(DevysColors.ink).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the details")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Details", systemImage: "sidebar.right") { showsDetails = true }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) { BusinessMenu(store: store) }
            if list == nil {
                ToolbarItem(placement: .topBarTrailing) { homeTrailing }
            }
        }
    }

    /// Home: how many things need the owner, and the Chief of Staff; either opens Needs you.
    private var homeTrailing: some View {
        HStack(spacing: 8) {
            let count = store.home.value?.needsYou.count ?? 0
            if count > 0 {
                Button { showsDetails = true } label: {
                    Text(count == 1 ? "1 needs you" : "\(count) need you")
                        .font(DevysTypography.caption.weight(.semibold))
                        .foregroundStyle(DevysColors.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DevysColors.amber.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if let ops = store.chiefOfStaff {
                Button { showsDetails = true } label: {
                    Portrait(store.state.portrait(for: ops), size: 28, mood: store.state.voiceMood ?? store.chiefOfStaffMood, label: ops.name)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ops.name)
            }
        }
    }
}

private enum CompactTab: CaseIterable, Hashable {
    case home, projects, team, apps

    /// The tab a place belongs to.
    init(_ place: Place) {
        switch place {
        case .home: self = .home
        case .direct: self = .team
        case .project, .thread: self = .projects
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .projects: "Projects"
        case .team: "Team"
        case .apps: "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .projects: "folder"
        case .team: "person.2"
        case .apps: "square.grid.2x2"
        }
    }
}

/// The business at the top of each tab: switch businesses, start something, open Settings.
private struct BusinessMenu: View {
    let store: StoreOf<Workspace>

    var body: some View {
        Menu {
            ForEach(store.businesses) { business in
                Button {
                    store.send(.businessSelected(business.id))
                } label: {
                    if business.id == store.businessID {
                        Label(business.name, systemImage: "checkmark")
                    } else {
                        Text(business.name)
                    }
                }
            }
            Divider()
            Button("New project") { store.send(.newProjectTapped) }
            Button("New work item") { store.send(.newWorkItemTapped()) }
            Button("Hire") { store.send(.hireTapped) }
            Button("Settings") { store.send(.preferencesToggled(true)) }
            Button("Apps & connections") { store.send(.settingsOpened(.apps)) }
            Divider()
            Button("Sign out of this device", role: .destructive) { store.send(.signOutTapped) }
        } label: {
            HStack(spacing: 8) {
                Portrait(store.state.portrait(for: store.snapshot.business), size: 26, isAnimated: false)
                Text(store.snapshot.businessName).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Switch business, currently \(store.snapshot.businessName)")
    }
}

/// The phone's Apps tab: each installed app opens as a sheet over the conversation.
private struct CompactApps: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ForEach((store.apps.value ?? []).filter(\.visible)) { app in
            Button { store.send(.layerOpened(.app(app.id))) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(DevysTypography.body.weight(.medium)).foregroundStyle(DevysColors.ink)
                    Text(app.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
#endif
