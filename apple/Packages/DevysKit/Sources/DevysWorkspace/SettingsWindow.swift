#if os(macOS)
public import ComposableArchitecture2
import DevysDesignSystem
public import SwiftUI

/// The Mac's Settings window. It shows the signed-in workspace's own Settings (one store, the same
/// one iPhone and iPad show as a sheet), so closing the window reloads what Settings changed.
public struct SettingsWindow: View {
    private let store: StoreOf<DevysApp>

    public init(store: StoreOf<DevysApp>) {
        self.store = store
    }

    public var body: some View {
        if let workspace = store.spawn(\.workspace) {
            WorkspaceSettings(store: workspace)
        } else {
            Text("Sign in to change settings.")
                .font(DevysTypography.body)
                .foregroundStyle(DevysColors.ink3)
                .frame(width: 640, height: 480)
        }
    }
}

private struct WorkspaceSettings: View {
    let store: StoreOf<Workspace>

    var body: some View {
        Group {
            if let preferences = store.spawn(\.preferences) {
                PreferencesScreen(store: preferences)
            } else {
                ProgressView().frame(width: 640, height: 480)
            }
        }
        // Opened at a section already (as "Apps & connections…" does), it stays there.
        .onAppear { if store.preferences == nil { store.send(.preferencesToggled(true)) } }
        .onDisappear { store.send(.preferencesToggled(false)) }
    }
}
#endif
