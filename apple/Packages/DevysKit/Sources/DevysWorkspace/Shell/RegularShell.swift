import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One gray frame around one rounded workspace: the sidebar, the conversation in the middle, and
/// the right panel while a layer is open, divided by hairlines. With several businesses, their
/// tiles sit in the frame on the left.
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
                if store.businesses.count > 1 {
                    BusinessStrip(store: store)
                } else {
                    Spacer().frame(width: DevysSpacing.small)
                }
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
            #if os(macOS)
                // A sheet can't close on a click outside it; these panels do, and on Esc.
                if store.isConnectingApps {
                    ConnectAppsSheet(store: store)
                        .frame(maxWidth: 720, maxHeight: 600)
                        .modalPanel { store.send(.connectAppsToggled(false)) }
                        .transition(.opacity)
                }
                if store.isShowingShortcuts {
                    ShortcutsSheet { store.send(.shortcutsToggled(false)) }
                        .modalPanel { store.send(.shortcutsToggled(false)) }
                        .transition(.opacity)
                }
            #endif
            if store.isPaletteOpen {
                CommandPalette(store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.isSidebarVisible)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.state.isPanelOpen)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.state.isWideShown)
        .animation(DevysMotion.quick, value: store.isPaletteOpen)
        .animation(DevysMotion.quick, value: store.isConnectingApps)
        .animation(DevysMotion.quick, value: store.isShowingShortcuts)
        #if os(iOS)
            .sheet(isPresented: Binding(get: { store.isConnectingApps }, set: { if !$0 { store.send(.connectAppsToggled(false)) } })) {
                ConnectAppsSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.isShowingShortcuts }, set: { if !$0 { store.send(.shortcutsToggled(false)) } })) {
                ShortcutsSheet { store.send(.shortcutsToggled(false)) }
            }
        #endif
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
                    ToolbarIconButton("Search (⌘K)", symbol: "magnifyingglass") { store.send(.paletteToggled(true)) }
                }
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
            ToolbarIconButton("Search (⌘K)", symbol: "magnifyingglass") { store.send(.paletteToggled(true)) }
            Spacer(minLength: DevysSpacing.regular)
            #if os(iOS)
                NewMenu(store: store)
            #endif
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

/// Tiles that switch businesses, shown when there are several.
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
            #if !os(macOS)
                // The Mac's menu bar has these (WorkspaceCommands); an iPad keyboard needs them here.
                Button("Search") { store.send(.paletteToggled(!store.isPaletteOpen)) }.keyboardShortcut("k", modifiers: .command)
                Button("New Employee") { store.send(.hireTapped) }.keyboardShortcut("n", modifiers: .command)
                Button("New Project") { store.send(.newProjectTapped) }.keyboardShortcut("n", modifiers: [.command, .shift])
            #endif
            Button("Sidebar") { store.send(.sidebarToggled) }.keyboardShortcut("s", modifiers: [.command, .control])
            // Esc goes back one layer, unless the palette or a panel over the workspace has it.
            Button("Back one layer") { store.send(.layerPopped) }.keyboardShortcut(.escape, modifiers: [])
                .disabled(store.layers.isEmpty || store.isPaletteOpen || store.isConnectingApps || store.isShowingShortcuts)
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
