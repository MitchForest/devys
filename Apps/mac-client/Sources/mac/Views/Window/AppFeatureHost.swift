import AppFeatures
import ComposableArchitecture
import SwiftUI

struct AppFeatureHost<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase

    let store: StoreOf<AppFeature>
    @ViewBuilder var content: Content

    @State private var hasSentLaunch = false

    init(
        store: StoreOf<AppFeature>,
        @ViewBuilder content: () -> Content
    ) {
        self.store = store
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                guard !hasSentLaunch else { return }
                hasSentLaunch = true
                store.send(.appDidFinishLaunching)
            }
            .onChange(of: scenePhase) { _, newValue in
                store.send(.scenePhaseChanged(AppLifecyclePhase(newValue)))
            }
    }
}

private extension AppLifecyclePhase {
    init(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            self = .active
        case .inactive:
            self = .inactive
        case .background:
            self = .background
        @unknown default:
            self = .inactive
        }
    }
}
