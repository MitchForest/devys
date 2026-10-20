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
            .overlay {
                if store.isEnrolling {
                    ProgressView("Signing in…")
                        .padding(DevysSpacing.roomy)
                        .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.card, style: .continuous))
                        .devysElevation(.raised)
                }
            }
            .onOpenURL { store.send(.linkOpened($0)) }
            .confirmationDialog(
                "Sign in with this link?",
                isPresented: Binding(get: { store.pendingLink != nil }, set: { if !$0 { store.send(.linkCancelled) } }),
                titleVisibility: .visible
            ) {
                Button("Sign in and replace this session", role: .destructive) { store.send(.linkConfirmed) }
                Button("Cancel", role: .cancel) { store.send(.linkCancelled) }
            } message: {
                Text("This device is already signed in. Signing in to \(store.pendingLink?.server.host() ?? "the server") replaces the current session here.")
            }
            .alert(
                "Couldn't sign in",
                isPresented: Binding(get: { store.linkError != nil }, set: { if !$0 { store.send(.linkErrorDismissed) } })
            ) {
                Button("OK") { store.send(.linkErrorDismissed) }
            } message: {
                Text(store.linkError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        switch store.route {
        case .launching:
            ProgressView()
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
