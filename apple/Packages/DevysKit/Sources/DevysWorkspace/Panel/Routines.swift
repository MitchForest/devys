import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

// Routines as the owner sees them: listed on an employee's desk and a project's overview, read in
// their layer, and proposed as a card in the chat. A running routine changes only by a new decision, so the
// owner pauses and resumes it here and changes it by asking its employee. The same words as the web.

/// How routines and waiting work read, as the web words them.
enum RoutineText {
    static func state(_ state: RoutineState) -> String {
        switch state {
        case .active: "Active"
        case .paused: "Paused"
        case .proposed: "Proposed"
        case .unknown: "Other"
        }
    }

    static func color(_ state: RoutineState) -> Color {
        switch state {
        case .active: DevysColors.green
        case .proposed: DevysColors.amber
        case .paused, .unknown: DevysColors.ink3
        }
    }

    static func notify(_ notify: RoutineNotify) -> String {
        switch notify {
        case .always: "Always posts"
        case .whenFound: "Posts only when something needs attention"
        case .unknown: "Posts as the server decides"
        }
    }

    /// A time still to come: "Today 2:21 PM", "Tomorrow 9:00 AM", "Thu 9:00 AM" within the week,
    /// else "Oct 30, 9:00 AM". A next run, or when waiting work looks again.
    static func upcoming(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        if date > now, date.timeIntervalSince(now) < 6 * 86_400 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }

    /// "Today 2:21 PM", "Yesterday 9:04 AM", "Mon 9:04 AM" or a date: a run that happened.
    static func past(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        if now.timeIntervalSince(date) < 7 * 86_400 { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// The next run while active, as a row reads it.
    static func nextRun(_ routine: Routine) -> String? {
        guard routine.state == .active, let next = routine.nextRunAt.flatMap(ServerDate.parse) else { return nil }
        return upcoming(next)
    }

    /// What waiting work waits on and when it looks again: "waiting on the press kit until Thu
    /// 9:00 AM", "waiting until Tomorrow 9:00 AM"; nil when neither is known.
    static func waiting(_ item: WorkItem) -> String? {
        let until = item.wakeAt.flatMap(ServerDate.parse).map { "until \(upcoming($0))" }
        if let condition = item.waitCondition, !condition.isEmpty {
            return "waiting on \(condition)\(until.map { " \($0)" } ?? "")"
        }
        return until.map { "waiting \($0)" }
    }

    /// Long instructions start folded, so a proposal reads at a glance.
    static func isLong(_ text: String) -> Bool {
        text.count > 240 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 4
    }
}

/// The routines given, as a section; callers leave it out when there are none.
struct RoutinesSection: View {
    let store: StoreOf<Workspace>
    let routines: [Routine]

    var body: some View {
        if !routines.isEmpty {
            PanelSection(title: "Routines", count: routines.count) {
                ForEach(routines) { RoutineRow(store: store, routine: $0) }
            }
        }
    }
}

/// One routine: what, when, its state, next run and last result. It opens its layer.
private struct RoutineRow: View {
    let store: StoreOf<Workspace>
    let routine: Routine
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Button { store.send(.layerOpened(.routine(routine.id))) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "repeat").font(.system(size: 12)).foregroundStyle(DevysColors.ink3).padding(.top, 2).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(routine.title).font(DevysTypography.secondary.weight(.medium)).foregroundStyle(DevysColors.ink).lineLimit(1)
                            Text(RoutineText.state(routine.state)).font(DevysTypography.caption).foregroundStyle(RoutineText.color(routine.state)).fixedSize()
                        }
                        Text([routine.schedule, RoutineText.nextRun(routine).map { "Next run \($0)" }].compactMap(\.self).joined(separator: " · "))
                            .font(DevysTypography.caption).foregroundStyle(DevysColors.ink3).lineLimit(1)
                        if let last = routine.lastResult {
                            Text("Last: \(last)").font(DevysTypography.caption).foregroundStyle(DevysColors.ink2).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RoutinePauseButton(store: store, routine: routine, style: DevysButtonStyle(.quiet, compact: true))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(hovering ? DevysColors.sheetTint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, -8)
        .onHover { hovering = $0 }
    }
}

/// Pause for an active routine, Resume for a paused one; a proposed one is decided on its card in the chat.
private struct RoutinePauseButton: View {
    let store: StoreOf<Workspace>
    let routine: Routine
    let style: DevysButtonStyle

