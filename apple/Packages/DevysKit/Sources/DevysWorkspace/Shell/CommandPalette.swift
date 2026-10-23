import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// ⌘K, as Grok Bot draws it: a Search field over rows (a face or symbol, a title, a grey second
/// line, and ⌘1…⌘9 for the first nine). It jumps to people and projects, runs the app's actions
/// and opens Settings at a section; typing also finds threads and pages.
struct CommandPalette: View {
    let store: StoreOf<Workspace>
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    #if os(macOS)
        @Environment(\.openSettings) private var openSettings
    #endif

    private var rows: [PaletteRow] { store.state.paletteRows(query) }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(DevysTypography.heading.weight(.regular))
                    .focused($focused)
                    .onSubmit { if rows.indices.contains(selection) { run(rows[selection]) } }
                    .onKeyPress(.downArrow) {
                        selection = min(selection + 1, max(rows.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selection = max(selection - 1, 0)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        store.send(.paletteToggled(false))
                        return .handled
                    }
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            PaletteRowView(store: store, row: row, index: index, selected: index == selection) { run(row) }
                                .id(row.id)
                                .onHover { if $0 { selection = index } }
                        }
                        if rows.isEmpty {
                            Text("No matches").font(DevysTypography.body).foregroundStyle(DevysColors.ink3).padding(12)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selection) {
                    if rows.indices.contains(selection) { proxy.scrollTo(rows[selection].id) }
                }
            }
            .frame(height: 380)
        }
        .frame(maxWidth: 560)
        .modalPanel(alignment: .top) { store.send(.paletteToggled(false)) }
        .background { numberKeys(rows) }
        .onChange(of: query) { selection = 0 }
        .onAppear { focused = true }
    }

    /// ⌘1…⌘9 run the first nine rows while the palette is open.
    private func numberKeys(_ rows: [PaletteRow]) -> some View {
        ZStack {
            ForEach(Array(rows.prefix(9).enumerated()), id: \.element.id) { index, row in
                Button(row.title) { run(row) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func run(_ row: PaletteRow) {
        store.send(.paletteRan(row.command))
        #if os(macOS)
            // Settings is its own window on the Mac; the workspace has already chosen the section.
            if case .settings = row.command { openSettings() }
        #endif
    }
}

private struct PaletteRowView: View {
    let store: StoreOf<Workspace>
    let row: PaletteRow
    let index: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon.frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(DevysTypography.control).foregroundStyle(DevysColors.ink).lineLimit(1)
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(DevysTypography.caption.monospacedDigit())
                        .foregroundStyle(DevysColors.ink3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .accessibilityLabel("Command \(index + 1)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var icon: some View {
        switch row.icon {
        case .employee(let id):
            if let employee = store.state.employee(id) {
                Portrait(store.state.portrait(for: employee), size: 28, isAnimated: false)
            }
        case .project(let id):
            BusinessTile(String(row.title.prefix(1)), tint: store.state.projectTint(id), size: 28)
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DevysColors.ink2)
                .frame(width: 28, height: 28)
                .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// A rounded panel over a dimmed backdrop: a click or tap on the backdrop closes it, as Esc does.
struct ModalPanel: ViewModifier {
    let alignment: Alignment
    let close: () -> Void

    func body(content: Content) -> some View {
        ZStack(alignment: alignment) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
            content
                .background(DevysColors.sheet)
                .clipShape(RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous).strokeBorder(DevysColors.hairline, lineWidth: 1)
                }
                .devysElevation(.raised)
                .padding(.horizontal, DevysSpacing.regular)
                .padding(.top, alignment == .top ? 90 : DevysSpacing.regular)
                .padding(.bottom, DevysSpacing.regular)
        }
    }
}

extension View {
    /// Shows this view as a panel over a dimmed backdrop whose tap runs `close`.
    func modalPanel(alignment: Alignment = .center, close: @escaping () -> Void) -> some View {
        modifier(ModalPanel(alignment: alignment, close: close))
    }
}

/// The app's keyboard shortcuts, opened from ⌘K.
struct ShortcutsSheet: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                Spacer()
                ToolbarIconButton("Close", symbol: "xmark", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
            VStack(spacing: 0) {
                ForEach(KeyboardShortcutList.entries, id: \.title) { entry in
                    HStack {
                        Text(entry.title).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
                        Spacer()
                        Text(entry.keys)
                            .font(DevysTypography.control.monospacedDigit())
                            .foregroundStyle(DevysColors.ink2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 420)
    }
}
