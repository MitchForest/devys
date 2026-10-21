import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A direct chat's permanent view: the employee's desk. What it is on now and what it just
/// finished stay open; who it is, its model, access and memory unfold on demand.
struct Desk: View {
    let store: StoreOf<Workspace>
    let employeeID: String
    let close: () -> Void
    @State private var retiring = false

    var body: some View {
        if let employee = store.state.employee(employeeID) {
            let owned = (store.work.value ?? []).filter { $0.ownerEmployeeID == employee.id }
            let open = owned.filter(\.state.isOpen)
            let done = owned.filter { $0.state == .completed }.sorted { $0.updatedAt > $1.updatedAt }.prefix(5)
            VStack(spacing: 0) {
                PanelHeader(title: { EditableName(store: store, employee: employee) }, close: close, trailing: { EmptyView() })
                PanelBody {
                    header(employee, open: open.count)
                    if employee.paused { PausedBanner(store: store, employee: employee) }
                    PanelSection(title: "Now", count: open.isEmpty ? nil : open.count) {
                        PanelAction(title: "Work item") { store.send(.newWorkItemTapped(owner: employee.id)) }
                    } content: {
                        if open.isEmpty {
                            Text("Nothing open.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                        }
                        ForEach(open) { WorkRow(store: store, item: $0, compact: true) }
                    }
                    if !done.isEmpty {
                        PanelSection(title: "Recently done") {
                            ForEach(done) { WorkRow(store: store, item: $0, compact: true) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(DevysColors.hairline).frame(height: 1)
                        Disclosure(title: "Responsibilities") { ResponsibilitiesEditor(store: store, employee: employee).id(employee.id) }
                        Disclosure(title: "Model") { ModelSection(store: store, employee: employee) }
                        Disclosure(title: "Access") { AccessPane(store: store, employee: employee) }
                        if employee.isOperations {
                            Disclosure(title: "Memory") { MemoryList(store: store) }
                        }
                    }
                    if !employee.isOperations {
                        Button("Retire…", systemImage: "person.badge.minus") { retiring = true }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                            .fixedSize()
                    }
                }
            }
            .sheet(isPresented: $retiring) {
                RetireSheet(store: store, employee: employee) { retiring = false }
            }
        } else {
            VStack(spacing: 0) {
                PanelHeader(title: "Desk", close: close)
                PanelBody { EmptyNote(text: "This employee no longer works here.") }
            }
        }
    }

    private func header(_ employee: Employee, open: Int) -> some View {
        HStack(spacing: 12) {
            Portrait(store.state.portrait(for: employee), size: 44, mood: store.state.mood(for: employee), label: employee.name)
            VStack(alignment: .leading, spacing: 2) {
                let template = RoleTemplate.displayName(employee.template)
                if template != employee.name {
                    Text(template).font(DevysTypography.control).foregroundStyle(DevysColors.ink)
                }
                Text(status(employee, open: open)).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            Spacer(minLength: 8)
            Button(employee.paused ? "Resume" : "Pause") { store.send(.pauseToggled(employee.id)) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .fixedSize()
        }
    }

    private func status(_ employee: Employee, open: Int) -> String {
        if employee.paused { return "Paused" }
        if store.state.isWorking(employee.id) { return "Working" }
        return open > 0 ? "\(open) open" : "Free"
    }
}

/// A section that unfolds on demand, so the desk shows only what is moving.
private struct Disclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $open) {
                content.padding(.top, 12)
            } label: {
                Text(title).font(DevysTypography.control).foregroundStyle(DevysColors.ink2)
            }
            .padding(.vertical, 10)
            Rectangle().fill(DevysColors.hairline).frame(height: 1)
        }
    }
}

/// The employee's name; the pencil renames them.
private struct EditableName: View {
    let store: StoreOf<Workspace>
    let employee: Employee
    @State private var editing = false
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        if editing {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(save)
                .onAppear { focused = true }
                .onChange(of: focused) { _, now in if !now { save() } }
                .onKeyPress(.escape) {
                    editing = false
                    return .handled
                }
        } else {
            HStack(spacing: 6) {
                Text(employee.name)
                Button("Rename \(employee.name)", systemImage: "pencil") {
                    name = employee.name
                    editing = true
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(DevysColors.ink3)
                .help("Rename")
            }
        }
    }

    private func save() {
        guard editing else { return }
        editing = false
        let next = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty, next != employee.name, next.count <= 80 else { return }
        store.send(.profileSaved(employee.id, name: next, responsibilities: employee.responsibilities))
    }
}

/// What the employee is accountable for; every turn starts from it.
private struct ResponsibilitiesEditor: View {
    let store: StoreOf<Workspace>
    let employee: Employee
    @State private var text = ""

    var body: some View {
        let changed = text.trimmingCharacters(in: .whitespacesAndNewlines) != employee.responsibilities.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 8) {
            Text("Accountable for").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            FieldBox { TextField("What they're accountable for", text: $text, axis: .vertical).lineLimit(4...12) }
            HStack(spacing: 8) {
                Text("\(text.count) of 2000 characters").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                Spacer(minLength: 4)
                if changed {
                    Button("Discard") { text = employee.responsibilities }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                }
                Button("Save responsibilities") {
                    store.send(.profileSaved(employee.id, name: employee.name, responsibilities: text.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                .buttonStyle(DevysButtonStyle(.raised, compact: true))
                .disabled(!changed || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
            }
        }
        .onAppear { text = employee.responsibilities }
    }
}

/// What Operations remembers about the business, with where each fact came from.
private struct MemoryList: View {
    let store: StoreOf<Workspace>

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            HStack(spacing: 8) {
                Text("What I remember").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                LiveTag()
            }
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

/// Retiring hands the employee's open work to a colleague; their history stays readable.
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
                    ? "\(employee.name) has no open work."
                    : "\(employee.name)'s \(open) open \(open == 1 ? "work item moves" : "work items move") to the colleague you choose."
            )
            .font(DevysTypography.body)
            .foregroundStyle(DevysColors.ink2)
            .fixedSize(horizontal: false, vertical: true)
            EmployeePicker(title: "Hand open work to", employees: others, selection: $successor)
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
