import AppFeatures
import ComposableArchitecture
import Testing

@Suite("AppFeature Tests")
struct AppFeatureTests {
    @Test("Launch marks the app as finished launching")
    @MainActor
    func appLaunchLifecycle() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.appDidFinishLaunching) {
            $0.lifecycle.hasFinishedLaunching = true
        }
        await store.receive(.window(.startWorkspaceOperationalObservation))
        await store.receive(.window(.startWorkflowObservation))
    }

    @Test("Scene phase updates lifecycle state")
    @MainActor
    func scenePhaseLifecycle() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }

        await store.send(.scenePhaseChanged(.active)) {
            $0.lifecycle.scenePhase = .active
        }
    }
}
