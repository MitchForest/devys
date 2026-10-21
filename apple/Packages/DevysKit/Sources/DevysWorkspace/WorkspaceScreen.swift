import ComposableArchitecture2
import SwiftUI

/// macOS and regular-width iPad get the frame-and-workspace shell; compact
/// width (iPhone, narrow iPad) gets tabs with full-screen conversations.
struct WorkspaceScreen: View {
    let store: StoreOf<Workspace>
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        shell.modifier(WorkspaceSheets(store: store))
            .onChange(of: scenePhase, initial: true) { _, phase in store.send(.activeChanged(phase == .active)) }
    }

    @ViewBuilder private var shell: some View {
        #if os(iOS)
            if sizeClass == .compact {
                CompactShell(store: store)
            } else {
                RegularShell(store: store)
            }
        #else
            RegularShell(store: store)
        #endif
    }
}
