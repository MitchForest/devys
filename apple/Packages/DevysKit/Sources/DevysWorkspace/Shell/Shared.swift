import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

extension Business {
    var tileTint: BusinessTile.Tint { BusinessTile.Tint(rawValue: tint) ?? .blue }
}

@MainActor
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
        case .unknown: StatusChip("Other", tone: .waiting, size: size)
        }
    }

    var group: WorkGroup {
        switch self {
        case .needsDecision: .needsYou
        case .inProgress, .ready, .proposed: .inProgress
        case .waiting, .unknown: .waiting
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

    /// A record's title from its ref, as the web names it: "Viewing Pricing".
    func recordTitle(_ ref: Ref) -> String {
        switch ref.recordKind {
        case "documents/artifact": artifactName(ref.id)
        case "documents/file": (ref.id as NSString).lastPathComponent
        case "code/session": "Coding session"
        case "work/item": work.value?.first { $0.id == ref.id }?.title ?? "Work item"
        case "work/project": project(ref.id)?.name ?? "Project"
        case "work/routine": routine(ref.id)?.title ?? "Routine"
        case "team/app": remoteApp(ref.id)?.name ?? "App"
        default: "Record"
        }
    }

    /// What a kept record shows now: a page's latest version (a page kept anywhere means the page,
    /// whichever version was kept); any other record as it is.
    func currentRef(_ ref: Ref) -> Ref {
        guard case .artifact(let id) = ref, let latest = artifacts.first(where: { $0.id == id })?.latestID else { return ref }
        return .artifact(latest)
    }

    /// The project's entry keeping this record, or any version of this page.
    func keptEntry(of record: Ref, in project: Project) -> ProjectItem? {
        project.items.first { currentRef($0.ref) == currentRef(record) }
    }

    /// What kind of record it is, under its title on a card: "File", "Coding session".
    func recordDetail(_ ref: Ref) -> String {
        switch ref.recordKind {
        case "documents/artifact": "Page"
        case "documents/file": "File"
        case "code/session": "Coding session"
        case "work/item": "Work item"
        case "work/project": "Project"
        case "work/routine": routine(ref.id)?.schedule ?? "Routine"
        case "team/app": "App"
        default: ""
        }
    }

    func project(_ id: String) -> Project? { projects.value?.first { $0.id == id } }

    func routine(_ id: String) -> Routine? { routines.value?.first { $0.id == id } }

    func employee(_ id: String?) -> Employee? { snapshot.employees.first { $0.id == id } }

    /// While talking by voice, the Chief of Staff's face follows the conversation.
    var voiceMood: BotMood? {
        switch voice {
        case .starting, .listening, .finishing: .listening
        case .awaitingReply: .thinking
        case .speaking: .working
        case .idle: nil
        }
    }

    var chiefOfStaffMood: BotMood {
        switch status {
        case .failed: .oops
        case .loading: .thinking
        case .loaded: isRunning ? .working : .idle
        }
    }

    /// An employee's face: the Chief of Staff follows its live state; everyone else their runtime.
    func mood(for employee: Employee) -> BotMood {
        if employee.id == chiefOfStaff?.id { return chiefOfStaffMood }
        return isWorking(employee.id) ? .working : .idle
    }

    /// Whether the signed-in person has taken the work item over from its employee.
    func isMine(_ item: WorkItem) -> Bool {
        item.takenOverBy != nil && item.takenOverBy == account?.person.id
    }

    /// Layers are read-only. The owner edits by hand only open work they have taken over, which
    /// fences its employee; otherwise they ask (owner decision, 2026-10-21).
    func isHandEditable(_ item: WorkItem) -> Bool {
        item.state.isOpen && isMine(item)
    }

    /// The work item of the thread on screen, which a layer opened here belongs to.
    var threadItem: WorkItem? {
        guard case .thread(let id) = place else { return nil }
        return work.value?.first { $0.id == id }
    }

    /// Who has taken the work item over, as the signed-in person reads it; nil while its
    /// employee has it.
    func takeoverTitle(_ item: WorkItem) -> String? {
        guard let person = item.takenOverBy else { return nil }
        if isMine(item) { return "You have it" }
        return "Taken over by \(members.first { $0.id == person }?.displayName ?? "another person")"
    }

    /// The requests waiting on the owner, from Home: the one source of what needs them.
    var decisions: [Decision] { home.value?.decisions ?? [] }

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
