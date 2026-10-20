import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One gray frame (toolbar and rail) around one rounded workspace holding the
/// sidebar, the page and the inspector, divided by hairlines.
struct RegularShell: View {
    #if os(macOS)
        static let sidebarWidth: CGFloat = 236
    #else
        static let sidebarWidth: CGFloat = 270
    #endif

    let store: StoreOf<Workspace>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("inspectorWidth") private var inspectorWidth = 320.0

    var body: some View {
        VStack(spacing: 0) {
            #if !os(macOS)
                ShellToolbar(store: store)
            #endif
            HStack(spacing: 0) {
                Rail(store: store)
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
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.isInspectorVisible)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : DevysMotion.panel, value: store.state.hasInspectorContent)
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
                inspectorVisible: store.isInspectorVisible && store.state.hasInspectorContent,
                preferredInspector: inspectorWidth
            )
            // Every column is always present at an explicit width; showing,
            // hiding and expanding animate widths, so motion stays continuous.
            HStack(spacing: 0) {
                Sidebar(store: store)
                    .frame(width: Self.sidebarWidth)
                    .frame(width: layout.sidebar, alignment: .trailing)
                    .clipped()
                    .background(DevysColors.sheetTint)
                Hairline().opacity(layout.sidebar > 0 ? 1 : 0).frame(width: layout.sidebar > 0 ? 1 : 0)
                MainPane(store: store)
                    .frame(width: max(layout.page, WorkspaceLayout.minimumPage))
                    .frame(width: layout.page, alignment: .leading)
                    .clipped()
                    .opacity(layout.page > 0 ? 1 : 0)
                    .background(DevysColors.sheet)
                ResizeHandle(width: $inspectorWidth)
                    .frame(width: layout.showsHandle ? WorkspaceLayout.handle : 0)
                    .opacity(layout.showsHandle ? 1 : 0)
                    .allowsHitTesting(layout.showsHandle)
                Inspector(store: store)
                    .frame(width: max(layout.inspector, WorkspaceLayout.inspectorRange.lowerBound))
                    .frame(width: layout.inspector, alignment: .leading)
                    .clipped()
                    .background(DevysColors.sheet)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
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

    static let range = 280.0...640.0

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
            .onTapGesture(count: 2) { width = 320 }
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
                    Breadcrumb(store: store).padding(.leading, 6)
                }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    PresenceStrip(store: store)
                    SearchPill { store.send(.paletteToggled(true)) }
                    InspectorToggle(store: store)
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
            Breadcrumb(store: store).padding(.leading, 6)
            Spacer(minLength: DevysSpacing.regular)
            PresenceStrip(store: store)
            SearchPill { store.send(.paletteToggled(true)) }
            InspectorToggle(store: store)
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

private struct InspectorToggle: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ToolbarIconButton(store.isInspectorVisible ? "Hide inspector (⌥⌘0)" : "Show inspector (⌥⌘0)", symbol: "sidebar.right") {
            store.send(.inspectorToggled)
        }
        .disabled(!store.state.hasInspectorContent)
    }
}

private struct Breadcrumb: View {
    let store: StoreOf<Workspace>

    var body: some View {
        HStack(spacing: 6) {
            Text(store.snapshot.businessName).foregroundStyle(DevysColors.ink3)
            Text("/").foregroundStyle(DevysColors.ink3)
            Text(store.pageTitle).foregroundStyle(DevysColors.ink).fontWeight(.semibold)
                .contentTransition(.opacity)
        }
        .font(DevysTypography.control)
        .fixedSize()
    }
}

/// Who is working and who is waiting on you, as overlapping Faces.
/// Teammates worth a glance: working, waiting on you, failed or stopped.
/// Click to act, hover to read, right-click for more.
private struct PresenceStrip: View {
    let store: StoreOf<Workspace>

