import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// External correspondence. Nothing is shown until a mailbox is really connected.
struct InboxPage: View {
    var body: some View {
        PageBody {
            PageHeader(title: "Inbox")
            EmptyNote(text: "No mailbox is connected yet. The business's mail appears here once one is.")
        }
    }
}

struct WorkPage: View {
    let store: StoreOf<Workspace>
    let filter: WorkFilter
    @State private var codingSession = false

    var body: some View {
        let items = store.state.work(filter)
        PageBody {
            PageHeader(title: filter == .all ? "Work" : filter.rawValue) {
                HStack(spacing: 8) {
                    SegmentedTabs(
                        selection: Binding(get: { store.workLayout }, set: { store.send(.workLayoutSelected($0)) }),
                        options: WorkLayout.allCases.map { (value: $0, title: $0.rawValue) }
                    )
                    Button("New task", systemImage: "plus") { store.send(.newTaskTapped()) }
                        .buttonStyle(DevysButtonStyle(.raised, compact: true))
                        .fixedSize()
                    Button("New coding session", systemImage: "chevron.left.forwardslash.chevron.right") { codingSession = true }
                        .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                        .fixedSize()
                }
            }
            .sheet(isPresented: $codingSession) { NewCodingSessionSheet(store: store, isPresented: $codingSession) }
            TerminalsSection(businessID: store.businessID)
            if case .loading = store.work {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if items.isEmpty {
                EmptyNote(text: filter == .all ? "Nothing is owed yet. Create a task, or ask Operations to take something on." : "Nothing here.")
            } else if store.workLayout == .list {
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    SectionHeader("Commitments", count: items.count)
                    ForEach(items) { WorkRow(store: store, item: $0) }
                }
            } else {
                board(items)
            }
        }
    }

    private func board(_ items: [Commitment]) -> some View {
        let columns = WorkFilter.allCases.filter { column in column != .all && items.contains { $0.state.filter == column } }
        // Columns share the page width; at most four states exist.
        return HStack(alignment: .top, spacing: DevysSpacing.compact) {
            ForEach(columns, id: \.self) { column in
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    SectionHeader(column.rawValue, count: items.filter { $0.state.filter == column }.count)
                    ForEach(items.filter { $0.state.filter == column }) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                            if !item.nextAction.isEmpty {
                                Text(item.nextAction).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                            }
                            Text(store.state.employeeName(item.ownerEmployeeID)).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .devysCard(padding: DevysSpacing.compact)
                        .contentShape(Rectangle())
                        .onTapGesture { store.send(.workOpened(item.id)) }
                        .contextMenu { WorkActions(store: store, item: item) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { store.send(.workOpened(item.id)) }
                    }
                }
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

/// What each employee's model use has actually cost. Budgets and spending limits arrive with P1.
struct MoneyPage: View {
    let store: StoreOf<Workspace>

    var body: some View {
        let employees = store.snapshot.employees
        let total = employees.reduce(0) { $0 + (store.state.usage(of: $1.id)?.totalCost ?? 0) }
        PageBody {
            PageHeader(title: "Money", subtitle: "Model spend so far: \(ModelText.dollars(total))")
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Spend by employee", count: employees.count)
                if employees.isEmpty { EmptyNote(text: "No employees yet.") }
                ForEach(employees) { employee in
                    HStack(spacing: DevysSpacing.compact) {
                        Portrait(store.state.portrait(for: employee), size: 26, isAnimated: false)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(employee.name).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                            Text(store.models.catalog?.model(employee.model)?.label ?? employee.model)
                                .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        }
                        Spacer()
                        Text(store.state.usage(of: employee.id).map { ModelText.dollars($0.totalCost) } ?? "Nothing yet")
                            .font(DevysTypography.body).monospacedDigit().foregroundStyle(DevysColors.ink2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { store.send(.pageSelected(.employee(employee.id))) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { store.send(.pageSelected(.employee(employee.id))) }
                }
            }
            EmptyNote(text: "Budgets and spending limits aren't available yet, so nothing can be purchased.")
        }
        .onAppear { store.send(.allUsageRequested) }
    }
}

/// Installed business functions and account connections: only what is real.
struct AppsPage: View {
    let store: StoreOf<Workspace>
    let section: AppsSection

    var body: some View {
        PageBody {
            PageHeader(title: section.rawValue) {
                // The sidebar lists both sections on wide layouts; iPhone has only this.
                SegmentedTabs(
                    selection: Binding(get: { section }, set: { store.send(.pageSelected(.apps($0))) }),
                    options: AppsSection.allCases.map { (value: $0, title: $0.rawValue) }
                )
            }
            switch section {
            case .installed:
                EmptyNote(text: "Installed apps arrive with T1, the tool registry.")
            case .connections:
                VStack(alignment: .leading, spacing: DevysSpacing.small) {
                    SectionHeader("Accounts")
                    HStack(spacing: DevysSpacing.compact) {
                        Image(systemName: "externaldrive.connected.to.line.below").frame(width: 28).foregroundStyle(DevysColors.ink2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Google Drive").font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                            Text("Files your employees read and write").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                        }
                        Spacer()
                        googleState
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    EmptyNote(text: "Other connections arrive with T1, the tool registry.")
                }
                .onAppear { store.send(.connectionsRequested) }
            }
        }
    }

    @ViewBuilder private var googleState: some View {
        switch store.google {
        case nil, .loading: ProgressView().controlSize(.small)
        case .failed(let message): Text(message).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        case .loaded(let google) where google.connected: StatusChip("Connected", tone: .done)
        case .loaded(let google) where google.configured:
            // Google's consent flow runs in the browser; this app doesn't start it.
            Text("Not connected · connect it in Devys on the web, under Connections")
                .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).multilineTextAlignment(.trailing)
        case .loaded: Text("Not set up on this server").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        }
    }
}
