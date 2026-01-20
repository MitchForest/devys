import SwiftUI

@main
struct DevysApp: App {
    /// Root workspace state managing all project tabs
    @State private var workspaceState = WorkspaceState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .workspaceState(workspaceState)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 800)
        .commands {
            AppCommands()
        }
    }
}
