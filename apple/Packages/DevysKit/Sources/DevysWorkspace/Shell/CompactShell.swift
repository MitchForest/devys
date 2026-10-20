import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

#if os(iOS)
/// iPhone and compact iPad: a floating glass tab bar. Home lists Direct messages and
/// Spaces; a conversation opens full screen, and a work item pushes on top.
struct CompactShell: View {
    let store: StoreOf<Workspace>

    var body: some View {
        TabView(selection: Binding(
            get: { Destination.compact.contains(store.destination) ? store.destination : .home },
            set: { store.send(.destinationSelected($0)) }
        )) {
            ForEach(Destination.compact) { destination in
                Tab(destination.title, systemImage: destination.symbol, value: destination) {
                    stack(for: destination)
                }
            }
        }
        .tint(DevysColors.indigo)
        .sheet(isPresented: Binding(get: { store.preferences != nil }, set: { if !$0 { store.send(.preferencesToggled(false)) } })) {
            if let preferences = store.spawn(\.preferences) {
                PreferencesScreen(store: preferences) { store.send(.preferencesToggled(false)) }
            }
        }
    }

    /// The tab whose stack shows the current page: Home also shows pages without a tab.
    private var activeTab: Destination {
        Destination.compact.contains(store.destination) ? store.destination : .home
    }

    @ViewBuilder private func stack(for destination: Destination) -> some View {
        if destination == .home {
            NavigationStack(path: homePath) {
                CompactHome(store: store)
                    .background(DevysColors.sheet)
                    .toolbar { toolbar }
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: Page.self) { page in
                        PageContent(store: store, page: page)
                            .background(DevysColors.sheet)
                            .toolbar(.hidden, for: .tabBar)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .modifier(WorkDestination(store: store, active: activeTab == .home))
            }
        } else {
            NavigationStack {
                MainPane(store: store)
                    .background(DevysColors.sheet)
                    .toolbar { toolbar }
                    .navigationBarTitleDisplayMode(.inline)
                    .modifier(WorkDestination(store: store, active: activeTab == destination))
            }
        }
    }

    /// Home's root is the list; any other page it shows is pushed on top of it.
    private var homePath: Binding<[Page]> {
        Binding(
            get: { activeTab == .home && store.page != .today ? [store.page] : [] },
            set: { path in
                if path.isEmpty, store.page != .today { store.send(.pageSelected(.today)) }
            }
        )
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
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
                Button("New task") { store.send(.newTaskTapped()) }
                Button("Hire") { store.send(.hireTapped) }
                Divider()
                Button("Files") { store.send(.pageSelected(.files(nil))) }
                Button("Money") { store.send(.pageSelected(.money)) }
                Button("Apps and connections") { store.send(.pageSelected(.apps(.installed))) }
                Button("Settings") { store.send(.preferencesToggled(true)) }
                Divider()
                Button("Sign out of this device", role: .destructive) { store.send(.signOutTapped) }
            } label: {
                HStack(spacing: 8) {
                    Portrait(store.state.portrait(for: store.preview.business), size: 26, isAnimated: false)
                    Text(store.preview.businessName).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(DevysColors.ink3)
                }
            }
            .accessibilityLabel("Switch business, currently \(store.preview.businessName)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if let ops = store.operations {
                Button { store.send(.pageSelected(.direct(ops.id))) } label: {
                    Portrait(store.state.portrait(for: ops), size: 28, mood: store.operationsMood, label: ops.name)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Message \(ops.name)")
            }
        }
    }
}

/// The open work item pushes onto the visible tab's stack; going back closes it.
private struct WorkDestination: ViewModifier {
    let store: StoreOf<Workspace>
    let active: Bool

    private struct Route: Hashable, Identifiable {
        let id: String
    }

    func body(content: Content) -> some View {
        content.navigationDestination(item: Binding(
            get: { active ? store.state.selectedWorkID.map(Route.init) : nil },
            set: { if $0 == nil, active { store.send(.workClosed) } }
        )) { route in
            WorkPanel(store: store, commitmentID: route.id)
                .background(DevysColors.sheet)
                .toolbar(.hidden, for: .tabBar)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
