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
            // A task, not `onChange(initial:)`: SwiftUI can flush a pending initial onChange
            // synchronously while a reducer mutates observed state (the first account load),
            // and sending then traps on the store's re-entrancy check.
            .task(id: scenePhase) { store.send(.activeChanged(scenePhase == .active)) }
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
