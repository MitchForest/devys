import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// A channel's permanent view: what the project is for and by when, who is on it, its work by
/// status and the records it keeps. Everything opens a thread or a layer.
struct Overview: View {
    let store: StoreOf<Workspace>
    let projectID: String
    let close: () -> Void
    @State private var editing = false
    @State private var showsDone = false

    var body: some View {
        if let project = store.state.project(projectID) {
            let work = (store.work.value ?? []).filter { $0.projectID == project.id }
            VStack(spacing: 0) {
                PanelHeader(title: "Overview", close: close) {
                    if !editing {
                        ToolbarIconButton("Edit project", symbol: "pencil") { editing = true }
                    }
                }
                PanelBody {
                    if editing {
                        ProjectForm(store: store, initial: project, submitLabel: "Save") { change in
                            store.send(.projectUpdated(project.id, change))
                            editing = false
                        } cancel: {
                            editing = false
                        }
                    } else {
                        summary(project, work: work)
                    }
                    workSection(project, work: work)
                    kept(project)
                }
            }
        } else {
            VStack(spacing: 0) {
                PanelHeader(title: "Project", close: close)
                PanelBody { EmptyNote(text: "This project no longer exists.") }
            }
        }
    }

    @ViewBuilder private func summary(_ project: Project, work: [Commitment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let goal = project.goal {
                Text(goal).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
            } else {
                Button("Add a goal") { editing = true }
                    .buttonStyle(.plain).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                if let deadline = project.deadline {
                    row("Deadline") { Text(ProjectText.deadline(deadline)) }
                }
                if let budget = project.budget {
                    row("Budget") { Text(ProjectText.money(budget)) }
                }
                if let lead = store.state.employee(project.leadEmployeeID) {
                    row("Lead") {
                        Button { store.send(.message(lead.id)) } label: {
                            HStack(spacing: 6) {
                                Portrait(store.state.portrait(for: lead), size: 18, isAnimated: false)
                                Text(lead.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                let members = store.snapshot.employees.filter { project.memberIDs.contains($0.id) && $0.id != project.leadEmployeeID }
                if !members.isEmpty {
                    row("Team") {
                        HStack(spacing: 4) {
                            ForEach(members) { member in
                                Button { store.send(.message(member.id)) } label: {
                                    Portrait(store.state.portrait(for: member), size: 20, isAnimated: false)
                                }
                                .buttonStyle(.plain)
                                .help(member.name)
                                .accessibilityLabel(member.name)
                            }
                        }
                    }
                }
                if !work.isEmpty {
                    let done = work.filter { $0.state.group == .done }.count
                    row("Progress") {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(done), total: Double(work.count))
                                .tint(DevysColors.green)
                                .frame(width: 96)
                            Text("\(done) of \(work.count)")
                        }
                    }
                }
            }
            .font(DevysTypography.secondary)
        }
    }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow {
            Text(label).foregroundStyle(DevysColors.ink3)
            value().foregroundStyle(DevysColors.ink)
        }
    }

    @ViewBuilder private func workSection(_ project: Project, work: [Commitment]) -> some View {
        let done = work.filter { $0.state.group == .done }
        PanelSection(title: "Work") {
            PanelAction(title: "Thread") { store.send(.newTaskTapped(project: project.id)) }
        } content: {
            if work.isEmpty {
                Text("No threads yet. Ask in the channel and work starts here.")
                    .font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
            }
            ForEach([WorkGroup.needsYou, .inProgress, .waiting], id: \.self) { group in
                let items = work.filter { $0.state.group == group }
                if !items.isEmpty {
                    Text(group.rawValue).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).padding(.top, 6)
                    ForEach(items) { WorkRow(store: store, item: $0, compact: true) }
                }
            }
            if !done.isEmpty {
                Button(showsDone ? "Hide done" : "Done · \(done.count)") { showsDone.toggle() }
                    .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).padding(.top, 6)
                if showsDone { ForEach(done) { WorkRow(store: store, item: $0, compact: true) } }
            }
        }
    }

    @ViewBuilder private func kept(_ project: Project) -> some View {
        let kept = project.items.map { (id: $0.id, layer: Layer(ref: $0.ref)) }
        let pages = kept.compactMap { item in
            if case .artifact(let page, _) = item.layer, store.artifacts.contains(where: { $0.id == page }) { (id: item.id, page: page) } else { nil }
        }
        let files = kept.compactMap { item in if case .file(let path) = item.layer { (id: item.id, path: path) } else { nil } }
        if !pages.isEmpty || !files.isEmpty {
            PanelSection(title: "Kept", count: pages.count + files.count) {
                ForEach(pages, id: \.id) { item in
                    KeptRow(title: store.state.artifactName(item.page)) { store.send(.layerOpened(.artifact(item.page))) }
                }
                ForEach(files, id: \.id) { item in
                    KeptRow(title: (item.path as NSString).lastPathComponent) { store.send(.layerOpened(.file(item.path))) }
                }
            }
        }
    }
}

