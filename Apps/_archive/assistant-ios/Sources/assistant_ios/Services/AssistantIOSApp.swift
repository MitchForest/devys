import SwiftUI
import UI

@main
struct AssistantIOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSAssistantRootView()
                .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .white))
        }
    }
}
