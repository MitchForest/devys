import ChatUI
import SwiftUI
import UI

struct IOSChatsSurfaceView: View {
    @Environment(\.devysTheme) private var theme
    let store: AppStore
    var connectAction: (() -> Void)?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            IOSConversationDetailView(store: store)
        }
        .task {
            if case .disconnected = store.connectionState {
                connectAction?()
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch sidebarState {
                case .disconnected:
                    disconnectedState
                case .connecting:
                    connectingState
                case .empty:
                    emptySessionsState
                case .loaded:
                    sessionList
                case .failed(let message):
                    failedState(message: message)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.base)

            // Floating new chat button
            if case .connected = store.connectionState {
                newChatButton
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { await store.reloadSessions() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List(selection: selectedSessionBinding) {
            ForEach(store.sessionListStore.sessions) { session in
                IOSSessionRowView(session: session)
                .tag(Optional(session.id))
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(session.id == store.sessionListStore.selectedSessionID
                              ? theme.elevated : Color.clear)
                        .padding(.horizontal, 8)
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        Task { await store.deleteSession(session.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        Task { await store.archiveSession(session.id) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await store.reloadSessions()
        }
    }

    // MARK: - New Chat FAB

    private var newChatButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            Task { await store.createSession() }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(ChatTokens.userBubble)
                .clipShape(Circle())
                .shadow(color: ChatTokens.userBubble.opacity(0.4), radius: 8, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: - State Views

    private var disconnectedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(theme.textTertiary)

            Text("Not Connected")
                .font(ChatTokens.title)
                .foregroundStyle(theme.text)

            Text("Connect to your Devys server to start chatting.")
                .font(ChatTokens.secondary)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                connectAction?()
            } label: {
                Text("Connect")
                    .font(ChatTokens.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(ChatTokens.userBubble)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    private var connectingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Connecting...")
                .font(ChatTokens.secondary)
                .foregroundStyle(theme.textSecondary)
        }
    }

    private var emptySessionsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(theme.textTertiary)

            Text("No Conversations")
                .font(ChatTokens.title)
                .foregroundStyle(theme.text)

            Text("Tap the compose button to start your first conversation with Devys.")
                .font(ChatTokens.secondary)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func failedState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(DevysColors.warning)

            Text("Connection Failed")
                .font(ChatTokens.title)
                .foregroundStyle(theme.text)

            Text(message)
                .font(ChatTokens.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                connectAction?()
            } label: {
                Text("Retry")
                    .font(ChatTokens.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 200)
                    .padding(.vertical, 12)
                    .background(ChatTokens.userBubble)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var sidebarState: SidebarState {
        switch store.connectionState {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .failed(let message):
            return .failed(message)
        case .connected:
            if store.sessionListStore.sessions.isEmpty {
                return .empty
            }
            return .loaded
        }
    }

    private enum SidebarState {
        case disconnected
        case connecting
        case empty
        case loaded
        case failed(String)
    }

    private var selectedSessionBinding: Binding<String?> {
        Binding(
            get: { store.sessionListStore.selectedSessionID },
            set: { newValue in
                Task { await store.selectSession(newValue) }
            }
        )
    }
}

// MARK: - Session Row

private struct IOSSessionRowView: View {
    @Environment(\.devysTheme) private var theme
    let session: Session

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            sessionAvatar

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.title)
                        .font(hasUnread ? ChatTokens.bodyBold : ChatTokens.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(Self.timeFormatter.localizedString(for: session.updatedAt, relativeTo: .now))
                        .font(ChatTokens.micro)
                        .foregroundStyle(hasUnread ? ChatTokens.userBubble : theme.textTertiary)
                }

                HStack(alignment: .top) {
                    Group {
                        if let preview = session.lastMessagePreview, !preview.isEmpty {
                            Text(preview)
                        } else {
                            Text("\(session.harnessType.rawValue) · \(session.model)")
                        }
                    }
                    .font(ChatTokens.secondary)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)

                    Spacer(minLength: 4)

                    if hasUnread {
                        unreadBadge
                    } else {
                        statusIndicator
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Avatar

    private var sessionAvatar: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: ChatTokens.avatarSize, height: ChatTokens.avatarSize)

            Image(systemName: avatarIcon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var avatarGradient: LinearGradient {
        let colors: [Color]
        switch session.status {
        case .streaming:
            colors = [Color(hex: "#34C759"), Color(hex: "#30D158")]
        case .waitingInput:
            colors = [Color(hex: "#FF9500"), Color(hex: "#FFB347")]
        case .failed:
            colors = [Color(hex: "#FF3B30"), Color(hex: "#FF6B6B")]
        default:
            colors = [Color(hex: "#5856D6"), Color(hex: "#AF52DE")]
        }
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var avatarIcon: String {
        switch session.harnessType {
        case .codex:
            return "chevron.left.forwardslash.chevron.right"
        case .claudeCode:
            return "brain"
        default:
            return "bubble.left.fill"
        }
    }

    // MARK: - Status & Badge

    private var statusIndicator: some View {
        Group {
            switch session.status {
            case .streaming:
                Image(systemName: "circlebadge.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(DevysColors.success)
            case .waitingInput:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DevysColors.warning)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(DevysColors.error)
            default:
                EmptyView()
            }
        }
    }

    private var unreadBadge: some View {
        Text("\(session.unreadCount)")
            .font(ChatTokens.captionBold)
            .foregroundStyle(.white)
            .frame(minWidth: ChatTokens.badgeSize, minHeight: ChatTokens.badgeSize)
            .background(ChatTokens.userBubble)
            .clipShape(Capsule())
    }

    private var hasUnread: Bool {
        session.unreadCount > 0
    }

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
