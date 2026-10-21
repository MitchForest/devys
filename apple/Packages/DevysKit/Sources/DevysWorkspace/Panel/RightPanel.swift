import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The right panel: the permanent view of what the conversation is about, with temporary
/// layers stacked over it. ‹ and Esc go back one layer; × returns to the permanent view.
/// On iPhone it is a sheet, which `onClose` dismisses.
struct RightPanel: View {
    let store: StoreOf<Workspace>
    var onClose: (() -> Void)?

    var body: some View {
        if let top = store.state.topLayer {
            VStack(spacing: 0) {
                PanelHeader(
                    title: store.state.reference(for: top).title,
                    back: store.layers.count > 1 ? { store.send(.layerPopped) } : nil,
                    closeLabel: "Close (back to the panel)",
                    close: {
                        store.send(.layersClosed)
                        onClose?()
                    },
                    trailing: {
                        if let record = top.ref, Layer(ref: record) != nil { KeepInProject(store: store, record: record) }
                        #if os(macOS)
                            widen
                        #else
                            if onClose == nil { widen }
                        #endif
                    }
                )
                LayerView(store: store, layer: top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            permanent
        }
    }

    private var widen: some View {
        ToolbarIconButton(store.isWide ? "Narrow" : "Widen", symbol: store.isWide ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
            store.send(.wideToggled)
        }
    }

    @ViewBuilder private var permanent: some View {
        let close = onClose ?? { store.send(.panelToggled) }
        switch store.place {
        case .home: NeedsYou(store: store, close: close)
        case .direct(let id): Desk(store: store, employeeID: id, close: close).id(id)
        case .project(let id): Overview(store: store, projectID: id, close: close).id(id)
        case .thread(let id): WorkCard(store: store, workItemID: id, close: close).id(id)
        }
    }
}

/// A panel's header: Back (when layered), the title, its own buttons and ×.
struct PanelHeader<Title: View, Trailing: View>: View {
    @ViewBuilder let title: Title
    var detail: String?
    var back: (() -> Void)?
    var closeLabel = "Hide side panel"
    let close: () -> Void
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if let back { ToolbarIconButton("Back", symbol: "chevron.left", action: back) }
                VStack(alignment: .leading, spacing: 1) {
                    title.font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink).lineLimit(1)
                    if let detail { Text(detail).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1) }
                }
                .padding(.leading, back == nil ? 6 : 0)
                Spacer(minLength: 4)
                trailing
                ToolbarIconButton(closeLabel, symbol: "xmark", action: close)
            }
            .padding(.horizontal, 10)
            .frame(height: 52)
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
        }
    }
}

extension PanelHeader where Title == Text {
    init(
        title: String,
        detail: String? = nil,
        back: (() -> Void)? = nil,
        closeLabel: String = "Hide side panel",
        close: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(title: { Text(title) }, detail: detail, back: back, closeLabel: closeLabel, close: close, trailing: trailing)
    }
}

extension PanelHeader where Title == Text, Trailing == EmptyView {
    init(title: String, close: @escaping () -> Void) {
        self.init(title: { Text(title) }, close: close, trailing: { EmptyView() })
    }
}

/// A permanent view's scrolling body.
struct PanelBody<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
        }
    }
}

/// A labelled group inside a panel; callers leave it out when it has nothing.
struct PanelSection<Action: View, Content: View>: View {
    let title: String
    /// Shown after the title when given.
    var count: Int?
    @ViewBuilder let action: Action
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(count.map { "\(title) · \($0)" } ?? title).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                action
            }
            content
        }
    }
}

extension PanelSection where Action == EmptyView {
    init(title: String, count: Int? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, count: count, action: { EmptyView() }, content: content)
    }
}

/// A small text button beside a panel section's title, as "+ Work item".
struct PanelAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: "plus").labelStyle(.titleAndIcon) }
            .buttonStyle(.plain)
            .font(DevysTypography.caption)
            .foregroundStyle(DevysColors.ink3)
    }
}

/// Keeps a page or file on a project's overview: a reference, so the record stays in its app.
/// Says where it is kept; dashed while it is kept nowhere. Any version of a page keeps the page.
struct KeepInProject: View {
    let store: StoreOf<Workspace>
    let record: Ref

    var body: some View {
        let all = store.projects.value ?? []
        let keptIn = all.filter { store.state.keptEntry(of: record, in: $0) != nil }
        if !all.isEmpty {
            Menu {
                ForEach(all) { project in
                    if let entry = store.state.keptEntry(of: record, in: project) {
                        Button("Remove from \(project.name)") { store.send(.projectItemRemoved(project.id, entry.id)) }
                    } else {
                        Button("Keep in \(project.name)") { store.send(.projectItemAdded(project.id, record)) }
                    }
                }
            } label: {
                Label(keptIn.isEmpty ? "Keep" : keptIn.map(\.name).joined(separator: ", "), systemImage: "folder.badge.plus")
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .overlay {
                        if keptIn.isEmpty {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(DevysColors.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                                .padding(-4)
                        }
                    }
            }
            .menuIndicator(.hidden)
            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            .fixedSize()
        }
    }
}
