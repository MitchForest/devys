import DevysCharacter
import Foundation

// Fixture businesses, teams and runtime answers for tests and SwiftUI previews. Debug builds
// only: the shipped app never contains them.
#if DEBUG
    extension WorkspaceSnapshot {
        /// Fixture businesses for previews and tests; the live app never shows them.
        public static let acmeLaunch = WorkspaceSnapshot(
            business: Business(id: "acme", name: "Acme"),
            employees: [
                Employee(
                    id: "ops",
                    name: "Head of Operations",
                    role: "Coordinates launch work and brings you decisions",
                    template: "operations",
                    avatar: AvatarSpec(palette: .blue, shape: .roundedSquare, seed: 7),
                    summary: "Updating the launch plan after your note on email"
                ),
                Employee(
                    id: "engineering",
                    name: "Engineering",
                    role: "Builds, verifies and deploys Acme",
                    template: "engineering",
                    avatar: AvatarSpec(palette: .green, shape: .hexagon, seed: 3),
                    summary: "Ready to deploy a preview once GitHub is connected"
                ),
                Employee(
                    id: "growth",
                    name: "Growth",
                    role: "Measurement, PR and campaigns",
                    template: "growth",
                    avatar: AvatarSpec(palette: .orange, shape: .blob, seed: 11),
                    summary: "Waiting on your approval to send the PR inquiry"
                ),
                Employee(
                    id: "business-ops",
                    name: "Business Operations",
                    role: "Accounts, purchases and suppliers",
                    template: "business-operations",
                    avatar: AvatarSpec(palette: .purple, shape: .capsule, seed: 5),
                    summary: "Comparing Workspace plans"
                )
            ]
        )

        public static let globexGrowth = WorkspaceSnapshot(
            business: Business(id: "globex", name: "Globex"),
            employees: [
                Employee(
                    id: "globex-ops",
                    name: "Head of Operations",
                    role: "Coordinates Globex's growth work",
                    template: "operations",
                    avatar: AvatarSpec(palette: .teal, shape: .circle, seed: 2),
                    summary: "Watching sign-ups and support"
                )
            ]
        )
    }

    extension RuntimeClient {
        /// Answers from the fixture businesses, for SwiftUI previews and tests.
        public static let fixture = Self(
            account: { .fixture },
            business: { id in BusinessDetail.fixture(id) },
            createBusiness: { business in Business(id: business.name.lowercased(), name: business.name, brief: business.brief) },
            status: { _ in .fixture },
            stop: { _ in true },
            memory: { _ in MemoryClaim.fixtures },
            conversation: { _, key, _ in .fixture(key) },
            models: { .fixture },
            projects: { id in id == WorkspaceSnapshot.acmeLaunch.business.id ? Project.fixtures : [] },
            apps: { _ in AppEntry.fixtures }
        )
    }

    extension Project {
        public static let fixtures = [
            Project(
                id: "launch",
                name: "Launch",
                goal: "Acme open to its first customers",
                deadline: "2026-11-30",
                budget: Budget(cents: 50_000),
                leadEmployeeID: "ops",
                memberIDs: ["engineering", "growth"]
            )
        ]
    }

    extension AppEntry {
        /// Documents and Code installed, and two of the system apps every business has.
        public static let fixtures = [
            AppEntry(
                id: "documents",
                name: "Documents",
                icon: "file-text",
                summary: "Documents, pages, sheets and uploads",
                skills: [Skill(name: "writing-pages", description: "Publishing a page")]
            ),
            AppEntry(id: "code", name: "Code", icon: "code", summary: "Repositories, coding sessions and deploys"),
            AppEntry(id: "work", name: "Work", icon: "list-checks", summary: "Work items and the projects they belong to", kind: .system, pinned: false, visible: false),
            AppEntry(id: "memory", name: "Memory", icon: "brain", summary: "What the business knows", kind: .system, pinned: false, visible: false)
        ]
    }

    extension Account {
        public static let fixture = Account(
            person: Person(id: "person-preview", displayName: "Mitch"),
            businesses: [WorkspaceSnapshot.acmeLaunch.business, WorkspaceSnapshot.globexGrowth.business]
        )
    }

    extension BusinessDetail {
        /// A fixture business's team.
        public static func fixture(_ id: String) -> Self {
            let sample = id == WorkspaceSnapshot.globexGrowth.business.id ? WorkspaceSnapshot.globexGrowth : .acmeLaunch
            return BusinessDetail(business: sample.business, employees: sample.employees, artifacts: [])
        }
    }

    extension EmployeeStatus {
        public static let fixture = EmployeeStatus(
            state: RuntimeState(
                run: nil,
                inbox: [
                    InboxEntry(id: "m2", text: "Draft the PR pricing inquiry", receivedAt: 1_760_880_000_000, status: "done"),
                    InboxEntry(id: "m1", text: "What is blocking launch?", receivedAt: 1_760_870_000_000, status: "done")
                ],
                outbox: [
                    OutboxEntry(id: "m2", text: "Draft ready for your review.", status: "sent"),
                    OutboxEntry(id: "m1", text: "Domain, mailbox and measurement.", status: "sent")
                ],
                usage: RuntimeUsage(models: [
                    "gateway/claude-opus-5-5": RuntimeUsage.ModelUsage(
                        input: 3_000,
                        output: 1_500,
                        cacheRead: 20_000,
                        cacheWrite: 0,
                        cost: RuntimeUsage.Cost(total: 0.0625)
                    )
                ])
            )
        )
    }

    extension MemoryClaim {
        public static let fixtures = [
            MemoryClaim(
                key: "acme.launch-window",
                content: "Acme launch work runs November 2026 through April 2027.",
                sourceKind: "user",
                revision: 1,
                updatedAt: "2026-10-19T15:00:00.000Z"
            )
        ]
    }

    extension ConversationPage {
        /// A short sample exchange in any conversation, for previews.
        public static func fixture(_ key: ConversationKey) -> Self {
            let employee = key.kind == .direct ? key.ref : "ops"
            func message(_ id: String, _ author: String, _ text: String, at seconds: Int, replyTo: String? = nil, reactions: [String] = []) -> ConversationMessage {
                ConversationMessage(
                    id: id,
                    conversation: key.rawValue,
                    author: author,
                    text: text,
                    replyTo: replyTo,
                    createdAt: Date(timeIntervalSince1970: 1_760_870_000 + Double(seconds)).formatted(.iso8601),
                    reactions: reactions
                )
            }
            return ConversationPage(
                messages: [
                    message("m1", "person:person-preview", "What is blocking launch?", at: 0),
                    message("m2", "employee:\(employee)", "Domain, mailbox and measurement. The domain quote needs your approval.", at: 10, reactions: ["👍"]),
                    message("m3", "person:person-preview", "Draft the PR pricing inquiry", at: 10_000, replyTo: "m2"),
                    message("m4", "employee:\(employee)", "Draft ready for your review.", at: 10_020)
                ],
                respondent: employee
            )
        }
    }
#endif
