import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One gray frame (toolbar and business strip) around one rounded workspace: the sidebar, the
/// conversation in the middle, and the right panel showing what the conversation is about,
/// divided by hairlines.
struct RegularShell: View {
    #if os(macOS)
        static let sidebarWidth: CGFloat = 236
    #else
        static let sidebarWidth: CGFloat = 270
    #endif

    let store: StoreOf<Workspace>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("panelWidth") private var panelWidth = Double(WorkspaceLayout.defaultPanel)

    var body: some View {
        VStack(spacing: 0) {
            #if !os(macOS)
                ShellToolbar(store: store)
            #endif
            HStack(spacing: 0) {
                BusinessStrip(store: store)
                workspace
            }
        }
        .background(DevysColors.frame)
        #if os(macOS)
            // Native window toolbar items: the system centres the traffic lights
            // and owns hit-testing in the title band, so custom views drawn
            // under it would never receive clicks.
            .toolbar { MacToolbar(store: store) }
        #endif
        .overlay {
            if store.isPaletteOpen {
                CommandPalette(store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.isSidebarVisible)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.state.isPanelOpen)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.state.isWideShown)
        .animation(DevysMotion.quick, value: store.isPaletteOpen)
        .background { Shortcuts(store: store) }
        #if os(iOS)
            .sheet(isPresented: Binding(get: { store.preferences != nil }, set: { if !$0 { store.send(.preferencesToggled(false)) } })) {
                if let preferences = store.spawn(\.preferences) {
                    PreferencesScreen(store: preferences) { store.send(.preferencesToggled(false)) }
                }
            }
        #endif
    }

    private var workspace: some View {
        GeometryReader { proxy in
            let layout = WorkspaceLayout(
                width: proxy.size.width,
                sidebarWidth: Self.sidebarWidth,
                sidebarVisible: store.isSidebarVisible,
                panelOpen: store.state.isPanelOpen,
                wide: store.state.isWideShown,
                preferredPanel: panelWidth
            )
            // Whether an open panel would lie over the conversation, whatever is open now.
            let narrow = WorkspaceLayout(
                width: proxy.size.width,
                sidebarWidth: Self.sidebarWidth,
                sidebarVisible: store.isSidebarVisible,
                panelOpen: true,
                wide: false,
                preferredPanel: panelWidth
            ).overlay
            // Every column is always present at an explicit width; showing, hiding and widening
            // animate widths, so motion stays continuous. Too narrow for both, the panel lies
            // over the conversation.
            HStack(spacing: 0) {
                Sidebar(store: store)
                    .frame(width: Self.sidebarWidth)
                    .frame(width: layout.sidebar, alignment: .trailing)
                    .clipped()
                    .background(DevysColors.sheetTint)
                Hairline().opacity(layout.sidebar > 0 ? 1 : 0).frame(width: layout.sidebar > 0 ? 1 : 0)
                ConversationPane(store: store)
                    .frame(width: max(layout.conversation, WorkspaceLayout.minimumConversation))
                    .frame(width: layout.conversation, alignment: .leading)
                    .clipped()
                    .background(DevysColors.sheet)
                ResizeHandle(width: $panelWidth)
                    .frame(width: layout.showsHandle ? WorkspaceLayout.handle : 0)
                    .opacity(layout.showsHandle ? 1 : 0)
                    .allowsHitTesting(layout.showsHandle)
                if !layout.overlay { panel(layout) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            // A task, as in WorkspaceScreen: an initial onChange can run inside a reducer's mutation.
            .task(id: narrow) {
                if narrow != store.isNarrow { store.send(.narrowChanged(narrow)) }
            }
            .overlay(alignment: .trailing) {
                if layout.overlay {
                    panel(layout)
                        .overlay(alignment: .leading) { Hairline() }
                        .devysElevation(.raised)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .background(DevysColors.sheet)
        .clipShape(RoundedRectangle(cornerRadius: DevysRadius.workspace, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DevysRadius.workspace, style: .continuous)
                .strokeBorder(DevysColors.hairline, lineWidth: 1)
        }
        .devysElevation(.resting)
        .padding(.trailing, DevysSpacing.small)
        .padding(.bottom, DevysSpacing.small)
    }

    private func panel(_ layout: WorkspaceLayout) -> some View {
        Group { if store.state.isPanelOpen { RightPanel(store: store) } }
            .frame(width: max(layout.panel, WorkspaceLayout.panelRange.lowerBound))
            .frame(width: layout.panel, alignment: .leading)
            .clipped()
            .background(DevysColors.sheet)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(DevysColors.hairline).frame(width: 1)
    }
}

/// The pane divider doubles as a drag handle for the right panel's width.
private struct ResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?
    @State private var hovering = false

    static let range = Double(WorkspaceLayout.panelRange.lowerBound)...Double(WorkspaceLayout.panelRange.upperBound)

    var body: some View {
        // A 9pt sheet-colored strip with the visible hairline in its centre.
        DevysColors.sheet
            .overlay {
                Rectangle()
                    .fill(hovering || start != nil ? DevysColors.ink3.opacity(0.6) : DevysColors.hairline)
                    .frame(width: hovering || start != nil ? 2 : 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            #if os(macOS)
            .pointerStyle(.frameResize(position: .leading))
            #endif
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let origin = start ?? width
                        start = origin
                        width = min(max(origin - value.translation.width, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in start = nil }
            )
            .onTapGesture(count: 2) { width = Double(WorkspaceLayout.defaultPanel) }
            .animation(DevysMotion.quick, value: hovering)
            .accessibilityHidden(true)
    }
}

#if os(macOS)
    private struct MacToolbar: ToolbarContent {
        let store: StoreOf<Workspace>

        var body: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    SidebarToggle(store: store)
                    BackButton(store: store)
                    Breadcrumb(store: store).padding(.leading, 6)
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                PanelToggle(store: store)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
#endif

/// iPad has no window toolbar, so it draws the same controls as a row.
private struct ShellToolbar: View {
    let store: StoreOf<Workspace>

    var body: some View {
        HStack(spacing: 6) {
            SidebarToggle(store: store)
            BackButton(store: store)
            Breadcrumb(store: store).padding(.leading, 6)
            Spacer(minLength: DevysSpacing.regular)
            PanelToggle(store: store)
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 50)
    }
}

private struct SidebarToggle: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ToolbarIconButton(store.isSidebarVisible ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)", symbol: "sidebar.left") {
            store.send(.sidebarToggled)
        }
    }
}

/// Back returns from a thread to where it was opened.
private struct BackButton: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if !store.history.isEmpty {
            ToolbarIconButton("Back (⌘[)", symbol: "chevron.left") { store.send(.backTapped) }
        }
    }
}

/// Shows or hides the right panel; only when there is something to show.
private struct PanelToggle: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if store.state.hasPermanent || !store.layers.isEmpty {
            ToolbarIconButton(store.state.isPanelOpen ? "Hide side panel (⌥⌘0)" : "Show side panel (⌥⌘0)", symbol: "sidebar.right") {
                store.send(.panelToggled)
            }
        }
    }
}

