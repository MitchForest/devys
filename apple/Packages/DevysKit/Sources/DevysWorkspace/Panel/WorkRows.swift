import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One work item: what, who, what's next and its state. Click to open its thread; right-click to
/// act on it. Compact rows sit in a permanent view.
struct WorkRow: View {
    let store: StoreOf<Workspace>
    let item: WorkItem
    var compact = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DevysSpacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(compact ? DevysTypography.secondary.weight(.medium) : DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    .lineLimit(compact ? 1 : nil)
                Text(detail).font(compact ? DevysTypography.caption : DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(compact ? 1 : 2)
            }
            Spacer(minLength: DevysSpacing.compact)
            if item.state.isOpen, let takeover = store.state.takeoverTitle(item) {
                Text(takeover).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
            }
            item.state.chip(size: compact ? .small : .regular)
        }
        .padding(.horizontal, compact ? 8 : 12)
        .padding(.vertical, compact ? 6 : 10)
        .background(hovering ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .padding(.horizontal, compact ? -8 : 0)
        .onTapGesture { store.send(.threadOpened(item.id)) }
        .onHover { hovering = $0 }
        .animation(DevysMotion.quick, value: hovering)
        .contextMenu { WorkActions(store: store, item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.send(.threadOpened(item.id)) }
    }

    private var detail: String {
        let owner = store.state.employeeName(item.ownerEmployeeID)
        if item.state == .waiting, let waiting = RoutineText.waiting(item) { return "\(owner) · \(waiting)" }
        if let done = item.evidence.last, item.state == .completed { return "\(owner) · \(done.note)" }
        return item.nextAction.isEmpty ? owner : "\(owner) · \(item.nextAction)"
    }
}

/// What the owner can do to a work item from a row: open its thread and take it over. Changing it
/// by hand (reassigning, marking it, cancelling) is for work the owner has taken over; otherwise
/// they ask in its thread.
struct WorkActions: View {
    let store: StoreOf<Workspace>
    let item: WorkItem

    var body: some View {
        Button("Open thread", systemImage: "arrow.up.right.square") { store.send(.threadOpened(item.id)) }
        if item.state.isOpen {
            TakeoverButton(store: store, item: item)
        }
        if item.state.isOpen, store.state.isMine(item) {
            Divider()
            Menu("Reassign to") {
                ForEach(store.snapshot.employees.filter { $0.id != item.ownerEmployeeID }) { employee in
                    Button(employee.name) { store.send(.reassigned(item.id, to: employee.id)) }
                }
            }
            if item.state != .ready { Button("Mark ready", systemImage: "arrow.uturn.forward") { store.send(.workItemStateSet(item.id, .ready)) } }
            if item.state != .waiting { Button("Mark waiting", systemImage: "clock") { store.send(.workItemStateSet(item.id, .waiting)) } }
            Button("Mark done", systemImage: "checkmark.circle") { store.send(.workItemStateSet(item.id, .completed)) }
            Button("Cancel", systemImage: "xmark.circle", role: .destructive) { store.send(.workItemStateSet(item.id, .cancelled)) }
        }
    }
}

/// Take over a work item from its employee, or hand it back when the signed-in person has it.
/// Nothing when someone else has taken it over.
struct TakeoverButton: View {
    let store: StoreOf<Workspace>
    let item: WorkItem

    var body: some View {
        if item.takenOverBy == nil {
            Button("Take over", systemImage: "hand.raised") { store.send(.takeoverToggled(item.id)) }
        } else if store.state.isMine(item) {
            Button("Hand back", systemImage: "arrowshape.turn.up.left") { store.send(.takeoverToggled(item.id)) }
        }
    }
}
