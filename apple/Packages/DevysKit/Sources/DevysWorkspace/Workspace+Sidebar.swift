import ComposableArchitecture2
import Dependencies
package import DevysClient
package import Foundation

// MARK: - The sidebar: pinned tiles, active projects and chats; Connect apps

/// One sidebar entry: an employee's direct chat or a project's channel, as the signed-in person
/// keeps it (pinned, unread) with its newest line.
package struct SidebarEntry: Equatable, Identifiable {
    package enum Subject: Equatable {
        case employee(String)
        case project(String)
    }

    package let subject: Subject
    package let key: ConversationKey
    /// Where it opens: the Chief of Staff's chat is Home.
    package let place: Place
    package let title: String
    /// The newest message's first line.
    package let preview: String?
    package let date: Date?
    package let unread: Int
    package let isPinned: Bool

    package var id: String { key.rawValue }
}

/// The sidebar as drawn: pinned tiles, then Projects (only active ones), then Chats.
package struct SidebarLayout: Equatable {
    package var pinned: [SidebarEntry] = []
    package var projects: [SidebarEntry] = []
    package var chats: [SidebarEntry] = []
}

package enum SidebarIntent {
    /// Pin, hide or mark unread, for the signed-in person; the sidebar changes before the server answers.
    case marked(ConversationKey, SidebarMark)
    case connectAppsToggled(Bool)
    case listedRequested
    case listedLoaded(businessID: String, Loadable<[ListedApp]>)
}

extension Workspace.State {
    /// Every employee has a chat row (one not yet talked to as well), and every active project a
    /// channel row, unless hidden; pinned ones are tiles. Employees keep the team's order (the
    /// Chief of Staff first) as tiles, and chats go most recent first.
    package var sidebar: SidebarLayout {
        var layout = SidebarLayout()
        let employees = snapshot.employees.compactMap { employee -> SidebarEntry? in
            let key = ConversationKey.direct(employee.id)
            return entry(.employee(employee.id), key: key, place: employee.isChiefOfStaff ? .home : .direct(employee.id), title: employee.name)
        }
        let channels = (projects.value ?? []).compactMap { project -> SidebarEntry? in
            let channel = entry(.project(project.id), key: .project(project.id), place: .project(project.id), title: project.name)
            guard let channel, channel.isPinned || isActive(project) else { return nil }
            return channel
        }
        layout.pinned = employees.filter(\.isPinned) + channels.filter(\.isPinned)
        layout.projects = channels.filter { !$0.isPinned }
        let chats = employees.filter { !$0.isPinned }
        // Stable: rows with no message yet keep the team's order, after the talked-to ones.
        layout.chats = chats.enumerated().sorted { first, second in
            switch (first.element.date, second.element.date) {
            case let (one?, two?) where one != two: one > two
            case (.some, nil): true
            case (nil, .some): false
            default: first.offset < second.offset
            }
        }.map(\.element)
        return layout
    }

    /// A project shows while it has open work, or before it has any; once all its work is done it
    /// leaves the sidebar (still found with ⌘K, or pinned).
    package func isActive(_ project: Project) -> Bool {
        let items = (work.value ?? []).filter { $0.projectID == project.id }
        return items.isEmpty || items.contains { $0.state.isOpen }
    }

    private func entry(_ subject: SidebarEntry.Subject, key: ConversationKey, place: Place, title: String) -> SidebarEntry? {
        let summary = summaries[key.rawValue]
        if summary?.hidden == true { return nil }
        let line = summary?.last?.text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        return SidebarEntry(
            subject: subject,
            key: key,
            place: place,
            title: title,
            preview: line,
            date: summary?.last?.date,
            unread: summary?.unread ?? 0,
            isPinned: summary?.pinned ?? false
        )
    }

    /// The connected apps' logos for the Connect apps button, else the first listed ones.
    package var connectLogos: [(name: String, logo: String?)] {
        let connected = (apps.value ?? []).filter { $0.state != nil }.map { (name: $0.name, logo: $0.logo) }
        if !connected.isEmpty { return Array(connected.prefix(3)) }
        return (listedApps.value ?? []).prefix(3).map { (name: $0.name, logo: Optional($0.logo)) }
    }
}

extension Workspace {
    func reduceSidebar(_ intent: SidebarIntent, state: inout State) {
        switch intent {
        case .marked(let key, let mark):
            markSidebar(key, mark, state: &state)
        case .connectAppsToggled(let open):
            state.isConnectingApps = open
            if open {
                loadListedApps(state)
            } else {
                // An app added or turned on in the sheet shows in the button and its connected list.
                loadWork(state)
            }
        case .listedRequested:
            loadListedApps(state)
            loadWork(state)
        case .listedLoaded(let businessID, let listed):
            guard businessID == state.businessID else { return }
            if case .failed = listed, state.listedApps.value != nil { return }
            state.listedApps = listed
        }
    }

    private func markSidebar(_ key: ConversationKey, _ mark: SidebarMark, state: inout State) {
        guard !state.businessID.isEmpty else { return }
        let current = state.summaries[key.rawValue] ?? ConversationSummary(key: key.rawValue, last: nil, unread: 0)
        state.summaries[key.rawValue] = current.with(
            unread: mark.unread.map { $0 ? max(current.unread, 1) : 0 },
            pinned: mark.pinned,
            hidden: mark.hidden
        )
        // Hiding the conversation on screen goes back to the Chief of Staff's.
        if mark.hidden == true, state.mainKey == key { reducePlace(.selected(.home), state: &state) }
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            do {
                try await runtime.markSidebar(businessID, key, mark)
            } catch {
                try store.send(Action(.stopFinished("That change to the sidebar didn't save.")))
            }
            guard let summaries = try? await runtime.conversations(businessID) else { return }
            try store.send(Action(.conversation(.summariesLoaded(businessID: businessID, summaries))))
        }
    }

    func loadListedApps(_ state: State) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            do {
                try store.send(Action(.sidebar(.listedLoaded(businessID: businessID, .loaded(try await runtime.listedApps(businessID))))))
            } catch {
                try store.send(Action(.sidebar(.listedLoaded(businessID: businessID, .failed("The apps couldn't be loaded.")))))
            }
        }
    }
}
