import ComposableArchitecture
import RemoteFeatures
import SwiftUI
import UI

@main
struct IOSClientApp: App {
    @State private var store = IOSAppBootstrap.makeStore()

    var body: some Scene {
        WindowGroup {
            IOSClientRootView(store: store)
                .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
                .environment(\.densityLayout, DensityLayout(.comfortable))
                .environment(\.density, .comfortable)
        }
    }
}
