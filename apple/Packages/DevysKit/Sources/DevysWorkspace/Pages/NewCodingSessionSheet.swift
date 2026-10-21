import ComposableArchitecture2
import Dependencies
import DevysClient
import DevysDesignSystem
import SwiftUI

/// "New coding session": the owner drives a session from the start. It becomes a work item
/// already taken over, followed, and handed to the chosen employee when the owner hands back.
struct NewCodingSessionSheet: View {
    let store: StoreOf<Workspace>
    @Binding var isPresented: Bool
    @Dependency(\.codingClient) private var coding
    @State private var provider = "codex"
    @State private var newRepository = false
    @State private var repository = ""
    @State private var objective = ""
    @State private var employeeID = ""
    @State private var starting = false
    @State private var problem: String?

    private var canStart: Bool {
        !starting && !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repository.trimmingCharacters(in: .whitespaces).isEmpty && !employeeID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.regular) {
            Text("New coding session").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
            fields
            if let problem {
                Label(problem, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
            }
            Spacer(minLength: 0)
            actions
        }
        .padding(DevysSpacing.roomy)
        .sheetFrame(width: 460, height: 440)
        .background(DevysColors.sheet)
        .presentationDetents([.medium, .large])
        .onAppear(perform: chooseEmployee)
    }

    @ViewBuilder private var fields: some View {
        Picker("Coding agent", selection: $provider) {
            Text("Codex").tag("codex")
            Text("Claude Code").tag("claude")
        }
        .pickerStyle(.segmented)
        Picker("Repository", selection: $newRepository) {
            Text("Existing repository").tag(false)
            Text("New repository").tag(true)
        }
        .pickerStyle(.segmented)
        FieldBox { TextField(newRepository ? "my-app" : "/Users/you/Code/project", text: $repository) }
        FieldBox {
            TextField("What to build, and how to check it", text: $objective, axis: .vertical).lineLimit(3...8)
        }
        EmployeePicker(title: "Hand it to", employees: store.snapshot.employees, selection: $employeeID)
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("Cancel") { isPresented = false }.buttonStyle(.quiet)
            Button(starting ? "Starting…" : "Start session") { Task { await start() } }
                .buttonStyle(.aurora)
                .disabled(!canStart)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func chooseEmployee() {
        let employees = store.snapshot.employees
        employeeID = employees.first { $0.template == "engineering" }?.id ?? employees.first?.id ?? ""
    }

    private func start() async {
        starting = true
        defer { starting = false }
        let path = repository.trimmingCharacters(in: .whitespaces)
        do {
            let work = try await coding.start(store.businessID, NewCodingSession(
                employee: employeeID,
                provider: provider,
                objective: objective,
                repository: newRepository ? nil : path,
                newRepository: newRepository ? path : nil
            ))
            isPresented = false
            store.send(.refreshTapped)
            store.send(.threadOpened(work))
        } catch {
            problem = "The session didn't start. \(error.localizedDescription)"
        }
    }
}
