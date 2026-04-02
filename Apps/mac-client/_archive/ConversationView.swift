// ConversationView.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import ChatCore
import ChatUI
import SwiftUI

struct ConversationView: View {
    @Environment(\.devysTheme) private var theme

    let store: AppStore
    let sessionId: String
    let isActive: Bool

    private var sessionTitle: String {
        if let session = store.sessionListStore.sessions.first(where: { $0.id == sessionId }) {
            return session.title
        }
        return "Conversation"
    }

    private var messages: [Message] {
        store.conversationStore.messages
    }

    private var composerBinding: Binding<String> {
        Binding(
            get: { store.composerText },
            set: { store.composerText = $0 }
        )
    }

    private var isAssistantThinking: Bool {
        let state = store.conversationStore.streamState
        guard state == .connecting || state == .streaming else {
            return false
        }
        if state == .connecting {
            return true
        }
        guard let last = store.conversationStore.messages.last else {
            return false
        }
        return last.role == .user || last.streamingState == .streaming
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider().foregroundStyle(theme.border)
            composerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.base)
        .onAppear {
            Task {
                await selectSessionIfNeeded()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                Task {
                    await selectSessionIfNeeded()
                }
            }
        }
        .onChange(of: sessionId) { _, newValue in
            Task {
                await selectSessionIfNeeded(sessionID: newValue)
            }
        }
        .sheet(item: approvalRequestBinding) { request in
            MacApprovalSheet(
                request: request,
                note: binding(\.approvalNote),
                onApprove: {
                    Task { await store.submitApproval(decision: .approve) }
                },
                onDeny: {
                    Task { await store.submitApproval(decision: .deny) }
                }
            )
            .frame(minWidth: 460, minHeight: 260)
        }
        .sheet(item: inputRequestBinding) { request in
            MacInputSheet(
                request: request,
                value: binding(\.inputResponseText)
            ) {
                Task { await store.submitUserInput() }
            }
            .frame(minWidth: 460, minHeight: 260)
        }
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 52))
                            .foregroundStyle(theme.textTertiary.opacity(0.6))
                        Text("No messages yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        Text("Say something to start chatting.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.top, 80)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 0) {
                        let groups = groupMessages(messages)
                        ForEach(Array(groups.enumerated()), id: \.offset) { groupIndex, group in
                            if groupIndex > 0 {
                                timestampSeparator(for: group.first)
                                    .padding(.vertical, 12)
                            }

                            ForEach(Array(group.enumerated()), id: \.element.id) { msgIndex, message in
                                messageBubble(for: message)
                                    .padding(.horizontal, 12)
                                    .padding(
                                        .top,
                                        msgIndex == 0 ? 12 : 4
                                    )
                            }
                        }

                        if isAssistantThinking {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom")
                    }
                    .padding(.vertical, 10)
                }
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isAssistantThinking) { _, thinking in
                if thinking {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageBubble(for message: Message) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 70)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "You" : sessionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                    if let block = message.blocks.first {
                        Text(block.kindLabel)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(
                            message.role == .user ? theme.accent.opacity(0.2) : theme.surface
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                ForEach(message.blocks) { block in
                    messageBlockCard(block)
                }
            }
            if message.role != .user {
                Spacer(minLength: 70)
            }
        }
    }

    private func messageBlockCard(_ block: MessageBlock) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: block.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                Text(block.kindLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
            }

            if let detail = block.summary ?? block.payload?.chatPreviewText, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }
        }
        .padding(8)
        .background(theme.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var composerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField(
                "Message \(sessionTitle)",
                text: composerBinding,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                Task {
                    await store.sendComposerMessage()
                }
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(theme.base)
                    .padding(8)
                    .background(isComposerEnabled ? theme.accent : theme.border)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isComposerEnabled)
        }
        .padding(10)
        .background(theme.surface)
    }

    private var isComposerEnabled: Bool {
        !composerBinding.wrappedValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }

    private var approvalRequestBinding: Binding<AppStore.PendingApprovalRequest?> {
        binding(\.pendingApprovalRequest)
    }

    private var inputRequestBinding: Binding<AppStore.PendingInputRequest?> {
        binding(\.pendingInputRequest)
    }

    private func groupMessages(_ messages: [Message]) -> [[Message]] {
        guard !messages.isEmpty else { return [] }
        var groups: [[Message]] = []
        var currentGroup: [Message] = [messages[0]]

        for index in 1 ..< messages.count {
            let previous = messages[index - 1]
            let current = messages[index]
            let sameRole = previous.role == current.role
            let withinGroupWindow = current.timestamp.timeIntervalSince(previous.timestamp) < 120

            if sameRole && withinGroupWindow {
                currentGroup.append(current)
            } else {
                groups.append(currentGroup)
                currentGroup = [current]
            }
        }

        groups.append(currentGroup)
        return groups
    }

    @ViewBuilder
    private func timestampSeparator(for message: Message?) -> some View {
        if let message {
            Text(Self.timestampFormatter.string(from: message.timestamp))
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("conversation-bottom", anchor: .bottom)
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppStore, Value>) -> Binding<Value> {
        Binding(
            get: { store[keyPath: keyPath] },
            set: { store[keyPath: keyPath] = $0 }
        )
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func selectSessionIfNeeded(sessionID targetSessionID: String? = nil) async {
        let targetSessionID = targetSessionID ?? sessionId
        if store.conversationStore.activeSessionID != targetSessionID {
            await store.selectSession(targetSessionID)
        }
    }
}

private struct MacApprovalSheet: View {
    let request: AppStore.PendingApprovalRequest
    @Binding var note: String
    let onApprove: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Approval Needed")
                .font(.system(size: 16, weight: .semibold))
            Text(request.prompt)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("Optional note", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 6)
            Spacer()
            HStack {
                Spacer()
                Button("Deny", role: .destructive) {
                    onDeny()
                }
                Button("Approve") {
                    onApprove()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

private struct MacInputSheet: View {
    let request: AppStore.PendingInputRequest
    @Binding var value: String
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Input Required")
                .font(.system(size: 16, weight: .semibold))
            Text(request.prompt)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("Response", text: $value, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2 ... 8)
            Spacer()
            HStack {
                Spacer()
                Button("Submit") {
                    onSubmit()
                }
                .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}

private struct TypingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(isAnimating ? 1.25 : 0.75)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.12),
                        value: isAnimating
                    )
            }
        }
        .padding(8)
        .onAppear {
            isAnimating = true
        }
    }
}
