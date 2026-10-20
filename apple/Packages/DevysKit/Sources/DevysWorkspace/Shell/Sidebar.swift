import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Contextual navigation for the selected rail destination. The selection is
/// one white pill that springs between rows.
struct Sidebar: View {
    let store: StoreOf<Workspace>
    @Namespace private var pill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                header
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                rows
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder private var header: some View {
        if store.destination == .home {
            Text(store.snapshot.businessName).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
        } else {
            Text(store.destination.title).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
        }
    }

    @ViewBuilder private var rows: some View {
        let snapshot = store.snapshot
        switch store.destination {
        case .home:
            row(.today, "Today", symbol: "sun.max")
            row(.approvals, "Approvals", symbol: "faceid", count: store.decisions.value?.count ?? 0)
            row(.files(nil), "Files", symbol: "folder")
            if !snapshot.employees.isEmpty {
                HStack {
                    label("Direct messages")
                    Spacer()
                    SidebarAddButton(title: "Hire") { store.send(.hireTapped) }
                }
                ForEach(snapshot.employees) { employee in
                    row(.direct(employee.id), employee.name, unread: store.state.unread(.direct(employee.id)), trailing: trailing(for: employee)) {
                        Portrait(store.state.portrait(for: employee), size: 20, mood: store.state.mood(for: employee), isAnimated: false)
                    }
                }
            }
            // Work the owner follows; the section is absent until they follow something.
            let followed = (store.work.value ?? []).filter { store.state.isFollowing($0.id) }
            if !followed.isEmpty {
                label("Following")
                ForEach(followed) { item in
                    Button { store.send(.workOpened(item.id)) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "checklist").frame(width: 20).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 4)
                            let unread = store.state.unread(.work(item.id))
                            if unread > 0 { UnreadBadge(count: unread) }
                        }
                        .font(DevysTypography.control).foregroundStyle(DevysColors.ink2)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                label("Spaces")
                Spacer()
                NewSpaceButton(store: store).padding(.trailing, 10)
            }
            ForEach(Array((store.spaces.value ?? []).enumerated()), id: \.element.id) { index, space in
                row(.space(space.id), space.name, unread: store.state.unread(.space(space.id))) {
                    SpaceDot(name: space.name, tint: BusinessTile.Tint.allCases[(index + 1) % BusinessTile.Tint.allCases.count])
                }
            }
        case .inbox:
            quiet("No mailbox is connected yet. The business's mail appears here once one is.")
        case .work:
            ForEach(WorkFilter.allCases, id: \.self) { filter in
                row(.work(filter), filter.rawValue, symbol: symbol(for: filter), count: store.state.work(filter).count)
            }
        case .team:
            ForEach(snapshot.employees) { employee in
                row(.employee(employee.id), employee.name, detail: employee.summary, trailing: trailing(for: employee)) {
                    Portrait(store.state.portrait(for: employee), size: 26, mood: store.state.mood(for: employee), isAnimated: false)
                }
            }
            Button { store.send(.hireTapped) } label: {
                Label("Hire", systemImage: "plus").font(DevysTypography.control).foregroundStyle(DevysColors.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .money:
            row(.money, "Overview", symbol: "chart.bar")
        case .apps:
            ForEach(AppsSection.allCases, id: \.self) { section in
                row(.apps(section), section.rawValue, symbol: section == .installed ? "square.grid.2x2" : "link")
            }
        }
    }

    private func trailing(for employee: Employee) -> SidebarTrailing {
        if employee.paused { return .paused }
        if store.state.isWorking(employee.id) { return .working }
        return store.decisions.value?.contains { $0.employeeID == employee.id } == true ? .needsYou : .none
    }

    private func symbol(for filter: WorkFilter) -> String {
        switch filter {
        case .all: "tray.full"
        case .needsYou: "exclamationmark.circle"
        case .inProgress: "circle.dashed"
        case .waiting: "clock"
        case .done: "checkmark.circle"
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(DevysTypography.label)
            .foregroundStyle(DevysColors.ink3)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func quiet(_ text: String) -> some View {
        Text(text).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).padding(.horizontal, 10)
    }

    private func row(
        _ page: Page,
        _ title: String,
        detail: String? = nil,
        symbol: String? = nil,
        count: Int? = nil,
        unread: Int = 0,
        trailing: SidebarTrailing = .none
    ) -> some View {
        row(page, title, detail: detail, count: count, unread: unread, trailing: trailing) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 20).accessibilityHidden(true)
            }
        }
    }

    private func row(
        _ page: Page,
        _ title: String,
        detail: String? = nil,
        count: Int? = nil,
        unread: Int = 0,
        trailing: SidebarTrailing = .none,
        @ViewBuilder leading: () -> some View
    ) -> some View {
        SidebarRow(
            title: title,
            detail: detail,
            count: count,
            unread: unread,
            trailing: trailing,
            // Files is one page whichever file it opened at.
            selected: store.page == page || (page == .files(nil) && { if case .files = store.page { true } else { false } }()),
            pill: pill,
            leading: leading()
        ) {
            store.send(.pageSelected(page))
        }
    }
}

enum SidebarTrailing: Equatable {
    case none
    case working
    case needsYou
    case paused
}

private struct SidebarRow<Leading: View>: View {
    let title: String
    let detail: String?
    let count: Int?
    /// Unread messages in the row's conversation.
    let unread: Int
    let trailing: SidebarTrailing
    let selected: Bool
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(unread > 0 ? .semibold : nil).lineLimit(1)
                    if let detail {
                        Text(detail).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                switch trailing {
                case .none: EmptyView()
                case .working:
                    Circle().fill(DevysColors.indigo).frame(width: 6, height: 6).accessibilityLabel("working")
                case .needsYou:
                    StatusChip("Needs you", tone: .needsYou, size: .small)
                case .paused:
                    Text("Paused").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                if let count, count > 0 {
                    Text("\(count)").font(DevysTypography.secondary).monospacedDigit().foregroundStyle(DevysColors.ink3)
                }
                if unread > 0 { UnreadBadge(count: unread) }
            }
            .font(DevysTypography.control)
            .foregroundStyle(selected || hovering ? DevysColors.ink : DevysColors.ink2)
            .padding(.horizontal, 10)
            .padding(.vertical, detail == nil ? 7 : 6)
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
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The number of unread messages in a conversation.
struct UnreadBadge: View {
    let count: Int
    @ScaledMetric(relativeTo: .caption2) private var size = 10.5

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: size, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(DevysColors.indigo, in: Capsule())
            .accessibilityLabel("\(count) unread")
    }
}

private struct SpaceDot: View {
    let name: String
    let tint: BusinessTile.Tint

    var body: some View {
        BusinessTile(String(name.prefix(1)), tint: tint, size: 20)
    }
}

/// A small "+" beside a sidebar heading.
struct SidebarAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: "plus", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(DevysColors.ink3)
            .padding(.trailing, 10)
            .help(title)
    }
}
