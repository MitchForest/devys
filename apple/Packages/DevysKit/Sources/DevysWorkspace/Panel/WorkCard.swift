import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A thread's permanent view: the work item itself. Who owns it, where it stands, what's next,
/// what it waits on, when it's due, the decision waiting on the owner, its coding sessions, the
/// live browser and its evidence. The thread itself is the conversation in the middle. Read-only
/// until the owner takes it over; then they change it by hand until they hand it back.
struct WorkCard: View {
    let store: StoreOf<Workspace>
    let workItemID: String
    let close: () -> Void
    @Dependency(\.runtimeClient) private var runtime
    /// This item's requests the owner already answered.
    @State private var answered: [Decision] = []
    @State private var showsEvidence = false

    var body: some View {
        VStack(spacing: 0) {
            if let item = store.work.value?.first(where: { $0.id == workItemID }) {
                header(item)
                ScrollView {
                    VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                        HStack(spacing: DevysSpacing.small) {
                            item.state.chip(size: .small)
                            if let takeover = store.state.takeoverTitle(item) {
                                Text(takeover).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                            }
                        }
                        if !item.objective.isEmpty {
                            Text(item.objective).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                        }
                        // Attached to a view that always exists, so it runs with no decisions yet.
                        WorkSummary(store: store, item: item)
                            .task(id: item.revision) { await loadAnswered(item) }
                        progress(item)
                        WorkItemActions(store: store, item: item)
                        decisions(item)
                        CodingSessions(store: store, item: item)
                        BrowserLine(store: store, item: item)
                        evidence(item)
                    }
                    .padding(14)
                }
            } else {
                header(nil)
                Spacer()
                if case .loading = store.work { ProgressView() } else { EmptyNote(text: "This work item no longer exists.").padding(14) }
                Spacer()
            }
        }
    }

    private func header(_ item: WorkItem?) -> some View {
        PanelHeader(title: item?.title ?? "Work", close: close) {
            if let item {
                let following = store.state.isFollowing(item.id)
                ToolbarIconButton(
                    following ? "Following: told at each step. Stop following" : "Follow each step",
                    symbol: following ? "bell.fill" : "bell"
                ) { store.send(.followToggled(item.id)) }
            }
        }
    }

    /// What it achieved, then the steps it shows while it takes time.
    @ViewBuilder private func progress(_ item: WorkItem) -> some View {
        if !item.results.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Results")
                WorkResultsView(results: item.results)
            }
        }
        if let progress = WorkStep.progress(item.steps) {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Steps · \(progress)")
                WorkStepsView(steps: item.steps)
            }
        }
    }

    @ViewBuilder private func decisions(_ item: WorkItem) -> some View {
        let decisions = store.state.decisions(for: item)
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Waiting on you", count: decisions.count)
                ForEach(decisions) { DecisionCard(store: store, decision: $0) }
            }
        }
        if !answered.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Decided")
                ForEach(answered) { decision in
                    Text("\(decision.status == "rejected" ? "Declined" : "Approved"): \(DecisionText.title(decision))\(decision.status == "used" ? " · used" : "")")
                        .font(DevysTypography.caption).foregroundStyle(DevysColors.ink2)
                }
            }
        }
    }

    /// Reloads the answered requests when the item changes (its revision moves on each answer).
    private func loadAnswered(_ item: WorkItem) async {
        answered = ((try? await runtime.workDecisions(store.businessID, item.id)) ?? []).filter { $0.status != "pending" }
    }

    /// For coding work one line (check, changes, pull request, commit) that opens the record;
    /// otherwise the evidence notes themselves.
    @ViewBuilder private func evidence(_ item: WorkItem) -> some View {
        if let outcome = CodingOutcome(item.evidence) {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                HStack(spacing: 8) {
                    if let passed = outcome.checkPassed {
                        StatusChip(passed ? "Check passed" : "Check failed", tone: passed ? .done : .failed)
                    }
                    if let changes = outcome.changes {
                        Text(changes).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
                    }
                    if let url = outcome.pullRequest, let label = outcome.pullRequestLabel {
                        Link(label, destination: url).font(DevysTypography.secondary.weight(.medium))
                    }
                    ForEach(outcome.deploys, id: \.stage) { deploy in
                        if deploy.live, let url = deploy.url.flatMap(URL.init(string:)) {
                            Link(deploy.stage == "production" ? "Live ↗" : "Preview ↗", destination: url)
                                .font(DevysTypography.secondary.weight(.medium))
                        } else {
                            Text("\(deploy.stage == "production" ? "Production" : "Preview") deploy failed")
                                .font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                        }
                    }
                    Text(outcome.commit).font(DevysTypography.caption.monospaced()).foregroundStyle(DevysColors.ink3)
                    Spacer(minLength: 4)
                    Button(showsEvidence ? "Hide" : "Details") { showsEvidence.toggle() }
                        .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: 10))
                if showsEvidence { notes(item) }
            }
        } else if !item.evidence.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Evidence", count: item.evidence.count)
                notes(item)
            }
        }
    }

    private func notes(_ item: WorkItem) -> some View {
        ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.note).font(DevysTypography.body).foregroundStyle(DevysColors.ink).textSelection(.enabled)
                Text("\(entry.author) · \(entry.recordedAt.prefix(10))").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            .devysCard()
        }
    }
}

