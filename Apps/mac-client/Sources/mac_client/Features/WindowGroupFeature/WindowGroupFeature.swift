import ComposableArchitecture
import Foundation

@Reducer
struct WindowGroupFeature {
    @ObservableState
    struct State: Equatable, Identifiable {
        let id: UUID
        var projectRootURL: URL?
        var tabs: [WorkspaceTab]
        var selectedTabID: WorkspaceTab.ID?

        init(
            id: UUID,
            projectRootURL: URL? = nil,
            initialTabID: WorkspaceTab.ID,
            initialTabKind: WindowTabKind = .terminal
        ) {
            let standardizedProjectRootURL = projectRootURL?.standardizedFileURL
            self.id = id
            self.projectRootURL = standardizedProjectRootURL
            self.tabs = [
                WorkspaceTab(
                    id: initialTabID,
                    kind: initialTabKind,
                    projectRootURL: standardizedProjectRootURL
                )
            ]
            self.selectedTabID = initialTabID
        }

        mutating func openTab(
            _ kind: WindowTabKind,
            requestedProjectRootURL: URL?,
            id tabID: WorkspaceTab.ID
        ) {
            let effectiveProjectRootURL = requestedProjectRootURL?.standardizedFileURL
                ?? projectRootURL
            tabs.append(
                WorkspaceTab(
                    id: tabID,
                    kind: kind,
                    projectRootURL: effectiveProjectRootURL
                )
            )
            selectedTabID = tabID
        }

        mutating func bindProjectRoot(_ url: URL?) {
            let standardizedURL = url?.standardizedFileURL
            projectRootURL = standardizedURL
            for index in tabs.indices {
                tabs[index].projectRootURL = standardizedURL
            }
        }
    }

    enum Action: Equatable {
        case bindProjectRoot(URL?)
        case closeTab(WorkspaceTab.ID)
        case openTab(WindowTabKind, projectRootURL: URL? = nil)
        case selectTab(WorkspaceTab.ID)
    }

    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .bindProjectRoot(url):
                state.bindProjectRoot(url)
                return .none

            case let .closeTab(tabID):
                state.tabs.removeAll { $0.id == tabID }
                if state.selectedTabID == tabID {
                    state.selectedTabID = state.tabs.last?.id
                }
                return .none

            case let .openTab(kind, projectRootURL):
                state.openTab(
                    kind,
                    requestedProjectRootURL: projectRootURL,
                    id: uuid()
                )
                return .none

            case let .selectTab(tabID):
                guard state.tabs.contains(where: { $0.id == tabID }) else {
                    return .none
                }
                state.selectedTabID = tabID
                return .none
            }
        }
    }
}
