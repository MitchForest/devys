import ComposableArchitecture
import Foundation

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var launchCount = 0
        var closePolicy = ClosePolicyFeature.State()
        var selectedWindowGroupID: WindowGroupFeature.State.ID?
        var windowGroups: [WindowGroupFeature.State] = []

        var selectedProjectRootURL: URL? {
            guard let selectedWindowGroupID else { return nil }
            return windowGroups.first { $0.id == selectedWindowGroupID }?.projectRootURL
        }
    }

    enum Action: Equatable {
        case applicationDidFinishLaunching
        case bindProjectRoot(URL?, windowGroupID: WindowGroupFeature.State.ID)
        case closePolicy(ClosePolicyFeature.Action)
        case nativeWindowClosed
        case nativeWindowSelected(WindowGroupFeature.State.ID)
        case openNewTab(
            WindowTabKind,
            projectRootURL: URL? = nil,
            windowGroupID: WindowGroupFeature.State.ID? = nil
        )
        case openNewWindow(
            id: WindowGroupFeature.State.ID? = nil,
            tabKind: WindowTabKind = .terminal,
            projectRootURL: URL? = nil
        )
        case selectWindowGroup(WindowGroupFeature.State.ID)
    }

    @Dependency(\.uuid) private var uuid

    var body: some ReducerOf<Self> {
        Scope(state: \.closePolicy, action: \.closePolicy) {
            ClosePolicyFeature()
        }
        Reduce { state, action in
            switch action {
            case .applicationDidFinishLaunching:
                state.launchCount += 1
                return .none

            case .nativeWindowClosed:
                return .none

            case let .nativeWindowSelected(windowGroupID):
                guard state.windowGroups.contains(where: { $0.id == windowGroupID }) else {
                    return .none
                }
                state.selectedWindowGroupID = windowGroupID
                return .none

            case let .bindProjectRoot(url, windowGroupID):
                guard let index = state.windowGroups.firstIndex(where: { $0.id == windowGroupID }) else {
                    return .none
                }
                state.windowGroups[index].bindProjectRoot(url)
                return .none

            case .closePolicy:
                return .none

            case let .openNewTab(kind, projectRootURL, windowGroupID):
                let targetWindowGroupID = windowGroupID ?? state.selectedWindowGroupID
                guard let targetWindowGroupID,
                      let index = state.windowGroups.firstIndex(where: { $0.id == targetWindowGroupID }) else {
                    let windowGroupID = targetWindowGroupID ?? uuid()
                    let initialTabID = uuid()
                    state.windowGroups.append(
                        WindowGroupFeature.State(
                            id: windowGroupID,
                            projectRootURL: projectRootURL,
                            initialTabID: initialTabID,
                            initialTabKind: kind
                        )
                    )
                    state.selectedWindowGroupID = windowGroupID
                    return .none
                }
                state.selectedWindowGroupID = targetWindowGroupID
                state.windowGroups[index].openTab(
                    kind,
                    requestedProjectRootURL: projectRootURL,
                    id: uuid()
                )
                return .none

            case let .openNewWindow(id, tabKind, projectRootURL):
                let windowGroupID = id ?? uuid()
                let initialTabID = uuid()
                state.windowGroups.append(
                    WindowGroupFeature.State(
                        id: windowGroupID,
                        projectRootURL: projectRootURL,
                        initialTabID: initialTabID,
                        initialTabKind: tabKind
                    )
                )
                state.selectedWindowGroupID = windowGroupID
                return .none

            case let .selectWindowGroup(windowGroupID):
                guard state.windowGroups.contains(where: { $0.id == windowGroupID }) else {
                    return .none
                }
                state.selectedWindowGroupID = windowGroupID
                return .none
            }
        }
    }
}
