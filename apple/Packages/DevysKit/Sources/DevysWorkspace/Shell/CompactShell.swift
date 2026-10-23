import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

#if os(iOS)
/// iPhone and compact iPad: the list as Messages shows it (pinned tiles, Projects, Chats, and
/// Connect apps at the bottom), and each conversation full screen with its pill in the bar.
/// The pill opens the desk or the project's details as a sheet; layers open as sheets too.
struct CompactShell: View {
    let store: StoreOf<Workspace>
    @State private var showsList = true
    @State private var showsDetails = false

    var body: some View {
        NavigationStack {
            Group {
                if showsList {
                    list
                } else {
                    ConversationPane(store: store, showsHeader: false)
                }
            }
            .background(DevysColors.sheet)
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(DevysColors.indigo)
        .overlay {
            if store.isPaletteOpen { CommandPalette(store: store).transition(.opacity) }
        }
        // ⌘K, a hire or a new project opens a conversation from the list.
        .onChange(of: store.place) { showsList = false }
        .sheet(isPresented: $showsDetails) {
            PlaceDetails(store: store) { showsDetails = false }
                .background(DevysColors.sheet)
                .presentationDetents([.large])
        }
        .sheet(isPresented: Binding(get: { !store.layers.isEmpty }, set: { if !$0 { store.send(.layersClosed) } })) {
            RightPanel(store: store) {}
                .background(DevysColors.sheet)
                .presentationDetents([.large])
        }
        .sheet(isPresented: Binding(get: { store.isConnectingApps }, set: { if !$0 { store.send(.connectAppsToggled(false)) } })) {
            ConnectAppsSheet(store: store)
        }
        .sheet(isPresented: Binding(get: { store.preferences != nil }, set: { if !$0 { store.send(.preferencesToggled(false)) } })) {
            if let preferences = store.spawn(\.preferences) {
                PreferencesScreen(store: preferences) { store.send(.preferencesToggled(false)) }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ScrollView {
                SidebarList(store: store) { showsList = false }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
            }
            HStack(spacing: 10) {
                OwnerButton(store: store)
                ConnectAppsButton(store: store)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if showsList {
            ToolbarItem(placement: .topBarLeading) { BusinessMenu(store: store) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass") { store.send(.paletteToggled(true)) }
            }
            ToolbarItem(placement: .topBarTrailing) { NewMenu(store: store) }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left") {
                    if store.history.isEmpty { showsList = true } else { store.send(.backTapped) }
                }
            }
            ToolbarItem(placement: .principal) {
                HeaderPill(store: store) { showsDetails = true }
            }
        }
    }
}

/// The business at the top of the list: switch businesses.
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
        } label: {
            HStack(spacing: 8) {
                Portrait(store.state.portrait(for: store.snapshot.business), size: 26, isAnimated: false)
                Text(store.snapshot.businessName).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                if store.businesses.count > 1 {
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                }
            }
        }
        .disabled(store.businesses.count < 2)
        .accessibilityLabel("Switch business, currently \(store.snapshot.businessName)")
    }
}
#endif
