import AppFeatures
import SwiftUI

@MainActor
extension ContentView {
    func addRepositorySheet(
        for _: AddRepositoryPresentation
    ) -> some View {
        presentedSheetContent(
            AddRepositorySheet(
                onSelectLocal: {
                    store.send(.setAddRepositoryPresentation(nil))
                    Task { @MainActor in
                        store.send(.requestOpenRepository)
                    }
                },
                onSelectSSH: {
                    store.send(.setAddRepositoryPresentation(nil))
                    Task { @MainActor in
                        store.send(.setRemoteRepositoryPresentation(RemoteRepositoryPresentation()))
                    }
                },
                onCancel: {
                    store.send(.setAddRepositoryPresentation(nil))
                }
            )
        )
    }
}