    var body: some View {
        let presence = store.state.presence
        HStack(spacing: 4) {
            ForEach(presence.prefix(4)) { item in
                PresenceFace(store: store, presence: item)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(DevysMotion.select, value: presence)
    }
}

private struct PresenceFace: View {
    let store: StoreOf<Workspace>
    let presence: Presence
    @State private var hovering = false
    @ScaledMetric(relativeTo: .caption2) private var countSize = 9.0

    private var isOperations: Bool { presence.employee.id == store.operations?.id }

    var body: some View {
        Button {
            store.send(.presenceTapped(presence.employee.id))
        } label: {
            Portrait(store.state.portrait(for: presence.employee), size: 22, mood: mood, isAnimated: false)
                .overlay { if presence.signal == .working { WorkingRing() } }
                .overlay(alignment: .topTrailing) { badge.offset(x: 5, y: -4) }
                .padding(4)
                .background(hovering ? DevysColors.track : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(presence.summary)
        .accessibilityLabel(presence.summary)
        .contextMenu {
            Button("Message", systemImage: "bubble.left") { store.send(.pageSelected(.direct(presence.employee.id))) }
            if case .needsYou = presence.signal {
                Button("Review decisions", systemImage: "checkmark.seal") { store.send(.pageSelected(.approvals)) }
            }
            Button("Open profile", systemImage: "person.crop.circle") { store.send(.pageSelected(.employee(presence.employee.id))) }
            Divider()
            if presence.employee.paused {
                Button("Resume", systemImage: "play.circle") { store.send(.pauseToggled(presence.employee.id)) }
            } else {
                Button("Pause", systemImage: "pause.circle") { store.send(.pauseToggled(presence.employee.id)) }
            }
            if isOperations, presence.signal == .working {
                Button("Stop", systemImage: "stop.circle", role: .destructive) { store.send(.stopTapped) }
            }
        }
    }

    private var mood: BotMood {
        switch presence.signal {
        case .working: .working
        case .needsYou: .waiting
        case .failed: .oops
        case .paused: .off
        }
    }

    @ViewBuilder private var badge: some View {
        switch presence.signal {
        case .working:
            EmptyView()
        case .needsYou(let count):
            Text("\(count)")
                .font(.system(size: countSize, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 14, minHeight: 14)
                .background(DevysColors.amber, in: Capsule())
                .overlay { Capsule().strokeBorder(DevysColors.frame, lineWidth: 1.5) }
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(DevysColors.red, in: Circle())
                .overlay { Circle().strokeBorder(DevysColors.frame, lineWidth: 1.5) }
        case .paused:
            Capsule()
                .fill(DevysColors.gray)
                .frame(width: 8, height: 3)
                .padding(3.5)
                .background(DevysColors.frame, in: Circle())
        }
    }
}

/// A slow indigo arc around a working teammate.
private struct WorkingRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let angle = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 * 360
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .inset(by: -2.5)
                .stroke(
                    AngularGradient(colors: [DevysColors.indigo, DevysColors.indigo.opacity(0)], center: .center, angle: .degrees(angle)),
                    lineWidth: 1.75
                )
        }
        .accessibilityHidden(true)
    }
}

private struct SearchPill: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                Text("⌘K").font(DevysTypography.caption)
            }
            .foregroundStyle(DevysColors.ink3)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(hovering ? DevysColors.track.opacity(0.8) : DevysColors.track, in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Search (⌘K)")
        .accessibilityLabel("Search")
    }
}

private struct Rail: View {
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
            Rectangle().fill(DevysColors.hairline).frame(width: 24, height: 1).padding(.vertical, 8)
            ForEach(Destination.allCases) { destination in
                RailButton(
                    destination: destination,
                    selected: store.destination == destination,
                    badge: destination == .home ? (store.decisions.value?.count ?? 0) + store.state.unreadConversations : 0
                ) {
                    store.send(.destinationSelected(destination))
                }
            }
            Spacer()
            Menu {
                if let name = store.account?.person.displayName { Text(name) }
                Text(store.server.host() ?? store.server.absoluteString)
                Divider()
                #if os(macOS)
                    SettingsLink { Text("Settings…") }
                #else
                    Button("Settings") { store.send(.preferencesToggled(true)) }
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

private struct RailButton: View {
    let destination: Destination
    let selected: Bool
    let badge: Int
    let action: () -> Void
    @State private var hovering = false
    @ScaledMetric(relativeTo: .caption2) private var badgeSize = 9.5

    var body: some View {
        Button(action: action) {
            Image(systemName: destination.symbol)
                .font(.system(size: 15, weight: .medium))
                .symbolVariant(selected ? .fill : .none)
                .foregroundStyle(selected || hovering ? DevysColors.ink : DevysColors.ink2)
                .frame(width: 38, height: 38)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DevysColors.sheet).devysElevation(.resting)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DevysColors.track)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: badgeSize, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(DevysColors.auroraRose, in: Capsule())
                            .offset(x: -3, y: 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(DevysMotion.quick, value: hovering)
        .help(destination.title)
        .accessibilityLabel(badge > 0 ? "\(destination.title), \(badge)" : destination.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Hardware-keyboard shortcuts for macOS and iPad.
private struct Shortcuts: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ZStack {
            ForEach(Array(Destination.allCases.enumerated()), id: \.element) { index, destination in
                Button(destination.title) { store.send(.destinationSelected(destination)) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Button("Search") { store.send(.paletteToggled(!store.isPaletteOpen)) }.keyboardShortcut("k", modifiers: .command)
            Button("Sidebar") { store.send(.sidebarToggled) }.keyboardShortcut("s", modifiers: [.command, .control])
            Button("Inspector") { store.send(.inspectorToggled) }.keyboardShortcut("0", modifiers: [.command, .option])
            Button("Refresh") { store.send(.refreshTapped) }.keyboardShortcut("r", modifiers: .command)
            Button("Stop") { store.send(.stopTapped) }.keyboardShortcut(".", modifiers: .command).disabled(!store.isRunning)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
