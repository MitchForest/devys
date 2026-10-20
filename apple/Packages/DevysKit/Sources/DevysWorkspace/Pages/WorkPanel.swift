import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One commitment in the right panel (pushed on iPhone): who owns it, its state, what's
/// next, what it waits on, when it's due, its decisions and evidence, then its own thread.
struct WorkPanel: View {
    let store: StoreOf<Workspace>
    let commitmentID: String
    /// In the right panel it closes; on iPhone navigation pops it instead.
    var closable = false
    @Dependency(\.runtimeClient) private var runtime
    /// This item's requests the owner already answered.
    @State private var answered: [Decision] = []

    private var key: ConversationKey { .work(commitmentID) }

    var body: some View {
        VStack(spacing: 0) {
            if let item = store.work.value?.first(where: { $0.id == commitmentID }) {
                header(item)
                ScrollView {
                    VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                        if !item.objective.isEmpty {
                            Text(item.objective).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                        }
                        decisions(item)
                        // Attached to a view that always exists, so it runs with no decisions yet.
                        WorkItemFields(store: store, item: item)
                            .task(id: item.revision) { await loadAnswered(item) }
                        WorkItemNotes(store: store, item: item)
                        CodingSessions(store: store, item: item)
                        evidence(item)
                        SectionHeader("Conversation").padding(.top, 6)
                        ConversationMessages(store: store, key: key)
                    }
                    .padding(14)
                }
                ConversationComposer(store: store, key: key).padding(10)
            } else {
                header(nil)
                Spacer()
                if case .loading = store.work { ProgressView() } else { EmptyNote(text: "This work no longer exists.").padding(14) }
                Spacer()
            }
        }
    }

    private func header(_ item: Commitment?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item?.title ?? "Work").font(DevysTypography.heading).foregroundStyle(DevysColors.ink).lineLimit(3)
                HStack(spacing: 6) {
                    item?.state.chip
                    if let takeover = item.flatMap(store.state.takeoverTitle) {
                        Text(takeover).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    }
                }
            }
            Spacer(minLength: 4)
            if closable {
                ToolbarIconButton("Close", symbol: "xmark") { store.send(.workClosed) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder private func decisions(_ item: Commitment) -> some View {
        let decisions = store.state.decisions(for: item)
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Waiting on you", count: decisions.count)
                ForEach(decisions) { DecisionCard(store: store, decision: $0) }
            }
        }
        if !answered.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Decided", count: answered.count)
                ForEach(answered) { decision in
                    Text("\(decision.status == "rejected" ? "Declined" : "Approved"): \(DecisionText.title(decision))\(decision.status == "used" ? " · used" : "")")
                        .font(DevysTypography.caption).foregroundStyle(DevysColors.ink2)
                }
            }
        }
    }

    /// Reloads the answered requests when the item changes (its revision moves on each answer).
    private func loadAnswered(_ item: Commitment) async {
        answered = ((try? await runtime.workDecisions(store.businessID, item.id)) ?? []).filter { $0.status != "pending" }
    }

    @ViewBuilder private func evidence(_ item: Commitment) -> some View {
        if !item.evidence.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Evidence", count: item.evidence.count)
                ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.note).font(DevysTypography.body).foregroundStyle(DevysColors.ink).textSelection(.enabled)
                        Text("\(entry.author) · \(entry.recordedAt.prefix(10))").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                    }
                    .devysCard()
                }
            }
        }
    }
}

/// Owner, state, due date and takeover, each changed at the revision on screen.
private struct WorkItemFields: View {
    let store: StoreOf<Workspace>
    let item: Commitment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Owner") {
                Menu {
                    ForEach(store.snapshot.employees.filter { $0.id != item.ownerEmployeeID }) { employee in
                        Button("Reassign to \(employee.name)") { store.send(.reassigned(item.id, to: employee.id)) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if let owner = store.snapshot.employees.first(where: { $0.id == item.ownerEmployeeID }) {
                            Portrait(store.state.portrait(for: owner), size: 20, isAnimated: false)
                        }
                        Text(store.state.employeeName(item.ownerEmployeeID))
                        Image(systemName: "chevron.up.chevron.down").imageScale(.small).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
                    }
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                .disabled(!item.state.isOpen)
            }
            row("State") {
                Menu {
                    ForEach(CommitmentState.allCases.filter { $0 != item.state }, id: \.self) { state in
                        Button(state.title) { store.send(.commitmentChanged(item.id, CommitmentChange(expectedRevision: item.revision, state: state))) }
                    }
                } label: {
                    item.state.chip
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
            }
            row("Due") { due }
            row("Handled by") {
                Text(handler).foregroundStyle(DevysColors.ink)
                Spacer(minLength: 8)
                if item.state.isOpen {
                    TakeoverButton(store: store, item: item)
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                        .fixedSize()
                }
            }
        }
        .font(DevysTypography.body)
        .devysCard()
    }

    private var handler: String {
        if item.takenOverBy == nil { return store.state.employeeName(item.ownerEmployeeID) }
        return store.state.isMine(item) ? "You" : "Another person"
    }

    @ViewBuilder private var due: some View {
        let date = item.dueAt.flatMap(ServerDate.parse)
        if let date {
            DatePicker(
                "Due",
                selection: Binding(get: { date }, set: { change(dueAt: .set($0.formatted(.iso8601))) }),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 8)
            Button("Clear") { change(dueAt: .clear) }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
        } else {
            Text("None").foregroundStyle(DevysColors.ink3)
            Spacer(minLength: 8)
            Button("Add due date") { change(dueAt: .set(Date.now.addingTimeInterval(86_400).formatted(.iso8601))) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .disabled(!item.state.isOpen)
        }
    }

    private func change(dueAt: CommitmentChange.Value) {
        store.send(.commitmentChanged(item.id, CommitmentChange(expectedRevision: item.revision, dueAt: dueAt)))
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3).frame(width: 76, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// The next action and what the work waits on, edited in place.
private struct WorkItemNotes: View {
    let store: StoreOf<Workspace>
    let item: Commitment
    @State private var nextAction = ""
    @State private var waiting = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            note("Next action", text: $nextAction, prompt: "What happens next", saved: item.nextAction) {
                store.send(.commitmentChanged(item.id, CommitmentChange(expectedRevision: item.revision, nextAction: nextAction)))
            }
            note("Waiting on", text: $waiting, prompt: "Nothing", saved: item.waitCondition ?? "") {
                let text = waiting.trimmingCharacters(in: .whitespacesAndNewlines)
                store.send(.commitmentChanged(item.id, CommitmentChange(expectedRevision: item.revision, waitCondition: text.isEmpty ? .clear : .set(text))))
            }
        }
        .devysCard()
        .onAppear(perform: reset)
        .onChange(of: item.revision) { reset() }
    }

    private func reset() {
        nextAction = item.nextAction
        waiting = item.waitCondition ?? ""
    }

    private func note(_ label: String, text: Binding<String>, prompt: String, saved: String, save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            HStack(spacing: 8) {
                FieldBox { TextField(prompt, text: text, axis: .vertical).lineLimit(1...4).onSubmit(save) }
                if text.wrappedValue != saved {
                    Button("Save", action: save).buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
            }
        }
    }
}

extension CommitmentState {
    var title: String {
        switch self {
        case .proposed: "Proposed"
        case .ready: "Ready"
        case .inProgress: "In progress"
        case .waiting: "Waiting"
        case .needsDecision: "Needs a decision"
        case .completed: "Done"
        case .cancelled: "Cancelled"
        }
    }
}
