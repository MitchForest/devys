import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

extension Business {
    var tileTint: BusinessTile.Tint { BusinessTile.Tint(rawValue: tint) ?? .blue }
}

extension WorkItemState {
    var chip: StatusChip { chip(size: .regular) }

    func chip(size: StatusChip.Size) -> StatusChip {
        switch self {
        case .needsDecision: StatusChip("Needs you", tone: .needsYou, size: size)
        case .inProgress: StatusChip("In progress", tone: .inProgress, size: size)
        case .waiting: StatusChip("Waiting", tone: .waiting, size: size)
        case .ready, .proposed: StatusChip("Ready", tone: .waiting, size: size)
        case .completed: StatusChip("Done", tone: .done, size: size)
        case .cancelled: StatusChip("Cancelled", tone: .waiting, size: size)
        }
    }

    var group: WorkGroup {
        switch self {
        case .needsDecision: .needsYou
        case .inProgress, .ready, .proposed: .inProgress
        case .waiting: .waiting
        case .completed, .cancelled: .done
        }
    }
}

extension Workspace.State {
    /// A place's title, and in a thread the project above it, so the breadcrumb reads
    /// "Launch › Fix sitemap".
    package func title(of place: Place) -> (title: String, parent: (title: String, place: Place)?) {
        switch place {
        case .home: return ("Home", nil)
        case .direct(let id): return (snapshot.employees.first { $0.id == id }?.name ?? "Message", nil)
        case .project(let id): return (projects.value?.first { $0.id == id }?.name ?? "Project", nil)
        case .thread(let id):
            let item = work.value?.first { $0.id == id }
            let project = item?.projectID.flatMap { projectID in projects.value?.first { $0.id == projectID } }
            return (item?.title ?? "Thread", project.map { ($0.name, Place.project($0.id)) })
        }
    }

    func project(_ id: String) -> Project? { projects.value?.first { $0.id == id } }

    func employee(_ id: String?) -> Employee? { snapshot.employees.first { $0.id == id } }

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
    func isMine(_ item: WorkItem) -> Bool {
        item.takenOverBy != nil && item.takenOverBy == account?.person.id
    }

    /// Who has taken the work item over, as the signed-in person reads it; nil while its
    /// employee has it.
    func takeoverTitle(_ item: WorkItem) -> String? {
        guard let person = item.takenOverBy else { return nil }
        if isMine(item) { return "You have it" }
        return "Taken over by \(members.first { $0.id == person }?.displayName ?? "another person")"
    }

    /// The owner's decisions waiting on this work item.
    func decisions(for item: WorkItem) -> [Decision] {
        decisions.value?.filter { $0.workItemID == item.id } ?? []
    }

    func employeeName(_ id: String) -> String {
        snapshot.employees.first { $0.id == id }?.name ?? "A former employee"
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
