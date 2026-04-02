import ChatUI
import SwiftUI
import UI

// MARK: - Bubble Position

enum BubblePosition {
    case alone, first, middle, last
}
// MARK: - Message Bubble

struct IOSMessageBubbleView: View {
    @Environment(\.devysTheme) private var theme
    let message: Message
    let position: BubblePosition
    let isDark: Bool

    var body: some View {
        if message.role == .system {
            systemMessage
        } else {
            chatBubble
        }
    }

    // MARK: - System Message (Centered Pill)

    private var systemMessage: some View {
        HStack {
            Spacer()
            Text(message.text.isEmpty ? "System" : message.text)
                .font(ChatTokens.caption)
                .foregroundStyle(ChatTokens.systemPillText)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(ChatTokens.systemPill)
                .clipShape(Capsule())
            Spacer()
        }
    }

    // MARK: - Chat Bubble

    private var chatBubble: some View {
        let isUser = message.role == .user

        return HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(ChatTokens.body)
                        .foregroundStyle(isUser ? ChatTokens.userBubbleText : theme.text)
                        .textSelection(.enabled)
                }

                if !message.blocks.isEmpty {
                    ForEach(message.blocks) { block in
                        IOSMessageBlockCard(block: block, isUser: isUser)
                    }
                }
            }
            .padding(.horizontal, ChatTokens.bubblePaddingH)
            .padding(.vertical, ChatTokens.bubblePaddingV)
            .background(bubbleColor)
            .clipShape(makeBubbleShape())

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private var bubbleColor: Color {
        message.role == .user
            ? ChatTokens.userBubble
            : (isDark ? ChatTokens.assistantBubbleDark : ChatTokens.assistantBubbleLight)
    }

    /// iMessage-style bubble corners: tight radius on the grouped side
    private func makeBubbleShape() -> UnevenRoundedRectangle {
        let isUser = message.role == .user
        let full = ChatTokens.bubbleRadius
        let tight = ChatTokens.bubbleRadiusSm

        switch position {
        case .alone:
            return UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: full,
                bottomTrailingRadius: full,
                topTrailingRadius: full
            )
        case .first:
            return UnevenRoundedRectangle(
                topLeadingRadius: full,
                bottomLeadingRadius: isUser ? full : tight,
                bottomTrailingRadius: isUser ? tight : full,
                topTrailingRadius: full
            )
        case .middle:
            return UnevenRoundedRectangle(
                topLeadingRadius: isUser ? full : tight,
                bottomLeadingRadius: isUser ? full : tight,
                bottomTrailingRadius: isUser ? tight : full,
                topTrailingRadius: isUser ? tight : full
            )
        case .last:
            return UnevenRoundedRectangle(
                topLeadingRadius: isUser ? full : tight,
                bottomLeadingRadius: full,
                bottomTrailingRadius: full,
                topTrailingRadius: isUser ? tight : full
            )
        }
    }
}

// MARK: - Message Block Card

struct IOSMessageBlockCard: View {
    @Environment(\.devysTheme) private var theme
    let block: MessageBlock
    let isUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: blockIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(iconColor)

                Text(blockLabel)
                    .font(ChatTokens.codeSm)
                    .foregroundStyle(iconColor)
            }

            if let summary = block.summary, !summary.isEmpty {
                Text(summary)
                    .font(ChatTokens.caption)
                    .foregroundStyle(summaryColor)
                    .lineLimit(4)
            }

            if let payloadText = block.payload?.chatPreviewText {
                Text(payloadText)
                    .font(ChatTokens.codeSm)
                    .foregroundStyle(iconColor)
                    .lineLimit(6)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUser ? Color.white.opacity(0.12) : theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var iconColor: Color {
        isUser ? ChatTokens.userBubbleText.opacity(0.7) : theme.textTertiary
    }

    private var summaryColor: Color {
        isUser ? ChatTokens.userBubbleText.opacity(0.85) : theme.textSecondary
    }

    private var blockIcon: String {
        switch block.kind {
        case .toolCall: return "wrench.fill"
        case .patch, .diff: return "doc.badge.plus"
        case .hunkList: return "text.badge.plus"
        case .plan: return "list.bullet.clipboard"
        case .todoList: return "checklist"
        case .userInputRequest: return "questionmark.circle.fill"
        case .reasoning: return "brain"
        case .systemStatus: return "info.circle.fill"
        case .fileSnippet: return "doc.text"
        case .gitCommitSummary: return "arrow.triangle.branch"
        case .pullRequestSummary: return "arrow.triangle.pull"
        }
    }

    private var blockLabel: String {
        switch block.kind {
        case .toolCall: return "Tool Call"
        case .patch: return "Patch"
        case .diff: return "Diff"
        case .hunkList: return "Changes"
        case .plan: return "Plan"
        case .todoList: return "Tasks"
        case .userInputRequest: return "Input Required"
        case .reasoning: return "Thinking"
        case .systemStatus: return "Status"
        case .fileSnippet: return "File"
        case .gitCommitSummary: return "Commit"
        case .pullRequestSummary: return "Pull Request"
        }
    }
}

// MARK: - Typing Indicator

struct IOSTypingIndicatorView: View {
    @Environment(\.devysTheme) private var theme
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack {
            HStack(spacing: ChatTokens.typingDotSpacing) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .fill(theme.textTertiary)
                        .frame(
                            width: ChatTokens.typingDotSize,
                            height: ChatTokens.typingDotSize
                        )
                        .offset(y: dotOffset(for: index))
                }
            }
            .padding(.horizontal, ChatTokens.bubblePaddingH)
            .padding(.vertical, ChatTokens.bubblePaddingV + 2)
            .background(typingBackground)
            .clipShape(RoundedRectangle(cornerRadius: ChatTokens.bubbleRadius))

            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
            ) {
                phase = 1
            }
        }
    }

    private var typingBackground: Color {
        theme.isDark ? ChatTokens.assistantBubbleDark : ChatTokens.assistantBubbleLight
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let delay = Double(index) * 0.15
        let progress = max(0, min(1, phase - delay))
        return -4 * sin(progress * .pi)
    }
}
