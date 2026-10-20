import DevysCharacter
package import DevysClient
import DevysDesignSystem
import SwiftUI

extension Business {
    var tileTint: BusinessTile.Tint { BusinessTile.Tint(rawValue: tint) ?? .blue }
}

extension CommitmentState {
    var chip: StatusChip {
        switch self {
        case .needsDecision: StatusChip("Needs you", tone: .needsYou)
        case .inProgress: StatusChip("In progress", tone: .inProgress)
        case .waiting: StatusChip("Waiting", tone: .waiting)
        case .ready, .proposed: StatusChip("Ready", tone: .waiting)
        case .completed: StatusChip("Done", tone: .done)
        case .cancelled: StatusChip("Cancelled", tone: .waiting)
        }
    }

    var filter: WorkFilter {
        switch self {
        case .needsDecision: .needsYou
        case .inProgress, .ready, .proposed: .inProgress
        case .waiting: .waiting
        case .completed, .cancelled: .done
        }
    }
}

extension Workspace.State {
    var pageTitle: String {
        switch page {
        case .today: "Today"
        case .approvals: "Approvals"
        case .files: "Files"
        case .direct(let id): employeeName(id)
        case .space(let id): spaces.value?.first { $0.id == id }?.name ?? "Space"
        case .employee(let id): snapshot.employees.first { $0.id == id }?.name ?? "Team"
        case .inbox: "Inbox"
        case .work(let filter): filter == .all ? "Work" : filter.rawValue
        case .money: "Money"
        case .apps(let section): section.rawValue
        }
    }

    /// While talking by voice, Operations' face follows the conversation.
    var voiceMood: BotMood? {
        switch voice {
        case .starting, .listening, .finishing: .listening
        case .awaitingReply: .thinking
        case .speaking: .working
        case .idle: nil
        }
    }

    var operationsMood: BotMood {
        switch status {
        case .failed: .oops
        case .loading: .thinking
        case .loaded: isRunning ? .working : .idle
        }
    }

    /// An employee's face: Operations follows its live state; everyone else their runtime.
    func mood(for employee: Employee) -> BotMood {
        if employee.id == operations?.id { return operationsMood }
        return isWorking(employee.id) ? .working : .idle
    }

    /// Whether the signed-in person has taken the work item over from its employee.
    func isMine(_ item: Commitment) -> Bool {
        item.takenOverBy != nil && item.takenOverBy == account?.person.id
    }

    /// Who has taken the work item over, as the signed-in person reads it; nil while its
    /// employee has it.
    func takeoverTitle(_ item: Commitment) -> String? {
        guard let person = item.takenOverBy else { return nil }
        if isMine(item) { return "You have it" }
        return "Taken over by \(members.first { $0.id == person }?.displayName ?? "another person")"
    }

    /// The owner's decisions waiting on this work item.
    func decisions(for item: Commitment) -> [Decision] {
        decisions.value?.filter { $0.commitmentID == item.id } ?? []
    }

    func work(_ filter: WorkFilter) -> [Commitment] {
        let items = work.value ?? []
        return filter == .all ? items : items.filter { $0.state.filter == filter }
    }

    /// Requests waiting on the owner. A "needs decision" commitment is also waiting on them.
    var needsYouCount: Int {
        (decisions.value?.count ?? 0) + (work.value?.filter { $0.state == .needsDecision }.count ?? 0)
    }

    func employeeName(_ id: String) -> String {
        snapshot.employees.first { $0.id == id }?.name ?? "A former employee"
    }
}

/// The pane-level page scaffold: title row with optional trailing controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: DevysSpacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DevysTypography.title).foregroundStyle(DevysColors.ink)
                if let subtitle {
                    Text(subtitle).font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
                }
            }
            Spacer(minLength: DevysSpacing.compact)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        trailing = EmptyView()
    }
}

/// Scrollable page body with the design's measure and arrival motion.
struct PageBody<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DevysSpacing.section) {
                content
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, DevysSpacing.page)
            .padding(.top, DevysSpacing.section)
            .padding(.bottom, DevysSpacing.page)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .transition(.opacity.combined(with: .offset(y: 6)))
    }
}

struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DevysTypography.body)
            .foregroundStyle(DevysColors.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DevysSpacing.regular)
            .overlay {
                RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous)
                    .strokeBorder(DevysColors.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            }
    }
}

extension Workspace.State {
    func portrait(for employee: Employee) -> PortraitSource {
        Self.portrait(for: employee, target: .employee(business: businessID, employee: employee.id), photos: lookPhotos)
    }

    func portrait(for business: Business) -> PortraitSource {
        Self.portrait(for: business, photos: lookPhotos)
    }

    static func portrait(for employee: Employee, target: LookTarget, photos: [String: Data]) -> PortraitSource {
        portrait(look: employee.look, photo: photo(employee.look, target, photos), fallback: .face(employee.avatar))
    }

    static func portrait(for business: Business, photos: [String: Data]) -> PortraitSource {
        portrait(
            look: business.look,
            photo: photo(business.look, .business(business.id), photos),
            fallback: .initials(business.initial, tint: business.tileTint)
        )
    }

    private static func photo(_ look: Look?, _ target: LookTarget, _ photos: [String: Data]) -> Data? {
        guard case .photo(let version) = look else { return nil }
        return photos[target.photoKey(version)]
    }

    var ownerPortrait: PortraitSource {
        if let ownerPhoto { return .photo(ownerPhoto) }
        return .initials(ownerFirstName?.prefix(1).uppercased() ?? "·", tint: .purple)
    }

    static func portrait(look: Look?, photo: Data?, fallback: PortraitSource) -> PortraitSource {
        switch look {
        case .face(let spec): .face(spec)
        case .emoji(let emoji, let tint): .emoji(emoji, tint: BusinessTile.Tint(rawValue: tint) ?? .blue)
        case .photo: photo.map(PortraitSource.photo) ?? fallback
        case nil: fallback
        }
    }
}

/// What one teammate is doing, when it's worth a glance. Idle teammates aren't shown.
package struct Presence: Equatable, Identifiable {
    package enum Signal: Equatable {
        case working
        case needsYou(Int)
        case failed
        case paused
    }

    package let employee: Employee
    package let signal: Signal
    package var id: String { employee.id }

    package var summary: String {
        switch signal {
        case .working: "\(employee.name) is working"
        case .needsYou(let count): "\(employee.name) needs you · \(count) decision\(count == 1 ? "" : "s")"
        case .failed: "\(employee.name) couldn't finish the last request"
        case .paused: "\(employee.name) is paused"
        }
    }
}

extension Workspace.State {
    /// Teammates worth a glance: working, waiting on you, failed or paused. The same rule as the
    /// web's `presence`, from each employee's runtime status and the decisions they're waiting on.
    package var presence: [Presence] {
        snapshot.employees.compactMap { employee in
            let decisions = decisions.value?.filter { $0.employeeID == employee.id }.count ?? 0
            let status = employee.id == operations?.id ? status.value : statuses[employee.id]
            let latest = status?.state.inbox.max { $0.receivedAt < $1.receivedAt }
            let signal: Presence.Signal?
            if employee.paused || status?.state.run?.stopped == true {
                signal = .paused
            } else if isWorking(employee.id) {
                signal = .working
            } else if decisions > 0 {
                signal = .needsYou(decisions)
            } else if latest?.status == "failed" {
                signal = .failed
            } else {
                signal = nil
            }
            return signal.map { Presence(employee: employee, signal: $0) }
        }
    }
}
