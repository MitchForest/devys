import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A persistent place: a header with its name and tabs, its conversation first, then its
/// overview, work and files.
struct SpacePage: View {
    let store: StoreOf<Workspace>
    let spaceID: String

    var body: some View {
        if let space = store.spaces.value?.first(where: { $0.id == spaceID }) {
            let refs = Set(space.refs(.commitment))
            let work = (store.work.value ?? []).filter { refs.contains($0.id) }
            VStack(spacing: 0) {
                header(space)
                Rectangle().fill(DevysColors.hairline).frame(height: 1)
                Group {
                    switch store.spaceTab {
                    case .conversation:
                        ConversationPane(store: store, key: .space(space.id), voice: true)
                    case .overview:
                        PageBody { SpaceOverview(store: store, space: space, work: work) }
                    case .work:
                        PageBody { workList(work, space: space) }
                    case .files:
                        PageBody { SpaceFiles(store: store, space: space) }
                    }
                }
                .transaction { $0.animation = nil }
            }
        } else if case .loading = store.spaces {
            PageBody { ProgressView() }
        } else {
            PageBody { EmptyNote(text: "This space no longer exists.") }
        }
    }

    private func header(_ space: Space) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BusinessTile(String(space.name.prefix(1)), tint: .blue, size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(space.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                    if !space.purpose.isEmpty {
                        Text(space.purpose).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button("New task", systemImage: "plus") { store.send(.newTaskTapped(space: space.id)) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    .fixedSize()
            }
            SegmentedTabs(
                selection: Binding(get: { store.spaceTab }, set: { store.send(.spaceTabSelected($0)) }),
                options: SpaceTab.allCases.map { (value: $0, title: $0.rawValue) }
            )
        }
        .padding(.horizontal, DevysSpacing.regular)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func workList(_ work: [Commitment], space: Space) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            HStack {
                SectionHeader("Work", count: work.count)
                Spacer()
                Button("New task", systemImage: "plus") { store.send(.newTaskTapped(space: space.id)) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    .fixedSize()
            }
            if work.isEmpty { EmptyNote(text: "Nothing here yet. Create a task, or add work from its menu under Work.") }
            ForEach(work) { item in
                WorkRow(store: store, item: item)
                    .contextMenu {
                        WorkActions(store: store, item: item)
                        if let entry = space.items.first(where: { $0.kind == .commitment && $0.ref == item.id }) {
                            Divider()
                            Button("Remove from \(space.name)", systemImage: "minus.circle") {
                                store.send(.spaceItemRemoved(space.id, entry.id))
                            }
                        }
                    }
            }
        }
    }
}

/// What the space is for, who leads it, who takes part, and what it holds.
private struct SpaceOverview: View {
    let store: StoreOf<Workspace>
    let space: Space
    let work: [Commitment]

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            Text("Purpose").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            Text(space.purpose.isEmpty ? "No purpose written yet." : space.purpose)
                .font(DevysTypography.body)
                .foregroundStyle(space.purpose.isEmpty ? DevysColors.ink3 : DevysColors.ink)
            lead
        }
        .devysCard()
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            SectionHeader("Participants", count: participants.count)
            HStack(spacing: 10) {
                ForEach(participants) { employee in
                    VStack(spacing: 4) {
                        Portrait(store.state.portrait(for: employee), size: 32, mood: employee.activity.mood, label: employee.name, isAnimated: false)
                        Text(employee.name).font(DevysTypography.caption).foregroundStyle(DevysColors.ink2).lineLimit(1)
                    }
                    .frame(maxWidth: 88)
                    .onTapGesture { store.send(.pageSelected(.direct(employee.id))) }
                }
            }
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: DevysSpacing.compact)], spacing: DevysSpacing.compact) {
            Metric(label: "Open", value: "\(work.filter(\.state.isOpen).count)", note: "\(work.filter { $0.state == .needsDecision }.count) need you")
            Metric(label: "In progress", value: "\(work.filter { $0.state == .inProgress }.count)", note: "\(work.filter { $0.state == .waiting }.count) waiting")
            Metric(label: "Done", value: "\(work.filter { $0.state == .completed }.count)", note: "with evidence")
        }
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            SectionHeader("Items", count: space.items.count)
            if space.items.isEmpty { EmptyNote(text: "Work and files shown here keep their one home; the space only references them.") }
            ForEach(work.prefix(6)) { WorkRow(store: store, item: $0) }
            ForEach(store.artifacts.filter { space.refs(.artifact).contains($0.id) }) { file in
                Label(file.filename, systemImage: "doc")
                    .font(DevysTypography.body)
                    .foregroundStyle(DevysColors.ink2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder private var lead: some View {
        let lead = space.leadEmployeeID.flatMap { id in store.preview.employees.first { $0.id == id } }
        HStack(spacing: 10) {
            if let lead {
                Portrait(store.state.portrait(for: lead), size: 26, isAnimated: false)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Lead").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                Text(lead?.name ?? "No lead").font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
            }
            Spacer(minLength: 8)
            Menu {
                ForEach(store.preview.employees.filter { $0.id != lead?.id }) { employee in
                    Button(employee.name) { store.send(.spaceLeadChanged(space.id, employee.id)) }
                }
            } label: {
                Text("Change")
            }
            .menuIndicator(.hidden)
            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            .fixedSize()
            .help("The lead answers the space's conversation until someone else speaks or is mentioned")
        }
        .padding(.top, 4)
    }

    private var participants: [Employee] { store.state.participants(in: space) }
}
