import ComposableArchitecture2
import DevysCharacter
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
            .sheet(isPresented: Binding(get: { store.newWorkItem != nil }, set: { if !$0 { store.send(.workItemCancelled) } })) {
                NewTaskSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.newProject != nil }, set: { if !$0 { store.send(.newProjectDismissed) } })) {
                NewProjectSheet(store: store)
            }
            .sheet(isPresented: Binding(get: { store.signing != nil }, set: { if !$0 { store.send(.signDismissed) } })) {
                SigningSheetView(store: store)
            }
            .sheet(isPresented: Binding(get: { store.secretEntry != nil }, set: { if !$0 { store.send(.secretDismissed) } })) {
                if let sheet = store.secretEntry {
                    // Opened from a request, its name and kind are fixed: nothing to edit.
                    SecretEntryView(sheet: sheet, edit: { _ in }, save: { store.send(.secretSubmitted($0)) }, cancel: { store.send(.secretDismissed) })
                }
            }
    }
}

/// New employee: the face large, a name, the Face's shapes and colors, and a role. The role
/// brings its responsibilities and access; a custom role asks for responsibilities.
struct HireSheet: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let draft = store.team.hiring {
            VStack(spacing: DevysSpacing.regular) {
                DevysAvatar(draft.look, size: 104, mood: draft.isSubmitting ? .thinking : .idle, label: draft.name)
                    .padding(.top, DevysSpacing.small)
                TextField("Name", text: binding(\.name), prompt: Text("Name").foregroundStyle(DevysColors.ink3))
                    .textFieldStyle(.plain)
                    .font(DevysTypography.heading)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(DevysColors.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: 260)
                shapes(draft)
                colors(draft)
                role(draft)
                if draft.template == "custom" {
                    FieldBox { TextField("What they're accountable for", text: binding(\.responsibilities), axis: .vertical).lineLimit(3...6) }
                }
                if let error = draft.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel") { store.send(.hireCancelled) }.buttonStyle(.quiet)
                    Button(draft.isSubmitting ? "Creating…" : "Create") { store.send(.hireConfirmed) }
                        .buttonStyle(.aurora)
                        .disabled(!draft.canHire)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(DevysSpacing.roomy)
            .sheetFrame(width: 420, height: 560)
            .background(DevysColors.sheet)
        }
    }

    private func shapes(_ draft: HireDraft) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 10)], spacing: 10) {
            ForEach(AvatarShape.allCases, id: \.self) { shape in
                let spec = AvatarSpec(palette: draft.look.palette, shape: shape, seed: draft.look.seed)
                Button { edit { $0.look = spec } } label: {
                    DevysAvatar(spec, size: 38, isAnimated: false)
                        .padding(3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(draft.look.shape == shape ? DevysColors.ink : .clear, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shape.rawValue)
                .accessibilityAddTraits(draft.look.shape == shape ? .isSelected : [])
            }
        }
        .frame(maxWidth: 330)
    }

    private func colors(_ draft: HireDraft) -> some View {
        HStack(spacing: 10) {
            ForEach(AvatarPalette.allCases, id: \.self) { palette in
                let rgb = palette.eyeInk
                let selected = draft.look.palette == palette
                Button { edit { $0.look = AvatarSpec(palette: palette, shape: $0.look.shape, seed: $0.look.seed) } } label: {
                    Circle()
                        .fill(Color(red: rgb.red, green: rgb.green, blue: rgb.blue))
                        .frame(width: 22, height: 22)
                        .overlay { Circle().strokeBorder(DevysColors.sheet, lineWidth: selected ? 2.5 : 0) }
                        .overlay { Circle().strokeBorder(DevysColors.ink, lineWidth: selected ? 1 : 0).padding(-2) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.rawValue.capitalized)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func role(_ draft: HireDraft) -> some View {
        switch store.team.roles {
        case .loading:
            ProgressView().controlSize(.small)
        case .failed(let message):
            Text(message).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
        case .loaded(let roles):
            let hireable = roles.filter { $0.id != "chief-of-staff" }
            let chosen = hireable.first { $0.id == draft.template }
            VStack(spacing: 4) {
                Menu {
                    ForEach(hireable) { role in
                        Button(role.name) { store.send(.templateChosen(role.id)) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(chosen?.name ?? "Choose a role").font(DevysTypography.control)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(chosen == nil ? DevysColors.ink2 : DevysColors.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(DevysColors.well, in: Capsule())
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .fixedSize()
                if let chosen, !chosen.summary.isEmpty {
                    Text(chosen.summary).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
            }
        }
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

/// New work item: a title, its owner, what it's for, when it's due, and optionally a project.
struct NewTaskSheet: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let draft = store.newWorkItem {
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                Text("New work item").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
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
                    Button("Cancel") { store.send(.workItemCancelled) }.buttonStyle(.quiet)
                    Button(draft.isSubmitting ? "Creating…" : "Create") { store.send(.workItemConfirmed) }
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

    private func binding(_ keyPath: WritableKeyPath<WorkItemDraft, String>) -> Binding<String> {
        Binding(get: { store.newWorkItem?[keyPath: keyPath] ?? "" }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func edit(_ change: (inout WorkItemDraft) -> Void) {
        guard var draft = store.newWorkItem else { return }
        change(&draft)
        store.send(.workItemEdited(draft))
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
