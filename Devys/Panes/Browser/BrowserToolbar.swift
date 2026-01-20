import SwiftUI

/// Navigation toolbar for browser pane.
struct BrowserToolbar: View {
    let store: WebViewStore
    @State private var urlText: String = ""
    @FocusState private var isURLFieldFocused: Bool

    init(store: WebViewStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Back button
                Button(action: { store.goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoBack)
                .opacity(store.canGoBack ? 1 : 0.4)
                .help("Go Back")

                // Forward button
                Button(action: { store.goForward() }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!store.canGoForward)
                .opacity(store.canGoForward ? 1 : 0.4)
                .help("Go Forward")

                // Reload/Stop button
                Button(action: {
                    if store.isLoading {
                        store.stopLoading()
                    } else {
                        store.reload()
                    }
                }) {
                    Image(systemName: store.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(store.isLoading ? "Stop Loading" : "Reload")

                // URL field
                TextField("Enter URL", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .focused($isURLFieldFocused)
                    .onSubmit {
                        store.load(urlString: urlText)
                        isURLFieldFocused = false
                    }
                    .onChange(of: isURLFieldFocused) { _, focused in
                        if focused {
                            // Select all when focused
                            urlText = store.currentURL.absoluteString
                        }
                    }
                    .onChange(of: store.currentURL) { _, newURL in
                        if !isURLFieldFocused {
                            urlText = newURL.absoluteString
                        }
                    }
                    .onAppear {
                        urlText = store.currentURL.absoluteString
                    }

                // Localhost quick access menu
                Menu {
                    ForEach(BrowserState.commonPorts, id: \.port) { item in
                        Button("\(item.name) (:\(item.port))") {
                            store.load(url: URL(string: "http://localhost:\(item.port)")!)  // swiftlint:disable:this force_unwrapping
                        }
                    }
                } label: {
                    Image(systemName: "network")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Localhost Ports")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Progress bar
            if store.isLoading {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * store.loadProgress)
                        .animation(.easeInOut(duration: 0.2), value: store.loadProgress)
                }
                .frame(height: 2)
            } else {
                // Invisible spacer to maintain layout
                Color.clear.frame(height: 2)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
