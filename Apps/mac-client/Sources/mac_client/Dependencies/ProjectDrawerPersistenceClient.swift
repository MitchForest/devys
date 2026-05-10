import ComposableArchitecture
import Foundation

struct ProjectDrawerSectionState: Equatable, Sendable {
    var changesExpanded: Bool
    var filesExpanded: Bool

    init(changesExpanded: Bool = true, filesExpanded: Bool = true) {
        self.changesExpanded = changesExpanded
        self.filesExpanded = filesExpanded
    }
}

struct ProjectDrawerPersistenceClient: Sendable {
    var loadPinned: @Sendable (URL?) -> Bool
    var savePinned: @Sendable (URL?, Bool) -> Void
    var loadSections: @Sendable (URL?) -> ProjectDrawerSectionState
    var saveSections: @Sendable (URL?, ProjectDrawerSectionState) -> Void

    init(
        loadPinned: @escaping @Sendable (URL?) -> Bool,
        savePinned: @escaping @Sendable (URL?, Bool) -> Void,
        loadSections: @escaping @Sendable (URL?) -> ProjectDrawerSectionState,
        saveSections: @escaping @Sendable (URL?, ProjectDrawerSectionState) -> Void
    ) {
        self.loadPinned = loadPinned
        self.savePinned = savePinned
        self.loadSections = loadSections
        self.saveSections = saveSections
    }
}

private enum ProjectDrawerPersistenceClientKey: DependencyKey {
    static let liveValue = ProjectDrawerPersistenceClient(
        loadPinned: { projectRootURL in
            UserDefaults.standard.bool(forKey: pinDefaultsKey(projectRootURL))
        },
        savePinned: { projectRootURL, isPinned in
            UserDefaults.standard.set(isPinned, forKey: pinDefaultsKey(projectRootURL))
        },
        loadSections: { projectRootURL in
            let defaults = UserDefaults.standard
            let changesKey = changesExpandedKey(projectRootURL)
            let filesKey = filesExpandedKey(projectRootURL)
            return ProjectDrawerSectionState(
                changesExpanded: defaults.object(forKey: changesKey) == nil
                    ? true
                    : defaults.bool(forKey: changesKey),
                filesExpanded: defaults.object(forKey: filesKey) == nil
                    ? true
                    : defaults.bool(forKey: filesKey)
            )
        },
        saveSections: { projectRootURL, state in
            let defaults = UserDefaults.standard
            defaults.set(state.changesExpanded, forKey: changesExpandedKey(projectRootURL))
            defaults.set(state.filesExpanded, forKey: filesExpandedKey(projectRootURL))
        }
    )
}

extension DependencyValues {
    var projectDrawerPersistenceClient: ProjectDrawerPersistenceClient {
        get { self[ProjectDrawerPersistenceClientKey.self] }
        set { self[ProjectDrawerPersistenceClientKey.self] = newValue }
    }
}

private func drawerScope(_ projectRootURL: URL?) -> String {
    projectRootURL?.standardizedFileURL.path ?? "unbound"
}

private func pinDefaultsKey(_ projectRootURL: URL?) -> String {
    "com.devys.terminal.project-drawer-pinned.\(drawerScope(projectRootURL))"
}

private func changesExpandedKey(_ projectRootURL: URL?) -> String {
    "com.devys.terminal.project-drawer-changes-expanded.\(drawerScope(projectRootURL))"
}

private func filesExpandedKey(_ projectRootURL: URL?) -> String {
    "com.devys.terminal.project-drawer-files-expanded.\(drawerScope(projectRootURL))"
}
