import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One employee: who they are and what they're responsible for, their model, memory and access.
struct EmployeePage: View {
    let store: StoreOf<Workspace>
    let employeeID: String?
    @State private var editing = false
    @State private var retiring = false

    var body: some View {
        if let employee = store.snapshot.employees.first(where: { $0.id == employeeID }) ?? store.snapshot.employees.first {
            PageBody {
                HStack(spacing: DevysSpacing.regular) {
                    Portrait(store.state.portrait(for: employee), size: 56, mood: mood(employee), label: employee.name)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(employee.name).font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                        Text(RoleTemplate.displayName(employee.template)).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                    }
                    Spacer(minLength: 8)
                    actions(employee)
                }
                if editing {
                    ProfileEditor(employee: employee) { name, responsibilities in
                        store.send(.profileSaved(employee.id, name: name, responsibilities: responsibilities))
                        editing = false
                    } cancel: {
                        editing = false
                    }
                }
                ModelSection(store: store, employee: employee)
                SegmentedTabs(
                    selection: Binding(get: { store.employeeTab }, set: { store.send(.employeeTabSelected($0)) }),
                    options: EmployeeTab.allCases.map { (value: $0, title: $0.rawValue) }
                )
                if employee.paused { PausedBanner(store: store, employee: employee) }
                Group {
                    switch store.employeeTab {
                    case .activity: activity(employee)
                    case .responsibilities: responsibilities(employee)
                    case .memory: memory(isOperations: employee.id == store.operations?.id)
                    case .access: AccessPane(store: store, employee: employee)
                    }
                }
                .transaction { $0.animation = nil }
            }
            .sheet(isPresented: $retiring) {
                RetireSheet(store: store, employee: employee) { retiring = false }
            }
            .onChange(of: employee.id) { editing = false }
        } else {
            PageBody { EmptyNote(text: "No employees yet.") }
        }
    }

    @ViewBuilder private func actions(_ employee: Employee) -> some View {
        HStack(spacing: 6) {
            Button("Message", systemImage: "bubble.left") { store.send(.pageSelected(.direct(employee.id))) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .fixedSize()
            Button("New task", systemImage: "plus") { store.send(.newTaskTapped(owner: employee.id)) }
                .buttonStyle(DevysButtonStyle(.raised, compact: true))
                .fixedSize()
            Menu {
                Button("Edit name and responsibilities", systemImage: "pencil") { editing = true }
                Button("Hire someone", systemImage: "person.badge.plus") { store.send(.hireTapped) }
                if !employee.isOperations {
                    Divider()
                    Button("Retire…", systemImage: "person.badge.minus", role: .destructive) { retiring = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .foregroundStyle(DevysColors.ink2)
            .fixedSize()
            .accessibilityLabel("More for \(employee.name)")
        }
    }

    private func mood(_ employee: Employee) -> BotMood {
        store.state.mood(for: employee)
    }

    /// Its open work, what it's waiting on you for, and the work it finished most recently.
    @ViewBuilder private func activity(_ employee: Employee) -> some View {
        let all = (store.work.value ?? []).filter { $0.ownerEmployeeID == employee.id }
        let owned = all.filter(\.state.isOpen)
        let finished = all.filter { $0.state == .completed }.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)
        let decisions = store.decisions.value?.filter { $0.employeeID == employee.id } ?? []
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            SectionHeader("Open work", count: owned.count)
            if owned.isEmpty { EmptyNote(text: "Nothing open. Give \(employee.name) a task.") }
            ForEach(owned) { WorkRow(store: store, item: $0) }
        }
        if !decisions.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Waiting on you", count: decisions.count)
                ForEach(decisions) { DecisionCard(store: store, decision: $0) }
            }
        }
        if !finished.isEmpty {
            VStack(alignment: .leading, spacing: DevysSpacing.small) {
                SectionHeader("Recently finished")
                ForEach(finished) { WorkRow(store: store, item: $0) }
            }
        }
    }

    @ViewBuilder private func responsibilities(_ employee: Employee) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.small) {
            HStack {
                SectionHeader("Accountable for")
                Spacer()
                Button("Edit") { editing = true }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
            }
            Text(employee.role).font(DevysTypography.body).foregroundStyle(DevysColors.ink).textSelection(.enabled)
        }
    }

    @ViewBuilder private func memory(isOperations: Bool) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            HStack(spacing: 8) {
                Text("What I remember").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                if isOperations { LiveTag() }
            }
            if !isOperations {
                EmptyNote(text: "No memory yet")
            } else {
                switch store.memory {
                case .loading: ProgressView()
                case .failed(let message): EmptyNote(text: message)
                case .loaded(let claims):
                    if claims.isEmpty { EmptyNote(text: "Nothing remembered yet.") }
                    ForEach(claims) { claim in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(claim.content).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
                            Text(claim.sourceKind == "user" ? "From you" : "Inferred from conversation")
                                .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        }
                        .devysCard()
                    }
                }
            }
        }
    }
}

/// Edits an employee's name and responsibilities in place.
private struct ProfileEditor: View {
    let employee: Employee
    let save: (String, String) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var responsibilities = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Name").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            FieldBox { TextField("Name", text: $name) }
            Text("Responsibilities").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            FieldBox { TextField("What they're accountable for", text: $responsibilities, axis: .vertical).lineLimit(3...10) }
            HStack {
                Text("\(responsibilities.count)/2000").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(DevysButtonStyle(.quiet, compact: true))
                Button("Save") { save(name, responsibilities) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .devysCard()
        .onAppear {
            name = employee.name
            responsibilities = employee.role
        }
    }

    private var isValid: Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = responsibilities.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name.count <= 80 && !text.isEmpty && text.count <= 2000
    }
}

/// Retiring hands the employee's open work to a successor; their history stays readable.
private struct RetireSheet: View {
    let store: StoreOf<Workspace>
    let employee: Employee
    let dismiss: () -> Void
    @State private var successor = ""

    var body: some View {
        let others = store.snapshot.employees.filter { $0.id != employee.id }
        let open = (store.work.value ?? []).filter { $0.ownerEmployeeID == employee.id && $0.state.isOpen }.count
        VStack(alignment: .leading, spacing: DevysSpacing.regular) {
            Text("Retire \(employee.name)?").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
            Text(
                open == 0
                    ? "\(employee.name) owns no open work. Their conversations stay readable."
                    : "\(employee.name)'s \(open) open item\(open == 1 ? "" : "s") move to the employee you choose. Their conversations stay readable."
            )
            .font(DevysTypography.body)
            .foregroundStyle(DevysColors.ink2)
            .fixedSize(horizontal: false, vertical: true)
            EmployeePicker(title: "Open work goes to", employees: others, selection: $successor)
            HStack {
                Spacer()
                Button("Cancel", action: dismiss).buttonStyle(.quiet)
                Button("Retire", role: .destructive) {
                    store.send(.retireConfirmed(employee.id, successor: successor))
                    dismiss()
                }
                .buttonStyle(.raised)
                .disabled(successor.isEmpty)
            }
        }
        .padding(DevysSpacing.roomy)
        .sheetFrame(width: 360, height: 240)
        .presentationDetents([.medium])
        .onAppear { successor = store.operations?.id ?? others.first?.id ?? "" }
    }
}
