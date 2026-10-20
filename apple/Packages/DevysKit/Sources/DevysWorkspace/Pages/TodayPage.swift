import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The briefing: a greeting, Operations' live state, what needs you, who is
/// working, and what finished today.
struct TodayPage: View {
    let store: StoreOf<Workspace>

    var body: some View {
        PageBody {
            TodayGreeting(store: store)
            TodayWork(store: store)
        }
    }
}

/// What needs the owner, what's in motion and what finished today.
struct TodayWork: View {
    let store: StoreOf<Workspace>

    var body: some View {
        let decisions = store.decisions.value ?? []
        let blocked = store.state.work(.needsYou)
        if !decisions.isEmpty || !blocked.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                SectionHeader("Needs you", count: decisions.count + blocked.count)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: DevysSpacing.compact)], spacing: DevysSpacing.compact) {
                    ForEach(decisions) { DecisionCard(store: store, decision: $0) }
                }
                ForEach(blocked) { WorkRow(store: store, item: $0) }
            }
        }
        let moving = (store.work.value ?? []).filter { [.inProgress, .ready, .waiting].contains($0.state) }
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            SectionHeader("In motion", count: moving.count)
            if moving.isEmpty { EmptyNote(text: "Nothing is in motion. Add work, or ask Operations.") }
            ForEach(moving.prefix(8)) { WorkRow(store: store, item: $0) }
        }
        let done = (store.work.value ?? []).filter { $0.state == .completed && Self.isToday($0.updatedAt) }
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Done today", count: done.count)
                ForEach(done) { WorkRow(store: store, item: $0) }
            }
        }
    }

    static func isToday(_ timestamp: String) -> Bool {
        ServerDate.parse(timestamp).map(Calendar.current.isDateInToday) ?? false
    }
}

/// "Good morning, Mitch." and what Operations is doing.
struct TodayGreeting: View {
    let store: StoreOf<Workspace>

    var body: some View { greeting }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            Text(salutation)
                .font(DevysTypography.greeting)
                .foregroundStyle(DevysColors.ink)
            HStack(spacing: 10) {
                if let ops = store.operations {
                    Portrait(store.state.portrait(for: ops), size: 28, mood: store.operationsMood, label: ops.name)
                }
                Text(operationsLine)
                    .font(DevysTypography.body)
                    .foregroundStyle(DevysColors.ink2)
                if store.isRunning {
                    Button("Stop", systemImage: "stop.fill") { store.send(.stopTapped) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        .disabled(store.isStopping)
                        .help("Stop the current work (⌘.)")
                }
                LiveTag()
            }
        }
        .padding(.top, DevysSpacing.small)
    }

    private var salutation: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return store.ownerFirstName.map { "\(part), \($0)." } ?? "\(part)."
    }

    private var operationsLine: String {
        switch store.status {
        case .loading: "Checking in with Operations…"
        case .failed(let message): message
        case .loaded(let snapshot):
            if store.isRunning, let running = snapshot.state.inbox.first(where: { $0.id == snapshot.state.run?.id }) {
                "Operations is working on “\(running.text ?? "your message")”."
            } else if store.isRunning {
                "Operations is working."
            } else {
                "Operations is available."
            }
        }
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
            VStack(alignment: .leading, spacing: 4) {
                ForEach(decision.input.fields, id: \.key) { field in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(field.key).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).frame(minWidth: 64, alignment: .leading)
                        Text(field.value).font(DevysTypography.body).foregroundStyle(DevysColors.ink).lineLimit(6).textSelection(.enabled)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: DevysSpacing.small) {
                Button("Approve once", systemImage: "checkmark") { store.send(.decisionAnswered(decision.id, approve: true)) }
                    .buttonStyle(.aurora)
                    .help("Allows this exact request once. Face ID signing arrives with signed decisions.")
                Button("Reject") { store.send(.decisionAnswered(decision.id, approve: false)) }
                    .buttonStyle(.raised)
            }
            .padding(.top, 2)
        }
        .devysCard()
    }
}

struct ApprovalsPage: View {
    let store: StoreOf<Workspace>

    var body: some View {
        let decisions = store.decisions.value ?? []
        PageBody {
            PageHeader(title: "Approvals")
            if case .loading = store.decisions {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if decisions.isEmpty {
                EmptyNote(text: "Nothing needs your approval. Requests appear here when an employee's access asks first.")
            } else {
                VStack(alignment: .leading, spacing: DevysSpacing.compact) {
                    SectionHeader("Waiting on you", count: decisions.count)
                    ForEach(decisions) { DecisionCard(store: store, decision: $0) }
                }
            }
        }
    }
}
