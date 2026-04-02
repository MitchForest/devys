import SwiftUI
import UI

@main
struct IOSClientApp: App {
    var body: some Scene {
        WindowGroup {
            IOSClientMainRootView()
                .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .white))
        }
    }
}
