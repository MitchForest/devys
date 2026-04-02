import AppKit
import SwiftUI
import UI

@MainActor
final class AssistantMacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct AssistantMacApp: App {
    @NSApplicationDelegateAdaptor(AssistantMacAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AssistantRootView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .white))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
    }
}
