import ComposableArchitecture2
import DevysDesignSystem
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
        if store.account != nil, store.businesses.isEmpty {
            FirstBusiness(store: store)
        } else {
            workspace
        }
    }

    private var workspace: some View {
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

/// Signed in with no business yet: start one with Settings' New business form, as on the web.
/// Once it exists, Settings closes and the workspace loads it.
private struct FirstBusiness: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ScrollView {
            Group {
                if let preferences = store.spawn(\.preferences), preferences.newBusiness != nil {
                    NewBusinessSheet(store: preferences, isFirst: true)
                        .onChange(of: preferences.businesses.isEmpty) { _, empty in
                            if !empty { store.send(.preferencesToggled(false)) }
                        }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: 520)
            .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: DevysRadius.sheet, style: .continuous))
            .devysElevation(.raised)
            .padding(DevysSpacing.roomy)
            .frame(maxWidth: .infinity, minHeight: 560)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(DevysColors.frame)
    }
}
