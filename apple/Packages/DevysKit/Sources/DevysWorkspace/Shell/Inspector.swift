import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

extension Workspace.State {
    /// The right panel has something to show: it only ever holds a work item.
    var hasInspectorContent: Bool {
        selectedWorkID != nil
    }

    /// Conversations with unread messages, for the Home badge.
    var unreadConversations: Int {
        summaries.values.filter { $0.unread > 0 }.count
    }
}

/// The right panel: the selected work item with its own thread. Who an employee or a space is
/// lives in a popover on the conversation's header, so nothing stays on screen unasked.
struct Inspector: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let id = store.state.selectedWorkID {
            WorkPanel(store: store, commitmentID: id, closable: true)
        }
    }
}

/// Wraps a conversation header's title so a click shows who or what it is.
struct AboutButton<Label: View, About: View>: View {
    let name: String
    @ViewBuilder let label: () -> Label
    @ViewBuilder let about: () -> About
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(name)")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DevysSpacing.compact) { about() }
                        .padding(14)
                        .frame(width: 300, alignment: .leading)
                }
                .frame(maxHeight: 420)
                .presentationCompactAdaptation(.popover)
            }
    }
}

/// A DM's employee: who they are, what they're doing, and their open work.
struct DirectInfo: View {
    let store: StoreOf<Workspace>
    let employeeID: String

    var body: some View {
        if let employee = store.snapshot.employees.first(where: { $0.id == employeeID }) {
            HStack(spacing: 10) {
                Portrait(store.state.portrait(for: employee), size: 40, mood: store.state.mood(for: employee), label: employee.name)
                VStack(alignment: .leading, spacing: 1) {
                    Text(employee.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                    Text(EmployeeLine.status(employee, working: store.state.isWorking(employee.id)))
                        .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                }
            }
            Text(employee.role).font(DevysTypography.body).foregroundStyle(DevysColors.ink2).lineLimit(6)
            Button("Open profile", systemImage: "person.crop.circle") { store.send(.pageSelected(.employee(employee.id))) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .fixedSize()
            OpenWork(store: store, items: (store.work.value ?? []).filter { $0.ownerEmployeeID == employee.id && $0.state.isOpen })
        }
    }
}

/// A space: its purpose, its lead, who's here, and its open work.
struct SpaceInfo: View {
    let store: StoreOf<Workspace>
    let spaceID: String

    var body: some View {
        if let space = store.spaces.value?.first(where: { $0.id == spaceID }) {
            Text(space.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
            if !space.purpose.isEmpty {
                Text(space.purpose).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
            }
            Text("Who's here").font(DevysTypography.label).foregroundStyle(DevysColors.ink3).padding(.top, 6)
            ForEach(store.state.participants(in: space)) { employee in
                HStack(spacing: 8) {
                    Portrait(store.state.portrait(for: employee), size: 22, mood: store.state.mood(for: employee), isAnimated: false)
                    Text(employee.name).font(DevysTypography.control).foregroundStyle(DevysColors.ink)
                    if employee.id == space.leadEmployeeID {
                        Text("Lead").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { store.send(.pageSelected(.direct(employee.id))) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens a direct message")
                .accessibilityAction { store.send(.pageSelected(.direct(employee.id))) }
            }
            let refs = Set(space.refs(.commitment))
            OpenWork(store: store, items: (store.work.value ?? []).filter { refs.contains($0.id) && $0.state.isOpen })
        }
    }
}

private struct OpenWork: View {
    let store: StoreOf<Workspace>
    let items: [Commitment]

    var body: some View {
        if !items.isEmpty {
            Text("Open work").font(DevysTypography.label).foregroundStyle(DevysColors.ink3).padding(.top, 6)
            ForEach(items) { item in
                Button { store.send(.workOpened(item.id)) } label: {
                    HStack(spacing: 8) {
                        Text(item.title).font(DevysTypography.control).foregroundStyle(DevysColors.ink).lineLimit(1)
                        Spacer(minLength: 4)
                        item.state.chip
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

extension Workspace.State {
    /// A space's lead, whoever owns its work, and whoever has spoken in its conversation.
    func participants(in space: Space) -> [Employee] {
        let refs = Set(space.refs(.commitment))
        var ids = Set((work.value ?? []).filter { refs.contains($0.id) }.map(\.ownerEmployeeID))
        if let lead = space.leadEmployeeID { ids.insert(lead) }
        if main?.key == .space(space.id) { ids.formUnion((main?.messages.value ?? []).compactMap(\.employeeID)) }
        return snapshot.employees.filter { ids.contains($0.id) }
    }
}

/// How an employee's state reads in a header.
enum EmployeeLine {
    static func status(_ employee: Employee, working: Bool) -> String {
        if employee.paused { return "Paused" }
        return working ? "Working…" : "Available"
    }
}
