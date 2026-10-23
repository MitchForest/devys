import ComposableArchitecture2
import DevysDesignSystem
import DevysWorkspace
import SwiftUI

@main
struct DevysMacApp: App {
    static let store = DevysComposition.makeLiveStore()
    @AppStorage("appearance") private var appearance = "system"

    private var scheme: ColorScheme? {
        #if DEBUG
            // QA: DEVYS_APPEARANCE=dark|light overrides the Settings choice.
            let appearance = ProcessInfo.processInfo.environment["DEVYS_APPEARANCE"] ?? appearance
        #endif
        return switch appearance {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            root
                #if DEBUG
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
        .commands { WorkspaceCommands(store: Self.store) }
        // A window per terminal on the owner's Mac; closing it leaves the session running.
        WindowGroup("Terminal", for: TerminalRef.self) { $ref in
            if let ref {
                TerminalWindow(ref: ref).preferredColorScheme(scheme)
            }
        }
        .defaultSize(width: 900, height: 560)
        Settings {
            SettingsWindow(store: Self.store)
                .preferredColorScheme(scheme)
        }
        #if DEBUG
            Window("Design Gallery", id: "gallery") {
                DesignGallery().frame(minWidth: 900, minHeight: 700)
            }
            .commands { DebugCommands() }
        #endif
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
            // QA: DEVYS_GALLERY=1 opens the design gallery instead of the app.
            if ProcessInfo.processInfo.environment["DEVYS_GALLERY"] == "1" {
                DesignGallery()
            } else {
                DevysAppScreen(store: Self.store)
            }
        #else
            DevysAppScreen(store: Self.store)
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
