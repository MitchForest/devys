import ChatUI
import ServerProtocol
import SwiftUI
import UI

struct IOSClientMainRootView: View {
    @Environment(\.devysTheme) private var theme
    @State private var store = AppStore()
    @State private var serverURLText: String = UserDefaults.standard.string(
        forKey: ConversationConnectionDefaults.serverURLKey
    ) ?? UserDefaults.standard.string(forKey: IOSClientConnectionStore.Keys.serverURL) ?? "http://127.0.0.1:8787"
    @State private var authTokenText: String = UserDefaults.standard.string(
        forKey: ConversationConnectionDefaults.authTokenKey
    ) ?? ""

    var body: some View {
        TabView {
            IOSChatsSurfaceView(store: store, connectAction: connectToServer)
                .tabItem {
                    Label("Chats", systemImage: "message.fill")
                }

            IOSWorkspacePlaceholderView(
                title: "Files",
                subtitle: "File browsing and syntax rendering move here in Phase 2.",
                icon: "doc.text.fill"
            )
            .tabItem {
                Label("Files", systemImage: "doc.text")
            }

            IOSWorkspacePlaceholderView(
                title: "Git",
                subtitle: "Repo status, branches, and hunk actions move here in Phase 2.",
                icon: "arrow.triangle.branch"
            )
            .tabItem {
                Label("Git", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }

            IOSClientRootView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }

            IOSConversationSettingsView(
                store: store,
                serverURLText: $serverURLText,
                authTokenText: $authTokenText,
                connectAction: connectToServer,
                disconnectAction: disconnectFromServer
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .tint(theme.accent)
        .onChange(of: serverURLText) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: ConversationConnectionDefaults.serverURLKey)
            UserDefaults.standard.set(newValue, forKey: IOSClientConnectionStore.Keys.serverURL)
        }
        .onChange(of: authTokenText) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: ConversationConnectionDefaults.authTokenKey)
            store.updateAuthToken(normalizedAuthToken(from: newValue))
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let latestURL = UserDefaults.standard.string(
                forKey: ConversationConnectionDefaults.serverURLKey
            ) ?? serverURLText
            if latestURL != serverURLText {
                serverURLText = latestURL
            }

            let latestToken = UserDefaults.standard.string(forKey: ConversationConnectionDefaults.authTokenKey) ?? ""
            if latestToken != authTokenText {
                authTokenText = latestToken
                store.updateAuthToken(normalizedAuthToken(from: latestToken))
            }
        }
    }

    private func connectToServer() {
        Task {
            guard let url = normalizedServerURL else { return }
            UserDefaults.standard.set(serverURLText, forKey: ConversationConnectionDefaults.serverURLKey)
            UserDefaults.standard.set(serverURLText, forKey: IOSClientConnectionStore.Keys.serverURL)
            UserDefaults.standard.set(authTokenText, forKey: ConversationConnectionDefaults.authTokenKey)
            await store.connect(to: url, authToken: normalizedAuthToken)
        }
    }

    private func disconnectFromServer() {
        Task {
            await store.disconnect()
        }
    }

    private var normalizedServerURL: URL? {
        var trimmed = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "http://\(trimmed)"
        }
        return URL(string: trimmed)
    }

    private var normalizedAuthToken: String? {
        normalizedAuthToken(from: authTokenText)
    }

    private func normalizedAuthToken(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Placeholder

private struct IOSWorkspacePlaceholderView: View {
    @Environment(\.devysTheme) private var theme

    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(theme.textTertiary.opacity(0.4))

                Text(title)
                    .font(ChatTokens.heading)
                    .foregroundStyle(theme.text)

                Text(subtitle)
                    .font(ChatTokens.secondary)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.base)
            .navigationTitle(title)
        }
    }
}

// MARK: - Settings

struct IOSConversationSettingsView: View {
    @Environment(\.devysTheme) private var theme
    let store: AppStore
    @Binding var serverURLText: String
    @Binding var authTokenText: String
    let connectAction: () -> Void
    let disconnectAction: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: connectionIcon)
                            .font(.system(size: 16))
                            .foregroundStyle(connectionColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status")
                                .font(ChatTokens.caption)
                                .foregroundStyle(theme.textSecondary)
                            Text(connectionStatusText)
                                .font(ChatTokens.body)
                                .foregroundStyle(theme.text)
                        }
                    }

                    TextField("http://127.0.0.1:8787", text: $serverURLText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(ChatTokens.secondary)

                    SecureField("Pairing bearer token (optional)", text: $authTokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(ChatTokens.secondary)

                    HStack(spacing: 12) {
                        Button {
                            connectAction()
                        } label: {
                            Text("Connect")
                                .font(ChatTokens.bodyBold)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(ChatTokens.userBubble)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            disconnectAction()
                        } label: {
                            Text("Disconnect")
                                .font(ChatTokens.bodyBold)
                                .foregroundStyle(theme.text)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(theme.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowSeparator(.hidden)
                } header: {
                    Text("Server")
                }

                Section {
                    HStack {
                        Text("Version")
                            .font(ChatTokens.body)
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text("1.0.0")
                            .font(ChatTokens.secondary)
                            .foregroundStyle(theme.textSecondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }

    private var connectionStatusText: String {
        switch store.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .failed(let message): return message
        }
    }

    private var connectionIcon: String {
        switch store.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.clockwise.circle"
        case .disconnected: return "circle"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .connected: return DevysColors.success
        case .connecting: return DevysColors.warning
        case .disconnected: return theme.textTertiary
        case .failed: return DevysColors.error
        }
    }
}

#Preview {
    IOSClientMainRootView()
        .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .white))
}
