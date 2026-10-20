/// Rail destinations (.docs/design/direction). The sidebar changes with them.
package enum Destination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, inbox, work, team, money, apps

    package var id: Self { self }

    package var title: String {
        switch self {
        case .home: "Home"
        case .inbox: "Inbox"
        case .work: "Work"
        case .team: "Team"
        case .money: "Money"
        case .apps: "Apps"
        }
    }

    package var symbol: String {
        switch self {
        case .home: "house"
        case .inbox: "tray"
        case .work: "checklist"
        case .team: "person.2"
        case .money: "dollarsign.circle"
        case .apps: "square.grid.2x2"
        }
    }

    /// Whether this destination's sidebar lists the page, so opening it keeps
    /// the owner where they are instead of switching sidebars.
    package func lists(_ page: Page) -> Bool {
        switch (self, page) {
        case (.home, .today), (.home, .approvals), (.home, .direct), (.home, .space), (.home, .employee): true
        default: page.destination == self
        }
    }

    /// iPhone tabs; Money and Apps open from Home there.
    package static let compact: [Destination] = [.home, .inbox, .work, .team]
}

/// What the main pane shows.
package enum Page: Hashable, Sendable {
    case today
    case approvals
    /// The business's files on the owner's Mac, opened at a file when one is given.
    case files(String?)
    /// A direct-message conversation with one employee.
    case direct(String)
    /// A space: its conversation, overview, work and files.
    case space(String)
    case employee(String?)
    case inbox
    case work(WorkFilter)
    case money
    case apps(AppsSection)

    package var destination: Destination {
        switch self {
        case .today, .approvals, .files, .direct, .space: .home
        case .employee: .team
        case .inbox: .inbox
        case .work: .work
        case .money: .money
        case .apps: .apps
        }
    }
}

package enum WorkFilter: String, CaseIterable, Hashable, Sendable {
    case all = "All work"
    case needsYou = "Needs you"
    case inProgress = "In progress"
    case waiting = "Waiting"
    case done = "Done"
}

package enum AppsSection: String, CaseIterable, Hashable, Sendable {
    case installed = "Installed"
    case connections = "Connections"
}

package enum EmployeeTab: String, CaseIterable, Hashable, Sendable {
    case activity = "Activity"
    case responsibilities = "Responsibilities"
    case memory = "Memory"
    case access = "Access"
}

/// A space's header tabs: its conversation first, then metrics, its work, and its files.
package enum SpaceTab: String, CaseIterable, Hashable, Sendable {
    case conversation = "Conversation"
    case overview = "Overview"
    case work = "Work"
    case files = "Files"
}

package enum WorkLayout: String, CaseIterable, Hashable, Sendable {
    case list = "List"
    case board = "Board"
}
