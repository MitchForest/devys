import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

struct Metric: View {
    let label: String
    let value: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            Text(value).font(DevysTypography.title).monospacedDigit().foregroundStyle(DevysColors.ink)
            Text(note).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
        }
        .devysCard()
    }
}

/// One commitment: what, who, what's next and its state. Click to open it in the right panel; right-click to act on it.
struct WorkRow: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    @State private var hovering = false

    var body: some View {
        HStack(spacing: DevysSpacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                Text(detail).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(2)
            }
            Spacer(minLength: DevysSpacing.compact)
            if item.takenOverBy != nil {
                Text("You have it").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
            }
            item.state.chip
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hovering ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { store.send(.workOpened(item.id)) }
        .onHover { hovering = $0 }
        .animation(DevysMotion.quick, value: hovering)
        .contextMenu { WorkActions(store: store, item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.send(.workOpened(item.id)) }
    }

    private var detail: String {
        let owner = store.state.employeeName(item.ownerEmployeeID)
        if let wait = item.waitCondition, item.state == .waiting { return "\(owner) · waiting on \(wait)" }
        if let done = item.evidence.last, item.state == .completed { return "\(owner) · \(done.note)" }
        return item.nextAction.isEmpty ? owner : "\(owner) · \(item.nextAction)"
    }
}

/// The same actions an employee has, applied by the owner at the revision on screen.
struct WorkActions: View {
    let store: StoreOf<Workspace>
    let item: Commitment

    var body: some View {
        Button("Open", systemImage: "arrow.up.right.square") { store.send(.workOpened(item.id)) }
        if item.state.isOpen {
            Menu("Reassign to") {
                ForEach(store.preview.employees.filter { $0.id != item.ownerEmployeeID }) { employee in
                    Button(employee.name) { store.send(.reassigned(item.id, to: employee.id)) }
                }
            }
            if item.state != .ready { Button("Mark ready", systemImage: "arrow.uturn.forward") { store.send(.commitmentStateSet(item.id, .ready)) } }
            if item.state != .waiting { Button("Mark waiting", systemImage: "clock") { store.send(.commitmentStateSet(item.id, .waiting)) } }
            Button("Mark done", systemImage: "checkmark.circle") { store.send(.commitmentStateSet(item.id, .completed)) }
            Divider()
            Button(item.takenOverBy == nil ? "Take over" : "Hand back", systemImage: item.takenOverBy == nil ? "hand.raised" : "arrowshape.turn.up.left") {
                store.send(.takeoverToggled(item.id))
            }
            Button("Cancel", systemImage: "xmark.circle", role: .destructive) { store.send(.commitmentStateSet(item.id, .cancelled)) }
            if let spaces = store.spaces.value, !spaces.isEmpty {
                Menu("Add to space") {
                    ForEach(spaces) { space in
                        Button(space.name) { store.send(.spaceItemAdded(space.id, .commitment, item.id)) }
                    }
                }
            }
        } else {
            Button("Reopen", systemImage: "arrow.uturn.backward") { store.send(.commitmentStateSet(item.id, .ready)) }
        }
    }
}