/// Who owns the work and its plan: what's next, what it waits on and when it's due. Read-only;
/// once the owner has taken the work over, Reassign and Edit change it by hand.
private struct WorkSummary: View {
    let store: StoreOf<Workspace>
    let item: WorkItem

    private var editable: Bool { store.state.isHandEditable(item) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let owner = store.snapshot.employees.first(where: { $0.id == item.ownerEmployeeID }) {
                    Portrait(store.state.portrait(for: owner), size: 26, isAnimated: false)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Owner").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    Text(store.state.employeeName(item.ownerEmployeeID))
                        .font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink).lineLimit(1)
                }
                Spacer(minLength: 8)
                if editable { reassign }
            }
            if editable, let draft = store.workPlan, draft.workItemID == item.id {
                WorkPlanForm(store: store, draft: draft)
            } else {
                plan
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
    }

    private var reassign: some View {
        Menu {
            ForEach(store.snapshot.employees.filter { $0.id != item.ownerEmployeeID }) { employee in
                Button(employee.name) { store.send(.reassigned(item.id, to: employee.id)) }
            }
        } label: {
            Label("Reassign", systemImage: "chevron.down").labelStyle(TrailingIcon())
        }
        .menuIndicator(.hidden)
        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
        .fixedSize()
    }

    private var plan: some View {
        HStack(alignment: .top, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                line("Next", item.nextAction.isEmpty ? "Not set" : item.nextAction)
                if let waiting = item.waitCondition, !waiting.isEmpty { line("Waiting on", waiting) }
                if item.state == .waiting, let wake = item.wakeAt.flatMap(ServerDate.parse) { line("Waiting until", RoutineText.upcoming(wake)) }
                line("Due", item.dueAt.flatMap(ServerDate.parse).map(dueDate) ?? "No due date")
            }
            Spacer(minLength: 0)
            if editable {
                Button("Edit", systemImage: "pencil") { store.send(.planEditTapped(item.id)) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    .fixedSize()
                    .accessibilityLabel("Edit next, waiting on and due")
            }
        }
    }

    private func line(_ label: String, _ text: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(DevysColors.ink3)
            Text(text).foregroundStyle(DevysColors.ink).textSelection(.enabled)
        }
        .font(DevysTypography.secondary)
    }

    /// "Wed, Oct 21", as the web shows a due date.
    private func dueDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

/// A label with its icon after the title, as a menu button reads ("Reassign ⌄").
private struct TrailingIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// What's next, what it waits on and the day it's due, saved as one change at the revision on
/// screen. If someone changed the item meanwhile, the latest loads and the draft stays to save again.
private struct WorkPlanForm: View {
    let store: StoreOf<Workspace>
    let draft: WorkPlanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Next") { TextField("Next", text: binding(\.nextAction), axis: .vertical).lineLimit(1...4) }
            field("Waiting on") { TextField("Nothing", text: binding(\.waiting), axis: .vertical).lineLimit(1...4) }
            VStack(alignment: .leading, spacing: 4) {
                Text("Due").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                HStack(spacing: 8) {
                    if draft.hasDue {
                        DatePicker("Due", selection: binding(\.due), displayedComponents: .date).labelsHidden().fixedSize()
                        Button("Clear") { edit { $0.hasDue = false } }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    } else {
                        Text("No due date").font(DevysTypography.body).foregroundStyle(DevysColors.ink3)
                        Button("Add due date") { edit { $0.hasDue = true } }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    }
                }
            }
            if let error = draft.error {
                Text(error).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
            }
            HStack(spacing: 6) {
                Button(draft.isSaving ? "Saving…" : "Save") { store.send(.planSaveTapped) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    .disabled(draft.isSaving)
                Button("Cancel") { store.send(.planEditCancelled) }
                    .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
            .fixedSize()
        }
        .onSubmit { store.send(.planSaveTapped) }
        .onKeyPress(.escape) {
            store.send(.planEditCancelled)
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Edit work plan")
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            FieldBox(content: content)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WorkPlanDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func edit(_ change: (inout WorkPlanDraft) -> Void) {
        guard var current = store.workPlan, current.workItemID == draft.workItemID else { return }
        change(&current)
        store.send(.planEdited(current))
    }
}

/// The owner's direct actions, as on the web: Take over while its employee has the work; once
/// they have it, Hand back, Mark done, Waiting and Cancel while it's open, Reopen once closed.
private struct WorkItemActions: View {
    let store: StoreOf<Workspace>
    let item: WorkItem

    var body: some View {
        let mine = store.state.isMine(item)
        let open = item.state.isOpen
        if mine || (open && item.takenOverBy == nil) {
            HStack(spacing: 6) {
                if open {
                    TakeoverButton(store: store, item: item)
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
                if mine && open {
                    Button("Mark done", systemImage: "checkmark.circle") { set(.completed) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    if item.state != .waiting {
                        Button("Waiting", systemImage: "clock") { set(.waiting) }
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    }
                    Button("Cancel", systemImage: "xmark.circle") { set(.cancelled) }
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
                if mine && !open {
                    Button("Reopen", systemImage: "arrow.uturn.backward") { set(.ready) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                }
            }
            .fixedSize()
        }
    }

    private func set(_ state: WorkItemState) {
        store.send(.workItemStateSet(item.id, state))
    }
}
