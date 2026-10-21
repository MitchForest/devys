import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Home's permanent view: everything waiting on the owner, then what is moving and what is
/// stuck. Each row opens its thread; a decision is answered right here.
struct NeedsYou: View {
    let store: StoreOf<Workspace>
    let close: () -> Void

    var body: some View {
        if let home = store.home.value {
            VStack(spacing: 0) {
                PanelHeader(title: home.needsYou.isEmpty ? "At a glance" : "Needs you", close: close)
                PanelBody {
                    if !home.needsYou.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(home.needsYou) { item in
                                if let decision = item.decision, let routine = item.routine {
                                    RoutineProposal(store: store, decision: decision, routine: routine)
                                } else if let decision = item.decision {
                                    DecisionRow(store: store, decision: decision)
                                } else {
                                    NeedsYouRow(store: store, item: item)
                                }
                            }
                        }
                    }
                    if !home.glance.moving.isEmpty {
                        PanelSection(title: "Moving", count: home.glance.moving.count) {
                            ForEach(home.glance.moving) { GlanceRow(store: store, card: $0, stuck: false) }
                        }
                    }
                    if !home.glance.stuck.isEmpty {
                        PanelSection(title: "Stuck", count: home.glance.stuck.count) {
                            ForEach(home.glance.stuck) { GlanceRow(store: store, card: $0, stuck: true) }
                        }
                    }
                }
            }
        }
    }
}

/// One request, answered in place; its input unfolds on demand.
struct DecisionRow: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    @State private var open = false

    var body: some View {
        let employee = store.state.employee(decision.employeeID)
        let item = store.work.value?.first { $0.id == decision.workItemID }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let employee { Portrait(store.state.portrait(for: employee), size: 22, isAnimated: false) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item?.title ?? DecisionText.title(decision)).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text("\(employee?.name ?? "An employee") asks\(item == nil ? "" : " · \(DecisionText.title(decision))")")
                        .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                .lineLimit(1)
            }
            if open { DecisionFields(decision: decision) }
            HStack(spacing: 6) {
                Button("Approve", systemImage: "checkmark") { store.send(.decisionAnswered(decision.id, approve: true)) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
                Button("Decline") { store.send(.decisionAnswered(decision.id, approve: false)) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                Spacer(minLength: 4)
                Button(open ? "Hide details" : "Details") { open.toggle() }
                    .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                if let workID = decision.workItemID {
                    Button("Thread") { store.send(.threadOpened(workID)) }
                        .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
            }
        }
        .devysCard(padding: 12)
    }
}

/// One exact request: who asked, what they will do, and the input it will run with.
struct DecisionCard: View {
    let store: StoreOf<Workspace>
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusChip("Needs approval", tone: .needsYou)
            Text(DecisionText.title(decision)).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
            Text("\(store.state.employeeName(decision.employeeID)) asked to run this exactly:")
                .font(DevysTypography.secondary)
                .foregroundStyle(DevysColors.ink2)
            DecisionFields(decision: decision)
            HStack(spacing: DevysSpacing.small) {
                Button("Approve", systemImage: "checkmark") { store.send(.decisionAnswered(decision.id, approve: true)) }
                    .buttonStyle(.aurora)
                    .help("Allows this exact request once. Face ID signing arrives with signed decisions.")
                Button("Decline") { store.send(.decisionAnswered(decision.id, approve: false)) }
                    .buttonStyle(.raised)
            }
            .padding(.top, 2)
        }
        .devysCard()
    }
}

/// The input a request will run with, key by key.
private struct DecisionFields: View {
    let decision: Decision

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(decision.input.fields, id: \.key) { field in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(field.key).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).frame(minWidth: 56, alignment: .leading)
                    Text(field.value).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink).lineLimit(6).textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Work waiting on the owner that isn't a decision here: it opens its thread.
private struct NeedsYouRow: View {
    let store: StoreOf<Workspace>
    let item: NeedsYouItem

    var body: some View {
        Button { if let workID = item.workID { store.send(.threadOpened(workID)) } } label: {
            HStack(spacing: 10) {
                if let employee = store.state.employee(item.employeeID) {
                    Portrait(store.state.portrait(for: employee), size: 22, isAnimated: false)
                }
                Text(item.title).font(DevysTypography.control).foregroundStyle(DevysColors.ink).lineLimit(1)
                Spacer(minLength: 4)
                if item.workID != nil {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                }
            }
            .devysCard(padding: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.workID == nil)
    }
}

/// A moving or stuck work item; stuck ones say what they wait on.
private struct GlanceRow: View {
    let store: StoreOf<Workspace>
    let card: GlanceItem
    let stuck: Bool
    @State private var hovering = false

    var body: some View {
        Button { store.send(.threadOpened(card.id)) } label: {
            HStack(spacing: 10) {
                if let employee = store.state.employee(card.employeeID) {
                    Portrait(store.state.portrait(for: employee), size: 20, isAnimated: false)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title).font(DevysTypography.secondary.weight(.medium)).foregroundStyle(DevysColors.ink).lineLimit(1)
                    if stuck {
                        Text(card.waitCondition.map { "Waiting on \($0)" } ?? "No change in a day")
                            .font(DevysTypography.caption).foregroundStyle(DevysColors.red).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovering ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, -8)
    }
}
