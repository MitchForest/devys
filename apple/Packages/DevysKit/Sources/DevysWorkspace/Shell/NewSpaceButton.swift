import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Creates a space: a name, what it's for, and the employee who leads its conversation.
struct NewSpaceButton: View {
    let store: StoreOf<Workspace>
    @State private var naming = false
    @State private var name = ""
    @State private var purpose = ""
    @State private var lead = ""

    var body: some View {
        Button("New space", systemImage: "plus") { naming = true }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(DevysColors.ink3)
            .help("New space")
            .popover(isPresented: $naming) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("New space").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                    FieldBox {
                        TextField("Name", text: $name).onSubmit(create)
                    }
                    FieldBox {
                        TextField("What it's for (optional)", text: $purpose, axis: .vertical).lineLimit(2...4)
                    }
                    EmployeePicker(title: "Lead", employees: store.snapshot.employees, selection: $lead)
                    HStack {
                        Spacer()
                        Button("Cancel") { naming = false }.buttonStyle(DevysButtonStyle(.quiet, compact: true))
                        Button("Create", action: create)
                            .buttonStyle(DevysButtonStyle(.raised, compact: true))
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(14)
                .frame(width: 300)
                .presentationCompactAdaptation(.popover)
                .onAppear { if lead.isEmpty { lead = store.operations?.id ?? "" } }
            }
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.send(.spaceCreateTapped(NewSpace(name: name, purpose: purpose, lead: lead.isEmpty ? nil : lead)))
        name = ""
        purpose = ""
        naming = false
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
