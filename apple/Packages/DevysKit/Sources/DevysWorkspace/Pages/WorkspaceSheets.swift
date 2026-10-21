import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The workspace's sheets, shared by the Mac/iPad shell and the iPhone shell.
struct WorkspaceSheets: ViewModifier {
    let store: StoreOf<Workspace>

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { store.team.hiring != nil }, set: { if !$0 { store.send(.hireCancelled) } })) {
                HireSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.newTask != nil }, set: { if !$0 { store.send(.taskCancelled) } })) {
                NewTaskSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.newProject != nil }, set: { if !$0 { store.send(.newProjectDismissed) } })) {
                NewProjectSheet(store: store)
            }
    }
}

/// Hire: choose a role, then name, responsibilities and model; the role brings its access.
struct HireSheet: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let draft = store.team.hiring {
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                HStack {
                    if draft.template != nil {
                        Button("Roles", systemImage: "chevron.left") { edit { $0.template = nil } }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                    }
                    Text(draft.template == nil ? "Hire" : "Hire \(RoleTemplate.displayName(draft.template ?? ""))")
                        .font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                    Spacer()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                        if let template = draft.template {
                            details(draft, template: template)
                        } else {
                            roles
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = draft.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                HStack {
                    Spacer()
                    Button("Cancel") { store.send(.hireCancelled) }.buttonStyle(.quiet)
                    if draft.template != nil {
                        Button(draft.isSubmitting ? "Hiring…" : "Hire") { store.send(.hireConfirmed) }
                            .buttonStyle(.aurora)
                            .disabled(!draft.canHire)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(DevysSpacing.roomy)
            .sheetFrame(width: 460, height: 520)
            .background(DevysColors.sheet)
        }
    }

    @ViewBuilder private var roles: some View {
        switch store.team.roles {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .failed(let message):
            EmptyNote(text: message)
        case .loaded(let roles):
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: DevysSpacing.compact)], spacing: DevysSpacing.compact) {
                ForEach(roles) { role in
                    Button { store.send(.templateChosen(role.id)) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(role.name).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                            Text(role.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).multilineTextAlignment(.leading)
                            Text(role.capabilities.isEmpty ? "No access to start" : "\(role.capabilities.count) kinds of access")
                                .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .devysCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(role.summary)
                }
            }
        }
    }

    @ViewBuilder private func details(_ draft: HireDraft, template: String) -> some View {
        let role = store.team.roles.value?.first { $0.id == template }
        label("Name")
        FieldBox { TextField("Name", text: binding(\.name)) }
        label("Responsibilities")
        FieldBox { TextField("What they're accountable for", text: binding(\.responsibilities), axis: .vertical).lineLimit(4...10) }
        label("Model")
        HStack {
            let model = store.models.catalog?.model(draft.model)
            VStack(alignment: .leading, spacing: 2) {
                Text(model?.label ?? "Server default").font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                if let model {
                    Text("\(model.provider) · \(ModelText.perTurn(model))").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
                }
            }
            Spacer()
            if let catalog = store.models.catalog {
                ModelChooser(catalog: catalog, selection: draft.model, label: "Choose the new employee's model") { id in edit { $0.model = id } }
            }
        }
        .devysCard()
        label("Access")
        VStack(alignment: .leading, spacing: 4) {
            let capabilities = role?.capabilities ?? []
            if capabilities.isEmpty {
                Text("Starts with no access. Grant some on its desk after hiring.").font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
            } else {
                Text(capabilities.map(AccessNames.title).joined(separator: " · "))
                    .font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                Text("From the role. Change it on its desk after hiring.").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
    }

    private func binding(_ keyPath: WritableKeyPath<HireDraft, String>) -> Binding<String> {
        Binding(get: { store.team.hiring?[keyPath: keyPath] ?? "" }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func edit(_ change: (inout HireDraft) -> Void) {
        guard var draft = store.team.hiring else { return }
        change(&draft)
        store.send(.hireEdited(draft))
    }
}

/// New task: a title, its owner, what it's for, when it's due, and optionally a project.
struct NewTaskSheet: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let draft = store.newTask {
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                Text("New task").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                FieldBox { TextField("Title", text: binding(\.title)) }
                EmployeePicker(title: "Owner", employees: store.snapshot.employees, selection: binding(\.ownerID))
                FieldBox { TextField("Objective (optional)", text: binding(\.objective), axis: .vertical).lineLimit(3...8) }
                HStack {
                    Toggle("Due", isOn: Binding(get: { draft.hasDue }, set: { value in edit { $0.hasDue = value } }))
                        .toggleStyle(.switch)
                        .font(DevysTypography.control)
                        .fixedSize()
                    Spacer()
                    if draft.hasDue {
                        DatePicker("Due", selection: Binding(get: { draft.due }, set: { value in edit { $0.due = value } }))
                            .labelsHidden()
                            .fixedSize()
                    }
                }
                HStack(spacing: 8) {
                    Text("Project").font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
                    Spacer(minLength: 8)
                    Picker("Project", selection: Binding(get: { draft.projectID ?? "" }, set: { value in edit { $0.projectID = value.isEmpty ? nil : value } })) {
                        Text("None").tag("")
                        ForEach(store.projects.value ?? []) { project in Text(project.name).tag(project.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if let error = draft.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel") { store.send(.taskCancelled) }.buttonStyle(.quiet)
                    Button(draft.isSubmitting ? "Creating…" : "Create") { store.send(.taskConfirmed) }
                        .buttonStyle(.aurora)
                        .disabled(!draft.canCreate)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DevysSpacing.roomy)
            .sheetFrame(width: 420, height: 380)
            .background(DevysColors.sheet)
            .presentationDetents([.medium, .large])
        }
    }

    private func binding(_ keyPath: WritableKeyPath<TaskDraft, String>) -> Binding<String> {
        Binding(get: { store.newTask?[keyPath: keyPath] ?? "" }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func edit(_ change: (inout TaskDraft) -> Void) {
        guard var draft = store.newTask else { return }
        change(&draft)
        store.send(.taskEdited(draft))
    }
}

extension View {
    /// Mac sheets size to their content's minimum; iPhone and iPad sheets fill their detent.
    func sheetFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
            frame(minWidth: width, minHeight: height)
        #else
            self
        #endif
    }
}

/// A labelled menu of the team, each with its portrait.
struct EmployeePicker: View {
    let title: String
    let employees: [Employee]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(employees) { employee in
                    Text(employee.name).tag(employee.id)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// A rounded well around a text field, as the design system draws inputs.
struct FieldBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .textFieldStyle(.plain)
            .font(DevysTypography.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