private struct KeptRow: View {
    let title: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Label(title, systemImage: "doc.text")
                .font(DevysTypography.secondary)
                .foregroundStyle(DevysColors.ink)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// How a project's deadline and budget read.
enum ProjectText {
    /// "Nov 30 · 12d", "· today", or "· 3d late".
    static func deadline(_ day: String, now: Date = .now) -> String {
        guard let date = Self.day.date(from: day) else { return day }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now), to: date).day ?? 0
        let label = date.formatted(.dateTime.month(.abbreviated).day())
        return days < 0 ? "\(label) · \(-days)d late" : days == 0 ? "\(label) · today" : "\(label) · \(days)d"
    }

    static func money(_ budget: Budget) -> String {
        (Double(budget.cents) / 100).formatted(.currency(code: budget.currency).precision(.fractionLength(0)))
    }

    /// `YYYY-MM-DD` in the owner's calendar, as the server stores a deadline.
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Name, goal, deadline, budget, lead and team, saved as one change.
struct ProjectForm: View {
    let store: StoreOf<Workspace>
    var initial: Project?
    let submitLabel: String
    var busy = false
    let submit: (ProjectChange) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var goal = ""
    @State private var hasDeadline = false
    @State private var deadline = Date.now.addingTimeInterval(14 * 86_400)
    @State private var budget = ""
    @State private var lead = ""
    @State private var members: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name") { FieldBox { TextField("Launch", text: $name) } }
            field("Goal") { FieldBox { TextField("What done looks like (optional)", text: $goal, axis: .vertical).lineLimit(2...5) } }
            HStack(alignment: .top, spacing: 12) {
                field("Deadline") {
                    HStack(spacing: 6) {
                        Toggle("Deadline", isOn: $hasDeadline).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        if hasDeadline { DatePicker("Deadline", selection: $deadline, displayedComponents: .date).labelsHidden() }
                    }
                }
                field("Budget") {
                    FieldBox { TextField("None", text: $budget) }
                        .onChange(of: budget) { _, value in budget = value.filter { $0.isNumber || $0 == "." } }
                }
            }
            field("Lead") {
                Picker("Lead", selection: $lead) {
                    ForEach(store.snapshot.employees) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
            }
            field("Team") { team }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(DevysButtonStyle(.quiet, compact: true))
                Button(busy ? "Saving…" : submitLabel) { submit(change) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
                    .disabled(busy || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: reset)
        .onKeyPress(.escape) {
            cancel()
            return .handled
        }
    }

    private var team: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.snapshot.employees.filter { $0.id != lead }) { employee in
                    let isOn = members.contains(employee.id)
                    Button {
                        if isOn { members.removeAll { $0 == employee.id } } else { members.append(employee.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Portrait(store.state.portrait(for: employee), size: 18, isAnimated: false)
                            Text(employee.name).font(DevysTypography.caption)
                        }
                        .padding(.leading, 2)
                        .padding(.trailing, 10)
                        .padding(.vertical, 2)
                        .foregroundStyle(isOn ? DevysColors.sheet : DevysColors.ink2)
                        .background(isOn ? DevysColors.ink : DevysColors.sheetTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.never)
    }

    private var change: ProjectChange {
        let goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = Double(budget)
        return ProjectChange(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: goal.isEmpty ? nil : String(goal.prefix(500)),
            deadline: hasDeadline ? ProjectText.day.string(from: deadline) : nil,
            budget: amount.flatMap { $0 >= 0 ? Budget(cents: Int(($0 * 100).rounded()), currency: initial?.budget?.currency ?? "USD") : nil },
            lead: lead.isEmpty ? nil : lead,
            members: members.filter { $0 != lead }
        )
    }

    private func reset() {
        name = initial?.name ?? ""
        goal = initial?.goal ?? ""
        if let day = initial?.deadline.flatMap(ProjectText.day.date(from:)) {
            hasDeadline = true
            deadline = day
        }
        budget = initial?.budget.map { String($0.cents / 100) } ?? ""
        lead = initial?.leadEmployeeID ?? store.operations?.id ?? ""
        members = initial?.memberIDs ?? []
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(DevysTypography.label).foregroundStyle(DevysColors.ink3)
            content()
        }
    }
}

/// New project: the same fields as the overview's edit form; it opens once created.
struct NewProjectSheet: View {
    let store: StoreOf<Workspace>

    var body: some View {
        if let sheet = store.newProject {
            VStack(alignment: .leading, spacing: DevysSpacing.regular) {
                Text("New project").font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                ProjectForm(store: store, submitLabel: "Create", busy: sheet.isSubmitting) { project in
                    store.send(.projectCreateTapped(project))
                } cancel: {
                    store.send(.newProjectDismissed)
                }
                if let error = sheet.error {
                    Label(error, systemImage: "exclamationmark.circle.fill").font(DevysTypography.secondary).foregroundStyle(DevysColors.red)
                }
                Spacer(minLength: 0)
            }
            .padding(DevysSpacing.roomy)
            .sheetFrame(width: 460, height: 500)
            .background(DevysColors.sheet)
            .presentationDetents([.large])
        }
    }
}