    var body: some View {
        switch routine.state {
        case .active: Button("Pause") { store.send(.routinePauseTapped(routine.id)) }.buttonStyle(style).fixedSize()
        case .paused: Button("Resume") { store.send(.routineResumeTapped(routine.id)) }.buttonStyle(style).fixedSize()
        case .proposed, .unknown: EmptyView()
        }
    }
}

/// A routine's facts, as its layer and its proposal show them alike.
private struct RoutineFacts: View {
    let store: StoreOf<Workspace>
    let routine: Routine
    var more = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            row("Schedule") { Text(routine.schedule) }
            row("Notify") { Text(RoutineText.notify(routine.notify)) }
            if more, let next = RoutineText.nextRun(routine) {
                row("Next run") { Text(next) }
            }
            if more, let last = routine.lastRunAt.flatMap(ServerDate.parse) {
                row("Last run") { Text(RoutineText.past(last)) }
            }
            if more, let result = routine.lastResult {
                row("Result") { Text(result).textSelection(.enabled) }
            }
            if more, let employee = store.state.employee(routine.employeeID) {
                row("Employee") {
                    Button { store.send(.message(employee.id)) } label: {
                        HStack(spacing: 6) {
                            Portrait(store.state.portrait(for: employee), size: 18, isAnimated: false)
                            Text(employee.name)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let project = routine.projectID.flatMap(store.state.project) {
                row("Project") {
                    Button(project.name) { store.send(.placeSelected(.project(project.id))) }.buttonStyle(.plain)
                }
            }
        }
        .font(DevysTypography.secondary)
    }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(DevysColors.ink3)
            value().foregroundStyle(DevysColors.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A routine, read-only: what it does, when, and what its last run said; Pause or Resume, and Ask
/// to change it.
struct RoutineLayer: View {
    let store: StoreOf<Workspace>
    let routineID: String

    var body: some View {
        ScrollView {
            if let routine = store.state.routine(routineID) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routine.title).font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                        HStack(spacing: 0) {
                            Text(RoutineText.state(routine.state)).foregroundStyle(RoutineText.color(routine.state))
                            if routine.state == .proposed {
                                Text(" · Waiting for your decision").foregroundStyle(DevysColors.ink3)
                            }
                        }
                        .font(DevysTypography.secondary)
                    }
                    Text(routine.instruction).font(DevysTypography.body).foregroundStyle(DevysColors.ink).textSelection(.enabled)
                    RoutineFacts(store: store, routine: routine, more: true)
                    HStack(spacing: 6) {
                        RoutinePauseButton(store: store, routine: routine, style: DevysButtonStyle(.raised, compact: true))
                        Button("Ask", systemImage: "quote.bubble") { store.send(.askTapped("\(routine.title) · \(routine.schedule)")) }
                            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                            .fixedSize()
                            .help("Quote this routine in the conversation to ask for a change")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 24)
            } else {
                EmptyNote(text: "This routine no longer exists.").padding(14)
            }
        }
    }
}

/// An employee's proposed routine, one card where it was asked, readable as a whole; approving
/// activates exactly this revision.
struct RoutineProposal: View {
    let store: StoreOf<Workspace>
    let decision: Decision
    let routine: Routine
    @State private var open = false

    var body: some View {
        let employee = store.state.employee(decision.employeeID)
        let long = RoutineText.isLong(routine.instruction)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let employee { Portrait(store.state.portrait(for: employee), size: 22, isAnimated: false) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(employee?.name ?? "An employee") proposes a routine").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                    Text(routine.title).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
                }
                .lineLimit(1)
            }
            RoutineFacts(store: store, routine: routine)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.instruction)
                    .font(DevysTypography.secondary)
                    .foregroundStyle(DevysColors.ink2)
                    .lineLimit(long && !open ? 3 : nil)
                    .textSelection(.enabled)
                if long {
                    Button(open ? "Less" : "More") { open.toggle() }
                        .buttonStyle(.plain).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
                }
            }
            HStack(spacing: 6) {
                Button("Approve", systemImage: "checkmark") { store.send(.decisionAnswered(decision.id, approve: true)) }
                    .buttonStyle(DevysButtonStyle(.aurora, compact: true))
                Button("Decline") { store.send(.decisionAnswered(decision.id, approve: false)) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
            }
        }
        .devysCard(padding: 12)
    }
}
