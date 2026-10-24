import DevysClient
import Foundation

/// What a ⌘K row does when it runs.
package enum PaletteCommand: Hashable, Sendable {
    case place(Place)
    case newEmployee
    case newProject
    case connectApps
    case shortcuts
    case settings(PreferencesSection)
    case layer(Layer)
}

/// A ⌘K row's picture: an employee's face, a project's tile, or a symbol.
package enum PaletteIcon: Hashable, Sendable {
    case employee(String)
    case project(String)
    case symbol(String)
}

/// One ⌘K row: a picture, a title, an optional grey second line, and what it runs.
package struct PaletteRow: Identifiable, Hashable, Sendable {
    package let id: String
    package let title: String
    package let detail: String?
    package let icon: PaletteIcon
    package let command: PaletteCommand
}

package enum PaletteIntent {
    case ran(PaletteCommand)
    case shortcutsToggled(Bool)
}

/// The app's keyboard shortcuts, as the Keyboard shortcuts sheet lists them.
package enum KeyboardShortcutList {
    package static let entries: [(title: String, keys: String)] = [
        ("Search", "⌘K"),
        ("New employee", "⌘N"),
        ("New project", "⇧⌘N"),
        ("Run a search result", "⌘1 – ⌘9"),
        ("Send", "↩"),
        ("Back", "⌘["),
        ("Back one layer, or close", "Esc"),
        ("Show or hide the sidebar", "⌃⌘S"),
        ("Stop the employee in view", "⌘."),
        ("Refresh", "⌘R"),
        ("Settings", "⌘,")
    ]
}

extension Workspace.State {
    /// ⌘K's rows. With no query: the Chief of Staff, the actions, each Settings section, then the
    /// other employees and the projects. Typing filters all of that plus threads and pages.
    package func paletteRows(_ query: String) -> [PaletteRow] {
        var rows: [PaletteRow] = []
        if let chief = chiefOfStaff {
            rows.append(PaletteRow(id: "dm-\(chief.id)", title: chief.name, detail: Self.roleLine(chief), icon: .employee(chief.id), command: .place(.home)))
        }
        rows += [
            PaletteRow(id: "new-employee", title: "New employee", detail: nil, icon: .symbol("person.badge.plus"), command: .newEmployee),
            PaletteRow(id: "new-project", title: "New project", detail: nil, icon: .symbol("folder.badge.plus"), command: .newProject),
            PaletteRow(id: "connect-apps", title: "Connect apps", detail: nil, icon: .symbol("square.grid.2x2"), command: .connectApps),
            PaletteRow(id: "shortcuts", title: "Keyboard shortcuts", detail: nil, icon: .symbol("command"), command: .shortcuts)
        ]
        rows += PreferencesSection.allCases.map { section in
            PaletteRow(id: "settings-\(section.rawValue)", title: "Settings: \(section.rawValue)", detail: "Settings", icon: .symbol(section.symbol), command: .settings(section))
        }
        rows += snapshot.employees.filter { !$0.isChiefOfStaff }.map { employee in
            PaletteRow(id: "dm-\(employee.id)", title: employee.name, detail: Self.roleLine(employee), icon: .employee(employee.id), command: .place(.direct(employee.id)))
        }
        rows += (projects.value ?? []).map { project in
            PaletteRow(id: "project-\(project.id)", title: project.name, detail: "Project", icon: .project(project.id), command: .place(.project(project.id)))
        }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return rows }
        rows += (work.value ?? []).filter(\.state.isOpen).map { item in
            PaletteRow(id: "work-\(item.id)", title: item.title, detail: "Work", icon: .symbol("checklist"), command: .layer(.work(item.id)))
        }
        rows += artifacts.filter { $0.contentType == "text/html" && $0.latestID == $0.id }.map { page in
            PaletteRow(id: "page-\(page.id)", title: artifactName(page.id), detail: "Page", icon: .symbol("doc.richtext"), command: .layer(.artifact(page.id)))
        }
        return rows.filter { $0.title.lowercased().contains(needle) || ($0.detail?.lowercased().contains(needle) ?? false) }
    }

    /// The role in the owner's words: the employee's responsibilities, or its role's name.
    private static func roleLine(_ employee: Employee) -> String {
        let responsibilities = employee.responsibilities.trimmingCharacters(in: .whitespacesAndNewlines)
        return responsibilities.isEmpty ? RoleTemplate.displayName(employee.template) : responsibilities
    }
}

extension Workspace {
    func reducePalette(_ intent: PaletteIntent, state: inout State) {
        switch intent {
        case .shortcutsToggled(let open):
            state.isShowingShortcuts = open
        case .ran(let command):
            state.isPaletteOpen = false
            switch command {
            case .place(let place): reducePlace(.selected(place), state: &state)
            case .newEmployee: reduceTeam(.hireTapped, state: &state)
            case .newProject: reduceProject(.newTapped, state: &state)
            case .connectApps: reduceSidebar(.connectAppsToggled(true), state: &state)
            case .shortcuts: state.isShowingShortcuts = true
            case .settings(let section): Self.openSettings(at: section, state: &state)
            case .layer(.work(let id)): reducePlace(.workOpened(id), state: &state)
            case .layer(let layer): reducePlace(.layerOpened(layer), state: &state)
            }
        }
    }
}
