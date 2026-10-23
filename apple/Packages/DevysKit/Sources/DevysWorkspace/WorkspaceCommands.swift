#if os(macOS)
public import ComposableArchitecture2
public import SwiftUI

/// The Mac's menu bar for the workspace: File › New Employee (⌘N), New Project (⇧⌘N), Search…
/// (⌘K) and Connect Apps…. They act on the signed-in workspace; signed out they do nothing.
public struct WorkspaceCommands: Commands {
    private let store: StoreOf<DevysApp>

    public init(store: StoreOf<DevysApp>) {
        self.store = store
    }

    private var workspace: StoreOf<Workspace>? { store.spawn(\.workspace) }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Employee") { workspace?.send(.hireTapped) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Project") { workspace?.send(.newProjectTapped) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Search…") {
                if let workspace { workspace.send(.paletteToggled(!workspace.isPaletteOpen)) }
            }
            .keyboardShortcut("k", modifiers: .command)
            Button("Connect Apps…") { workspace?.send(.connectAppsToggled(true)) }
        }
    }
}
#endif
