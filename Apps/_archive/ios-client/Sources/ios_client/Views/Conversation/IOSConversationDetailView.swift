import ChatUI
import SwiftUI
import UI

struct IOSConversationDetailView: View {
    @Environment(\.devysTheme) private var theme
    let store: AppStore
    @State private var sttTapped = false

    var body: some View {
        Group {
            if store.conversationStore.activeSessionID != nil {
                conversationContent
            } else {
                emptyState
            }
        }
        .alert("Speech to Text", isPresented: $sttTapped) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Voice input is coming soon.")
        }
        .sheet(item: approvalRequestBinding) { request in
            IOSApprovalSheet(
                request: request,
                note: binding(\.approvalNote),
                onApprove: {
                    Task { await store.submitApproval(decision: .approve) }
                },
                onDeny: {
                    Task { await store.submitApproval(decision: .deny) }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(item: inputRequestBinding) { request in
            IOSInputSheet(
                request: request,
                value: binding(\.inputResponseText)
            ) {
                Task { await store.submitUserInput() }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Conversation Content

    private var conversationContent: some View {
        VStack(spacing: 0) {
            messageList
            composerBar
        }
        .navigationTitle(currentSessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(theme.base)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    let groups = groupMessages(
                        store.conversationStore.messages
                    )
                    ForEach(
                        Array(groups.enumerated()),
                        id: \.offset
                    ) { groupIndex, group in
                        if groupIndex > 0 {
                            timestampSeparator(for: group.first)
                                .padding(.vertical, 12)
                        }

                        ForEach(
                            Array(group.enumerated()),
                            id: \.element.id
                        ) { msgIndex, message in
                            IOSMessageBubbleView(
                                message: message,
                                position: bubblePosition(
                                    index: msgIndex,
                                    total: group.count
                                ),
                                isDark: theme.isDark
                            )
                            .id(message.id)
                            .padding(.horizontal, 12)
                            .padding(
                                .top,
                                msgIndex == 0
                                    ? ChatTokens.groupBreakSpacing
                                    : ChatTokens.groupedSpacing
                            )
                        }
                    }

                    if isAssistantThinking {
                        IOSTypingIndicatorView()
                            .padding(.horizontal, 12)
                            .padding(.top, ChatTokens.groupBreakSpacing)
                            .id("typing-indicator")
                    }

                    Color.clear.frame(height: 1).id("bottom-anchor")
                }
                .padding(.vertical, 12)
            }
            .background(theme.base)
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.conversationStore.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isAssistantThinking) { _, thinking in
                if thinking { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(DevysAnimation.smoothSpring) {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }

    // MARK: - Composer

    private var composerBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(theme.borderSubtle)

            HStack(alignment: .bottom, spacing: 8) {
                if composerTextTrimmed.isEmpty {
                    micButton
                        .transition(.scale.combined(with: .opacity))
                }

                textField

                if !composerTextTrimmed.isEmpty {
                    sendButton
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.surface)
            .animation(DevysAnimation.fast, value: composerTextTrimmed.isEmpty)
        }
    }

    private var micButton: some View {
        Button {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            sttTapped = true
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 18))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 36, height: 36)
        }
    }

    private var textField: some View {
        TextField("Message", text: binding(\.composerText), axis: .vertical)
            .font(ChatTokens.body)
            .lineLimit(1 ... 8)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.elevated)
            .clipShape(
                RoundedRectangle(cornerRadius: ChatTokens.composerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ChatTokens.composerRadius)
                    .stroke(theme.borderSubtle, lineWidth: 0.5)
            )
    }

    private var sendButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            Task { await store.sendComposerMessage() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: ChatTokens.sendButtonSize))
                .foregroundStyle(ChatTokens.userBubble)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(theme.textTertiary.opacity(0.5))
            Text("Select a Conversation")
                .font(ChatTokens.title)
                .foregroundStyle(theme.text)
            Text("Pick a session or create a new one.")
                .font(ChatTokens.secondary)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
    }

    // MARK: - Helpers

    private var currentSessionTitle: String {
        guard let sid = store.conversationStore.activeSessionID else {
            return "Conversation"
        }
        let match = store.sessionListStore.sessions.first {
            $0.id == sid
        }
        return match?.title ?? "Conversation"
    }

    private var isAssistantThinking: Bool {
        let state = store.conversationStore.streamState
        guard state == .connecting || state == .streaming else {
            return false
        }
        if state == .connecting { return true }
        guard let last = store.conversationStore.messages.last else {
            return false
        }
        return last.role == .user || last.streamingState == .streaming
    }

    private var composerTextTrimmed: String {
        store.composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    }


    private var approvalRequestBinding: Binding<AppStore.PendingApprovalRequest?> {
        binding(\.pendingApprovalRequest)
    }

    private var inputRequestBinding: Binding<AppStore.PendingInputRequest?> {
        binding(\.pendingInputRequest)
    }

    private func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<AppStore, Value>
    ) -> Binding<Value> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: { store[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Message Grouping

    private func groupMessages(
        _ messages: [Message]
    ) -> [[Message]] {
        guard !messages.isEmpty else { return [] }
        var groups: [[Message]] = []
        var current: [Message] = [messages[0]]

        for idx in 1 ..< messages.count {
            let prev = messages[idx - 1]
            let msg = messages[idx]
            let sameRole = msg.role == prev.role
            let close = msg.timestamp.timeIntervalSince(prev.timestamp) < 120

            if sameRole && close {
                current.append(msg)
            } else {
                groups.append(current)
                current = [msg]
            }
        }
        groups.append(current)
        return groups
    }

    private func bubblePosition(
        index: Int,
        total: Int
    ) -> BubblePosition {
        if total == 1 { return .alone }
        if index == 0 { return .first }
        if index == total - 1 { return .last }
        return .middle
    }

    private func timestampSeparator(
        for message: Message?
    ) -> some View {
        Group {
            if let message {
                Text(
                    Self.timestampFormatter.string(from: message.timestamp)
                )
                .font(ChatTokens.micro)
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.doesRelativeDateFormatting = true
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt
    }()
}
