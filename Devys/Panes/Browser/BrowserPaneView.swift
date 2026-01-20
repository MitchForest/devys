import SwiftUI

/// Complete browser pane with toolbar and webview.
struct BrowserPaneView: View {
    let paneId: UUID
    let state: BrowserState

    @Environment(\.canvasState) private var _canvas
    private var canvas: CanvasState { _canvas! }  // swiftlint:disable:this force_unwrapping

    @State private var store: WebViewStore

    init(paneId: UUID, state: BrowserState) {
        self.paneId = paneId
        self.state = state
        self._store = State(wrappedValue: WebViewStore(initialURL: state.url))
    }

    var body: some View {
        VStack(spacing: 0) {
            BrowserToolbar(store: store)

            ZStack {
                BrowserWebView(
                    store: store,
                    initialURL: state.url
                )

                // Error overlay
                if let error = store.errorMessage {
                    errorOverlay(message: error)
                }
            }
        }
        .onAppear {
            store.onTitleChange = { title in
                Task { @MainActor in
                    canvas.updatePaneTitle(paneId, title: title.isEmpty ? "Browser" : title)
                }
            }
        }
    }

    @ViewBuilder
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                store.clearError()
                store.reload()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Preview

#Preview {
    BrowserPaneView(
        paneId: UUID(),
        state: BrowserState()
    )
    .frame(width: 600, height: 400)
    .canvasState(CanvasState())
}
