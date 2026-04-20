import ComposableArchitecture
import Foundation

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public struct Lifecycle: Equatable {
            public var hasFinishedLaunching = false
            public var scenePhase: AppLifecyclePhase?

            public init(
                hasFinishedLaunching: Bool = false,
                scenePhase: AppLifecyclePhase? = nil
            ) {
                self.hasFinishedLaunching = hasFinishedLaunching
                self.scenePhase = scenePhase
            }
        }

        public var lifecycle = Lifecycle()
        public var window = WindowFeature.State()

        public init(
            lifecycle: Lifecycle = Lifecycle(),
            window: WindowFeature.State = WindowFeature.State()
        ) {
            self.lifecycle = lifecycle
            self.window = window
        }
    }

    public enum Action: Equatable {
        case appDidFinishLaunching
        case scenePhaseChanged(AppLifecyclePhase)
        case window(WindowFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.window, action: \.window) {
            WindowFeature()
        }

        Reduce { state, action in
            switch action {
            case .appDidFinishLaunching:
                state.lifecycle.hasFinishedLaunching = true
                return .merge(
                    .send(.window(.loadRemoteRepositories)),
                    .send(.window(.startWorkspaceOperationalObservation)),
                    .send(.window(.startWorkflowObservation))
                )

            case .scenePhaseChanged(let phase):
                state.lifecycle.scenePhase = phase
                return .none

            case .window:
                return .none
            }
        }
    }
}
