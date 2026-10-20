import ComposableArchitecture2
import DevysDesignSystem
import DevysWorkspace
import SwiftUI

@main
struct DevysMacApp: App {
    static let store = DevysComposition.makeLiveStore()
    static let preferences = DevysComposition.makePreferencesStore()
    @AppStorage("appearance") private var appearance = "system"

    /// QA: DEVYS_APPEARANCE=dark|light overrides the Settings choice.
    private var scheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["DEVYS_APPEARANCE"] ?? appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    static let showsGallery = ProcessInfo.processInfo.environment["DEVYS_GALLERY"] == "1"

    var body: some Scene {
        WindowGroup {
            Group {
                if Self.showsGallery {
                    DesignGallery()
                } else {
                    DevysAppScreen(store: Self.store)
                }
            }
                #if DEBUG
                    .task { await DevysComposition.enrollFromEnvironment() }
                    .modifier(OpenSettingsForQA())
                #endif
                .frame(minWidth: 760, minHeight: 560)
                .preferredColorScheme(scheme)
                // The workspace supplies native toolbar items; the toolbar shows
                // the frame color behind them.
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
                .containerBackground(DevysColors.frame, for: .window)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        // A window per terminal on the owner's Mac; closing it leaves the session running.
        WindowGroup("Terminal", for: TerminalRef.self) { $ref in
            if let ref {
                TerminalWindow(ref: ref).preferredColorScheme(scheme)
            }
        }
        .defaultSize(width: 900, height: 560)
        Settings {
            PreferencesScreen(store: Self.preferences)
                .preferredColorScheme(scheme)
        }
        #if DEBUG
            Window("Design Gallery", id: "gallery") {
                DesignGallery().frame(minWidth: 900, minHeight: 700)
            }
            .commands { DebugCommands() }
        #endif
    }
}

#if DEBUG
    private struct OpenSettingsForQA: ViewModifier {
        @Environment(\.openSettings) private var openSettings

        func body(content: Content) -> some View {
            content.task { if DevysComposition.opensSettingsAtLaunch { openSettings() } }
        }
    }

    private struct DebugCommands: Commands {
        @Environment(\.openWindow) private var openWindow

        var body: some Commands {
            CommandMenu("Debug") {
                Button("Design Gallery") { openWindow(id: "gallery") }
                    .keyboardShortcut("g", modifiers: [.command, .option])
            }
        }
    }
#endif
