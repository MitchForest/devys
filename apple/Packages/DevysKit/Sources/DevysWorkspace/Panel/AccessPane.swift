import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
import SwiftUI

/// Shown on a paused employee's desk and above a composer they'd answer, with the way back.
struct PausedBanner: View {
    let store: StoreOf<Workspace>
    let employee: Employee

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pause.circle.fill").foregroundStyle(DevysColors.gray).accessibilityHidden(true)
            Text("\(employee.name) is paused and takes no actions.")
                .font(DevysTypography.body).foregroundStyle(DevysColors.ink2)
            Spacer(minLength: 8)
            Button("Resume") { store.send(.pauseToggled(employee.id)) }
                .buttonStyle(DevysButtonStyle(.raised, compact: true))
        }
        .padding(12)
        .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
    }
}

/// What an employee may do, from the server: each grant, how it runs, and its limits.
struct AccessPane: View {
    let store: StoreOf<Workspace>
    let employee: Employee

    var body: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.compact) {
            HStack(spacing: 8) {
                Text("Standing access").font(DevysTypography.heading).foregroundStyle(DevysColors.ink)
                LiveTag()
                Spacer(minLength: 8)
                addMenu
            }
            switch store.access {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let message):
                EmptyNote(text: message)
            case .loaded(let list):
                if list.grants.isEmpty {
                    EmptyNote(text: "No access yet. \(employee.name) can talk with you but can't act until you grant something.")
                }
                ForEach(list.grants) { grant in
                    GrantRow(grant: grant) { store.send(.revokeTapped(employee.id, grant.id)) }
                }
            }
        }
        .onAppear { store.send(.accessRequested(employee.id)) }
        .onChange(of: employee.id) { _, id in store.send(.accessRequested(id)) }
    }

    @ViewBuilder private var addMenu: some View {
        if case .loaded(let list) = store.access, !list.available.isEmpty {
            Menu {
                ForEach(list.available) { capability in
                    // Anything that reaches outside the business asks first by default.
                    Button(AccessNames.title(capability.capability)) {
                        store.send(.grantTapped(employee.id, capability.capability, capability.effect == "external" ? .ask : .auto))
                    }
                }
            } label: {
                Label("Add access", systemImage: "plus")
            }
            .buttonStyle(DevysButtonStyle(.quiet, compact: true))
            .fixedSize()
        }
    }
}

private struct GrantRow: View {
    let grant: AccessGrant
    let revoke: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: DevysSpacing.compact) {
            Image(systemName: grant.mode == .ask ? "faceid" : "key")
                .foregroundStyle(grant.mode == .ask ? DevysColors.amber : DevysColors.ink3)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(AccessNames.title(grant.capability)).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                    Text(grant.mode == .ask ? "Asks first" : "Runs")
                        .font(DevysTypography.caption)
                        .foregroundStyle(grant.mode == .ask ? DevysColors.amber : DevysColors.ink3)
                }
                Text(grant.description).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(2)
                if !grant.hosts.isEmpty {
                    Text("Only \(grant.hosts.joined(separator: ", "))").font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                }
            }
            Spacer(minLength: 8)
            Button("Revoke", action: revoke)
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .opacity(hovering ? 1 : 0.55)
        }
        .padding(.vertical, 6)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// Plain names for capabilities; the description carries the detail.
enum AccessNames {
    private static let titles = [
        "recall": "Recall memory",
        "remember": "Remember facts",
        "forget": "Forget facts",
        "readPublicUrl": "Read public websites",
        "readSkill": "Read skills",
        "secretList": "See saved secrets",
        "importAttachment": "Import attachments",
        "read": "Read workspace files",
        "write": "Write workspace files",
        "run": "Run commands",
        "conversationHistory": "Read older conversation",
        "suggestReplies": "Offer replies to tap",
        "publishArtifact": "Save files for you",
        "driveList": "List Drive files",
        "driveRead": "Read Drive files",
        "driveCreate": "Create Drive files",
        "driveUpdate": "Update Drive files",
        "workList": "List work",
        "workCreate": "Take on work",
        "workUpdate": "Update work",
        "workComplete": "Complete work",
        "projectList": "List projects",
        "projectCreate": "Create projects",
        "projectUpdate": "Update projects",
        "projectAdd": "Add to projects",
        "hireEmployee": "Propose hires"
    ]

    static func title(_ capability: String) -> String { titles[capability] ?? capability }
}
