public import ComposableArchitecture2
import DevysClient
import DevysDesignSystem
public import SwiftUI

public struct DevysAppScreen: View {
    private let store: StoreOf<DevysApp>

    public init(store: StoreOf<DevysApp>) {
        self.store = store
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DevysColors.frame)
            .onOpenURL { store.send(.linkOpened($0)) }
    }

    @ViewBuilder private var content: some View {
        switch store.route {
        case .launching:
            Color.clear
        case .signedOut:
            if let signIn = store.spawn(\.signIn) {
                SignInScreen(store: signIn)
            }
        case .signedIn:
            if let workspace = store.spawn(\.workspace) {
                WorkspaceScreen(store: workspace)
            }
        }
    }
}