/// The business, the place and, in a thread, its project: "Acme / Launch › Fix sitemap".
private struct Breadcrumb: View {
    let store: StoreOf<Workspace>

    var body: some View {
        let trail = store.state.title(of: store.place)
        HStack(spacing: 6) {
            Text(store.snapshot.businessName).foregroundStyle(DevysColors.ink3)
            Text("/").foregroundStyle(DevysColors.ink3)
            if let parent = trail.parent {
                Button(parent.title) { store.send(.placeSelected(parent.place)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(DevysColors.ink2)
                Text("›").foregroundStyle(DevysColors.ink3)
            }
            Text(trail.title).foregroundStyle(DevysColors.ink).fontWeight(.semibold).lineLimit(1)
                .contentTransition(.opacity)
        }
        .font(DevysTypography.control)
        .fixedSize()
    }
}

/// Tiles that switch businesses, and the account at the bottom.
private struct BusinessStrip: View {
    let store: StoreOf<Workspace>

    var body: some View {
        VStack(spacing: 6) {
            ForEach(store.businesses) { business in
                let selected = business.id == store.businessID
                Button { store.send(.businessSelected(business.id)) } label: {
                    Portrait(store.state.portrait(for: business), size: 36, isAnimated: false)
                        .scaleEffect(selected ? 1 : 0.92)
                        .opacity(selected ? 1 : 0.75)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .leading) {
                    if selected {
                        Capsule().fill(DevysColors.ink).frame(width: 4, height: 20).offset(x: -12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(DevysMotion.select, value: selected)
                .help(business.name)
                .accessibilityLabel("Switch to \(business.name)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
            Menu {
                if let name = store.account?.person.displayName { Text(name) }
                Text(store.server.host() ?? store.server.absoluteString)
                Divider()
                #if os(macOS)
                    SettingsLink { Text("Settings…") }
                #else
                    Button("Settings…") { store.send(.preferencesToggled(true)) }
                    Button("Apps & connections…") { store.send(.settingsOpened(.apps)) }
                #endif
                Button("Sign out of this device") { store.send(.signOutTapped) }
            } label: {
                Portrait(store.state.ownerPortrait, size: 30, isAnimated: false)
                    .clipShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Account")
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(width: 60)
    }
}

/// Hardware-keyboard shortcuts for macOS and iPad.
private struct Shortcuts: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ZStack {
            Button("Search") { store.send(.paletteToggled(!store.isPaletteOpen)) }.keyboardShortcut("k", modifiers: .command)
            Button("Back") { store.send(.backTapped) }.keyboardShortcut("[", modifiers: .command).disabled(store.history.isEmpty)
            Button("Sidebar") { store.send(.sidebarToggled) }.keyboardShortcut("s", modifiers: [.command, .control])
            Button("Side panel") { store.send(.panelToggled) }.keyboardShortcut("0", modifiers: [.command, .option])
            // Esc goes back one layer, unless the palette has it.
            Button("Back one layer") { store.send(.layerPopped) }.keyboardShortcut(.escape, modifiers: []).disabled(store.layers.isEmpty || store.isPaletteOpen)
            Button("Refresh") { store.send(.refreshTapped) }.keyboardShortcut("r", modifiers: .command)
            // ⌘.: the employee of the conversation in view.
            Button("Stop") { store.send(.stopTapped) }.keyboardShortcut(".", modifiers: .command)
                .disabled(store.state.employeeInView.flatMap { store.statuses[$0] }?.isRunning != true)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
