import ComposableArchitecture2
import DevysDesignSystem
import DevysWorkspace
import SwiftUI

@main
struct DevysIOSApp: App {
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
            .preferredColorScheme(scheme)
                #if DEBUG
                    .task { await DevysComposition.enrollFromEnvironment() }
                #endif
        }
        // On iPad a terminal gets a window of its own; iPhone shows it full screen instead.
        WindowGroup("Terminal", for: TerminalRef.self) { $ref in
            if let ref {
                TerminalWindow(ref: ref).preferredColorScheme(scheme)
            }
        }
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
