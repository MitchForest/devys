// swiftlint:disable file_length
import AppKit
import AppFeatures
import SwiftUI
import UI
import UniformTypeIdentifiers
import Workspace

// swiftlint:disable:next type_body_length
struct AgentSessionView: View {
    @Environment(\.devysTheme) private var theme
    @State private var isComposerFocused = false
    @State private var isAtBottom = true

    let session: AgentSessionRuntime
    let speechService: any AgentComposerSpeechService
    let onOpenTerminalTab: (UUID) -> Void
    let onOpenLocationTarget: (AgentFollowTarget, Bool) -> Void
    let onOpenDiffArtifact: (AgentDiffContent, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            transcript
            composer
        }
        .background(theme.base)
        .onAppear {
            isComposerFocused = true
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.space4) {
                    if session.timeline.isEmpty {
                        emptyState
                            .padding(.vertical, Spacing.space8)
                    } else {
                        ForEach(session.timeline) { item in
                            timelineRow(item)
                                .id(item.id)
                        }
                    }

                    // Bottom sentinel for scroll-to-latest detection
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomSentinelID)
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.horizontal, Spacing.space4)
                .padding(.vertical, Spacing.space4)
            }
            .background(theme.base)
            .overlay(alignment: .bottom) {
                if !isAtBottom && !session.timeline.isEmpty {
                    jumpToLatest(proxy: proxy)
                        .padding(.bottom, Spacing.space3)
                }
            }
            .onAppear {
                scrollToBottom(using: proxy)
            }
            .onChange(of: session.timeline.last?.id) { _, _ in
                if isAtBottom {
                    scrollToBottom(using: proxy)
                }
            }
        }
    }

    private static let bottomSentinelID = "agent-session-bottom-sentinel"

    private func jumpToLatest(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
            }
        } label: {
            HStack(spacing: Spacing.space1) {
                Image(systemName: "arrow.down")
                    .font(Typography.micro)
                Text("Jump to latest")
                    .font(Typography.label)
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
            .background(theme.overlay, in: DevysShape())
            .overlay(
                DevysShape()
                    .stroke(theme.border, lineWidth: Spacing.borderWidth)
            )
            .shadowStyle(Shadows.md)
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            if !session.attachmentSummaries.isEmpty {
                attachmentStrip
            }

            if let speechMessage = session.speechState.message {
                Text(speechMessage)
                    .font(Typography.caption)
                    .foregroundStyle(session.speechState.isRecording ? theme.accent : theme.textSecondary)
            }

            if let selectedCommand = session.selectedCommand {
                selectedCommandRow(selectedCommand)
            }

            if !slashCommandSuggestions.isEmpty {
                suggestionStrip(for: slashCommandSuggestions)
            }

            if !session.mentionSuggestions.isEmpty {
                mentionStrip(for: session.mentionSuggestions)
            }

            composerInput

            composerToolbar
        }
        .padding(.horizontal, Spacing.space4)
        .padding(.vertical, Spacing.space3)
        .background(theme.base)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.border)
                .frame(height: Spacing.borderWidth)
        }
    }

    private func selectedCommandRow(_ command: AgentAvailableCommand) -> some View {
        HStack(spacing: Spacing.space2) {
            HStack(spacing: Spacing.space1) {
                Image(systemName: "command")
                    .font(Typography.micro)
                Text("/\(command.name)")
                    .font(Typography.label)
                if let hint = command.input?.hint {
                    Text(hint)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .foregroundStyle(theme.text)
            .padding(.horizontal, Spacing.space3)
            .padding(.vertical, Spacing.space2)
            .elevation(.card)

            Button("Clear") {
                session.clearSelectedSlashCommand()
                isComposerFocused = true
            }
            .buttonStyle(.plain)
            .font(Typography.caption)
            .foregroundStyle(theme.textSecondary)

            Spacer()
        }
    }

    private func suggestionStrip(for commands: [AgentAvailableCommand]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.space2) {
                ForEach(commands) { command in
                    Button {
                        session.selectSlashCommand(command)
                        isComposerFocused = true
                    } label: {
                        HStack(spacing: Spacing.space1) {
                            Image(systemName: "slash.circle")
                                .font(Typography.micro)
                                .foregroundStyle(theme.accent)
                            Text(command.name)
                                .font(Typography.label)
                                .foregroundStyle(theme.text)
                            Text(command.description)
                                .font(Typography.caption)
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, Spacing.space3)
                        .padding(.vertical, Spacing.space1)
                        .background(theme.overlay, in: DevysShape())
                        .overlay(
                            DevysShape()
                                .stroke(theme.border, lineWidth: Spacing.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func mentionStrip(for suggestions: [AgentMentionSuggestion]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.space2) {
                ForEach(suggestions) { suggestion in
                    Button {
                        session.insertMention(suggestion)
                        isComposerFocused = true
                    } label: {
                        HStack(spacing: Spacing.space1) {
                            Image(systemName: "at")
                                .font(Typography.micro)
                                .foregroundStyle(theme.accent)
                            Text(suggestion.displayPath)
                                .font(Typography.label)
                                .foregroundStyle(theme.text)
                        }
                        .padding(.horizontal, Spacing.space3)
                        .padding(.vertical, Spacing.space1)
                        .background(theme.overlay, in: DevysShape())
                        .overlay(
                            DevysShape()
                                .stroke(theme.border, lineWidth: Spacing.borderWidth)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var composerInput: some View {
        AgentComposerTextView(
            text: Binding(
                get: { session.draft },
                set: { session.updateDraft($0) }
            ),
            isFocused: $isComposerFocused
        ) {
            session.sendDraft()
            isComposerFocused = true
        }
        .font(Typography.Chat.body)
        .foregroundStyle(theme.text)
        .frame(minHeight: 44, maxHeight: 180)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.card)
        .clipShape(DevysShape())
        .overlay(
            DevysShape()
                .stroke(isComposerFocused ? theme.borderFocus : theme.border, lineWidth: Spacing.borderWidth)
        )
        .shadowStyle(Shadows.sm)
        .overlay(alignment: .topLeading) {
            if let hint = placeholderHint, session.draft.isEmpty {
                Text(hint)
                    .font(Typography.Chat.body)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .allowsHitTesting(false)
            }
        }
        .animation(Animations.micro, value: isComposerFocused)
        .dropDestination(for: URL.self) { items, _ in
            handleDroppedURLs(items)
        }
        .dropDestination(for: GitDiffTransfer.self) { items, _ in
            session.addAttachments(items.map { .gitDiff(path: $0.path, isStaged: $0.isStaged) })
            return true
        }
    }

    private var composerToolbar: some View {
        HStack(spacing: Spacing.space2) {
            IconButton(
                session.speechState.isRecording ? "stop.circle.fill" : "mic.fill",
                style: session.speechState.isRecording ? .primary : .ghost,
                tone: session.speechState.isRecording ? .destructive : .standard,
                size: .md,
                accessibilityLabel: session.speechState.isRecording ? "Stop dictation" : "Start dictation"
            ) {
                if session.speechState.isRecording {
                    session.stopDictation()
                } else {
                    session.startDictation(using: speechService)
                }
                isComposerFocused = true
            }

            ForEach(session.configOptions) { option in
                configMenu(option)
            }

            if session.isSendingPrompt {
                HStack(spacing: Spacing.space1) {
                    ProgressView()
                        .scaleEffect(0.45)
                        .frame(width: 12, height: 12)
                    Text("Running")
                        .font(Typography.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Spacer()

            IconButton(
                session.isSendingPrompt ? "stop.fill" : "arrow.up",
                style: .primary,
                tone: .standard,
                size: .md,
                accessibilityLabel: session.isSendingPrompt ? "Cancel prompt" : "Send message"
            ) {
                if session.isSendingPrompt {
                    session.cancelPrompt()
                } else {
                    session.sendDraft()
                }
                isComposerFocused = true
            }
            .disabled(!session.canSendDraft && !session.isSendingPrompt)
        }
    }

    private func configMenu(_ option: AgentSessionConfigOption) -> some View {
        Menu {
            ForEach(option.groups) { group in
                if let name = group.name {
                    Section(name) {
                        configButtons(for: option, group: group)
                    }
                } else {
                    configButtons(for: option, group: group)
                }
            }
        } label: {
            HStack(spacing: Spacing.space1) {
                Image(systemName: icon(for: option))
                    .font(Typography.micro)
                Text(selectedValueName(for: option))
                    .font(Typography.label)
                Image(systemName: "chevron.down")
                    .font(Typography.micro)
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, 6)
            .background(theme.hover.opacity(0.001), in: DevysShape())
            .contentShape(DevysShape())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .center, spacing: Spacing.space4) {
            Icon("sparkles", size: .custom(28), color: theme.textTertiary)

            VStack(spacing: Spacing.space2) {
                Text(session.descriptor.displayName)
                    .font(Typography.title)
                    .foregroundStyle(theme.text)

                Text(emptyStateMessage)
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            if case .connected = session.launchState {
                quickStartChips
            } else if case .idle = session.launchState {
                quickStartChips
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var quickStartChips: some View {
        HStack(spacing: Spacing.space2) {
            ForEach(quickStartActions, id: \.label) { quickStart in
                Button {
                    session.updateDraft(quickStart.draft)
                    isComposerFocused = true
                } label: {
                    HStack(spacing: Spacing.space1) {
                        Image(systemName: quickStart.icon)
                            .font(Typography.micro)
                            .foregroundStyle(theme.accent)
                        Text(quickStart.label)
                            .font(Typography.label)
                            .foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, Spacing.space3)
                    .padding(.vertical, Spacing.space2)
                    .background(theme.card, in: DevysShape())
                    .overlay(
                        DevysShape()
                            .stroke(theme.border, lineWidth: Spacing.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Spacing.space2)
    }

    private var quickStartActions: [QuickStart] {
        [
            QuickStart(label: "Plan a task", icon: "list.bullet.rectangle", draft: "/plan "),
            QuickStart(label: "Review changes", icon: "eye", draft: "/review "),
            QuickStart(label: "Reference a file", icon: "at", draft: "@")
        ]
    }

    private struct QuickStart {
        let label: String
        let icon: String
        let draft: String
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timelineRow(_ item: AgentTimelineItem) -> some View {
        switch item {
        case .message(let message):
            messageRow(message)
        case .toolCall(let toolCall):
            ToolCallRowView(
                item: toolCall,
                session: session,
                onOpenLocationTarget: onOpenLocationTarget,
                onOpenDiffArtifact: onOpenDiffArtifact,
                onOpenTerminalTab: onOpenTerminalTab
            )
        case .approval(let approval):
            approvalRow(approval)
        case .plan(let plan):
            PlanRowView(item: plan)
        case .status(let status):
            statusRow(status)
        }
    }

    private func messageRow(_ item: AgentMessageTimelineItem) -> some View {
        HStack(alignment: .top, spacing: Spacing.space3) {
            if item.role == .user {
                Spacer(minLength: 64)
            } else {
                AgentIdentityStripe(
                    color: sessionAgentColor,
                    status: stripeStatus(for: item),
                    width: 2
                )
                .frame(minHeight: 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(roleLabel(for: item.role))
                    .font(Typography.Chat.caption)
                    .foregroundStyle(theme.textTertiary)

                Text(item.text)
                    .font(Typography.Chat.body)
                    .foregroundStyle(item.role == .thought ? theme.textSecondary : theme.text)
                    .italic(item.role == .thought)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: item.role == .user ? 640 : .infinity, alignment: .leading)
            .padding(item.role == .user ? EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
                                         : EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
            .background(item.role == .user ? theme.active : Color.clear, in: DevysShape())
            .contextMenu {
                Button("Copy") {
                    copyText(item.text)
                }
                if item.role == .user && session.canRetryLastSubmission && isLastUserMessage(item) {
                    Divider()
                    Button {
                        session.retryLastSubmission()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
            }

            if item.role != .user {
                Spacer(minLength: 0)
            }
        }
    }

    private func approvalRow(_ item: AgentApprovalTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space3) {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(Typography.heading)
                    .foregroundStyle(theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Typography.heading)
                        .foregroundStyle(theme.text)
                    Text(item.toolCallId)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            HStack(spacing: Spacing.space2) {
                ForEach(Array(item.options.enumerated()), id: \.element.id) { index, option in
                    ActionButton(
                        option.name,
                        style: approvalButtonStyle(for: item, option: option, isPrimary: index == 0),
                        tone: approvalButtonTone(for: option)
                    ) {
                        session.respondToApproval(
                            requestID: item.requestID,
                            optionID: option.optionId
                        )
                    }
                    .disabled(item.isResolved)
                }
                Spacer()
            }
        }
        .padding(Spacing.space4)
        .elevation(.popover)
        .contextMenu {
            Button("Copy") {
                copyText(copyText(for: item))
            }
        }
    }

    private func statusRow(_ item: AgentStatusTimelineItem) -> some View {
        HStack {
            Spacer()
            Chip(.status(item.text, statusColor(for: item.style)))
            Spacer()
        }
        .contextMenu {
            Button("Copy") {
                copyText(item.text)
            }
        }
    }

    // MARK: - Attachment strip

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.space2) {
                ForEach(session.attachmentSummaries) { summary in
                    attachmentChip(summary)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func attachmentChip(_ summary: AgentAttachmentSummary) -> some View {
        HStack(spacing: Spacing.space2) {
            Image(systemName: summary.systemImage)
                .font(Typography.caption)
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: 0) {
                Text(summary.title)
                    .font(Typography.label)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let subtitle = summary.subtitle {
                    Text(subtitle)
                        .font(Typography.caption)
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }

            Text(summary.delivery.rawValue.capitalized)
                .font(Typography.micro)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.hover, in: Capsule())

            Button {
                session.removeAttachment(id: summary.id)
            } label: {
                Image(systemName: "xmark")
                    .font(Typography.micro)
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.leading, Spacing.space3)
        .padding(.trailing, Spacing.space1)
        .padding(.vertical, 6)
        .background(theme.card, in: DevysShape())
        .overlay(
            DevysShape()
                .stroke(theme.border, lineWidth: Spacing.borderWidth)
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    fileprivate func configButtons(
        for option: AgentSessionConfigOption,
        group: AgentSessionConfigValueGroup
    ) -> some View {
        ForEach(group.options) { value in
            Button(value.name) {
                session.setConfigOption(id: option.id, value: value.value)
            }
        }
    }

    fileprivate func selectedValueName(for option: AgentSessionConfigOption) -> String {
        option.allValues.first { $0.value == option.currentValue }?.name ?? option.currentValue
    }

    fileprivate var slashCommandSuggestions: [AgentAvailableCommand] {
        guard session.selectedCommand == nil else { return [] }
        let trimmed = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return [] }
        let query = String(trimmed.dropFirst()).lowercased()
        if query.isEmpty {
            return session.availableCommands
        }
        return session.availableCommands.filter { command in
            command.name.lowercased().contains(query) || command.description.lowercased().contains(query)
        }
    }

    fileprivate var placeholderHint: String? {
        if let commandHint = session.commandInputHint {
            return commandHint
        }
        switch session.launchState {
        case .launching:
            return "Connecting…"
        case .failed:
            return nil
        case .idle, .connected:
            return "Message \(session.descriptor.displayName)… (⇧⏎ for newline)"
        }
    }

    fileprivate var emptyStateMessage: String {
        switch session.launchState {
        case .launching:
            "Restoring the prior session and replaying agent state."
        case .failed(let message):
            message
        case .idle, .connected:
            "Send a prompt, reference files with @, or start with a slash command."
        }
    }

    fileprivate func scrollToBottom(using proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(Self.bottomSentinelID, anchor: .bottom)
        }
    }

    fileprivate var sessionAgentColor: AgentColor {
        let index = abs(session.descriptor.kind.rawValue.hashValue) % AgentColor.palette.count
        return AgentColor.palette[index]
    }

    fileprivate func stripeStatus(for item: AgentMessageTimelineItem) -> AgentStatus {
        guard isLastAssistantMessage(item) else { return .complete }
        if session.isSendingPrompt { return .running }
        if case .failed = session.launchState { return .error }
        return .complete
    }

    fileprivate func roleLabel(for role: AgentMessageRole) -> String {
        switch role {
        case .user:
            "You"
        case .assistant:
            session.descriptor.displayName
        case .thought:
            "Reasoning"
        }
    }

    fileprivate func icon(for option: AgentSessionConfigOption) -> String {
        switch option.category {
        case "mode":
            "slider.horizontal.3"
        case "model":
            "cpu"
        case "thought_level":
            "brain"
        default:
            "dial.low"
        }
    }

    fileprivate func approvalButtonStyle(
        for item: AgentApprovalTimelineItem,
        option: AgentPermissionOption,
        isPrimary: Bool
    ) -> ActionButton.Style {
        if item.selectedOptionID == option.optionId {
            return .primary
        }
        return isPrimary ? .primary : .ghost
    }

    fileprivate func approvalButtonTone(for option: AgentPermissionOption) -> ActionButton.Tone {
        let lowered = option.name.lowercased()
        if lowered.contains("reject") || lowered.contains("deny") || lowered.contains("cancel") {
            return .destructive
        }
        return .standard
    }

    fileprivate func statusColor(for style: AgentStatusStyle) -> Color {
        switch style {
        case .neutral:
            theme.textSecondary
        case .warning:
            theme.warning
        case .error:
            theme.error
        }
    }

    fileprivate func isLastUserMessage(_ item: AgentMessageTimelineItem) -> Bool {
        guard let lastUserItem = session.timeline.last(where: {
            if case .message(let msg) = $0, msg.role == .user { return true }
            return false
        }),
        case .message(let msg) = lastUserItem else {
            return false
        }
        return msg.id == item.id
    }

    fileprivate func isLastAssistantMessage(_ item: AgentMessageTimelineItem) -> Bool {
        guard let lastAssistantItem = session.timeline.last(where: {
            if case .message(let msg) = $0, msg.role != .user { return true }
            return false
        }),
        case .message(let msg) = lastAssistantItem else {
            return false
        }
        return msg.id == item.id
    }

    fileprivate func handleDroppedURLs(_ items: [URL]) -> Bool {
        guard !items.isEmpty else { return false }
        session.addAttachments(items.map(attachment(from:)))
        return true
    }

    fileprivate func attachment(from url: URL) -> AgentAttachment {
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        if let mimeType,
           let type = UTType(mimeType: mimeType),
           type.conforms(to: .image) {
            return .image(url: url)
        }
        return .file(url: url)
    }

    fileprivate func copyText(for item: AgentApprovalTimelineItem) -> String {
        [
            item.title,
            item.toolCallId,
            item.options.map(\.name).joined(separator: ", ")
        ]
        .joined(separator: "\n")
    }

    fileprivate func copyText(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - Tool Call Row

@MainActor
private struct ToolCallRowView: View {
    @Environment(\.devysTheme) private var theme
    @State private var isExpanded = true

    let item: AgentToolCallTimelineItem
    let session: AgentSessionRuntime
    let onOpenLocationTarget: (AgentFollowTarget, Bool) -> Void
    let onOpenDiffArtifact: (AgentDiffContent, Bool) -> Void
    let onOpenTerminalTab: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? Spacing.space3 : 0) {
            header

            if isExpanded {
                if !item.locations.isEmpty {
                    locationsStrip
                }

                ForEach(item.content) { content in
                    contentView(for: content)
                }
            }
        }
        .padding(Spacing.space3)
        .elevation(.card)
        .contextMenu {
            Button("Copy") {
                copy(copyText(for: item))
            }
            if let location = item.locations.first {
                Button("Reveal File") {
                    onOpenLocationTarget(
                        AgentFollowTarget(
                            location: location,
                            diff: preferredDiff(for: item, location: location)
                        ),
                        false
                    )
                }
            }
            if let diff = item.content.compactMap(\.diff).first {
                Button("Open Diff") {
                    onOpenDiffArtifact(diff, false)
                }
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(Animations.micro) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "chevron.right")
                    .font(Typography.micro)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 10)

                Image(systemName: icon(forToolKind: item.kind))
                    .font(Typography.caption)
                    .foregroundStyle(theme.accent)

                Text(item.title)
                    .font(Typography.label)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)

                if let status = item.status {
                    Chip(.status(
                        status.replacingOccurrences(of: "_", with: " "),
                        statusColorForToolStatus(status)
                    ))
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var locationsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.space2) {
                ForEach(item.locations, id: \.self) { location in
                    Button {
                        onOpenLocationTarget(
                            AgentFollowTarget(
                                location: location,
                                diff: preferredDiff(for: item, location: location)
                            ),
                            false
                        )
                    } label: {
                        HStack(spacing: Spacing.space1) {
                            Image(systemName: "doc.text")
                                .font(Typography.micro)
                            Text(location.line.map { "\(location.path):\($0)" } ?? location.path)
                                .font(Typography.caption)
                                .lineLimit(1)
                        }
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, Spacing.space2)
                        .padding(.vertical, 3)
                        .background(theme.hover, in: DevysShape())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func contentView(for content: AgentToolContentPreview) -> some View {
        switch content.kind {
        case .diff:
            if let diff = content.diff {
                diffContent(diff)
            }
        case .terminal:
            if let terminalID = content.terminalID,
               let terminal = session.inlineTerminal(id: terminalID) {
                TerminalInlineView(
                    terminal: terminal,
                    session: session,
                    onOpenTerminalTab: onOpenTerminalTab
                )
            } else {
                Text(content.summary)
                    .font(Typography.body)
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
            }
        default:
            Text(content.summary)
                .font(Typography.body)
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
        }
    }

    private func diffContent(_ diff: AgentDiffContent) -> some View {
        VStack(alignment: .leading, spacing: Spacing.space1) {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "doc.text.below.ecg")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textSecondary)
                Text(diff.path)
                    .font(Typography.Code.sm)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open Diff") {
                    onOpenDiffArtifact(diff, false)
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(theme.accent)
            }
            .padding(.horizontal, Spacing.space2)
            .padding(.vertical, 4)
            .background(theme.hover, in: DevysShape())

            if let oldText = diff.oldText {
                diffBlock(oldText, kind: .removed)
            }
            diffBlock(diff.newText, kind: .added)
        }
    }

    private enum DiffKind { case added, removed }

    private func diffBlock(_ text: String, kind: DiffKind) -> some View {
        Text(text)
            .font(Typography.Code.sm)
            .foregroundStyle(theme.text)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.space2)
            .background(kind == .added ? theme.successSubtle : theme.errorSubtle, in: DevysShape())
            .overlay(
                DevysShape()
                    .stroke(
                        (kind == .added ? theme.success : theme.error).opacity(0.3),
                        lineWidth: Spacing.borderWidth
                    )
            )
    }

    // Helpers

    private func statusColorForToolStatus(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed", "complete", "success":
            theme.success
        case "failed", "error":
            theme.error
        case "running", "in_progress":
            theme.accent
        default:
            theme.textSecondary
        }
    }

    private func icon(forToolKind kind: String?) -> String {
        switch kind {
        case "read":
            "doc.text.magnifyingglass"
        case "edit":
            "pencil.line"
        case "execute":
            "terminal"
        case "search":
            "magnifyingglass"
        case "think":
            "brain"
        case "fetch":
            "globe"
        default:
            "gearshape.2"
        }
    }

    private func preferredDiff(
        for item: AgentToolCallTimelineItem,
        location: AgentToolCallLocation
    ) -> AgentDiffContent? {
        item.content.first { $0.diff?.path == location.path }?.diff
            ?? item.content.compactMap(\.diff).first
    }

    private func copyText(for item: AgentToolCallTimelineItem) -> String {
        var components = [item.title]
        if let status = item.status {
            components.append("Status: \(status)")
        }
        if !item.locations.isEmpty {
            components.append(
                "Locations: " + item.locations.map { location in
                    location.line.map { "\(location.path):\($0)" } ?? location.path
                }.joined(separator: ", ")
            )
        }
        let summaries = item.content.map(\.summary).filter { !$0.isEmpty }
        if !summaries.isEmpty {
            components.append(summaries.joined(separator: "\n"))
        }
        return components.joined(separator: "\n")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - Plan Row

@MainActor
private struct PlanRowView: View {
    @Environment(\.devysTheme) private var theme
    @State private var isExpanded = true

    let item: AgentPlanTimelineItem

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? Spacing.space2 : 0) {
            Button {
                withAnimation(Animations.micro) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.space2) {
                    Image(systemName: "chevron.right")
                        .font(Typography.micro)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 10)

                    Image(systemName: "list.bullet.rectangle")
                        .font(Typography.caption)
                        .foregroundStyle(theme.accent)

                    Text("Plan")
                        .font(Typography.label)
                        .foregroundStyle(theme.text)

                    Chip(.count(item.entries.count))

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(Array(item.entries.enumerated()), id: \.offset) { index, entry in
                    HStack(alignment: .top, spacing: Spacing.space2) {
                        Text("\(index + 1).")
                            .font(Typography.body)
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 20, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.content)
                                .font(Typography.body)
                                .foregroundStyle(theme.text)
                            HStack(spacing: Spacing.space1) {
                                Chip(.status(entry.status, planStatusColor(entry.status)))
                                Chip(.tag(entry.priority))
                            }
                        }
                        Spacer()
                    }
                    .padding(.leading, Spacing.space2)
                }
            }
        }
        .padding(Spacing.space3)
        .elevation(.card)
        .contextMenu {
            Button("Copy") {
                copy(copyText(for: item))
            }
        }
    }

    private func planStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed", "done":
            theme.success
        case "in_progress", "active":
            theme.accent
        case "blocked", "failed":
            theme.error
        default:
            theme.textSecondary
        }
    }

    private func copyText(for item: AgentPlanTimelineItem) -> String {
        item.entries.enumerated().map { index, entry in
            "\(index + 1). \(entry.content) [\(entry.status) • \(entry.priority)]"
        }
        .joined(separator: "\n")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

// MARK: - Inline Terminal

@MainActor
private struct TerminalInlineView: View {
    @Environment(\.devysTheme) private var theme

    let terminal: AgentInlineTerminalViewState
    let session: AgentSessionRuntime
    let onOpenTerminalTab: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.space2) {
            HStack(spacing: Spacing.space2) {
                Image(systemName: "terminal")
                    .font(Typography.caption)
                    .foregroundStyle(theme.accent)
                Text(terminal.command)
                    .font(Typography.Code.sm)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer()
                statusChip
                Button("Open Terminal") {
                    Task {
                        do {
                            let terminalTabID = try await session.promoteInlineTerminal(terminal.terminalID)
                            onOpenTerminalTab(terminalTabID)
                        } catch {
                            session.noteStatus(error.localizedDescription, style: .error)
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(theme.accent)
                .disabled(!terminal.isRunning)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(terminal.output.isEmpty ? "Waiting for output…" : terminal.output)
                    .font(Typography.Code.gutter)
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.space2)
            }
            .frame(minHeight: 84, maxHeight: 180)
            .background(theme.base)
            .clipShape(DevysShape())
            .overlay(
                DevysShape()
                    .stroke(theme.border, lineWidth: Spacing.borderWidth)
            )

            if terminal.truncated {
                Text("Output truncated to the retained byte limit.")
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        if terminal.isRunning {
            Chip(.status("Running", theme.accent))
        } else if let exitCode = terminal.exitCode {
            Chip(.status("Exit \(exitCode)", exitCode == 0 ? theme.success : theme.error))
        } else if let signal = terminal.signal {
            Chip(.status("Signal \(signal)", theme.warning))
        }
    }
}

// MARK: - Composer Text View

@MainActor
private struct AgentComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay

        let textView = context.coordinator.textView
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let textView = context.coordinator.textView

        if textView.string != text {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let updatedLength = (textView.string as NSString).length
            textView.setSelectedRange(
                NSRange(location: min(selectedRange.location, updatedLength), length: 0)
            )
        }

        if isFocused,
           let window = scrollView.window,
           window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AgentComposerTextView
        let textView: AgentComposerNSTextView

        init(_ parent: AgentComposerTextView) {
            self.parent = parent
            self.textView = AgentComposerNSTextView()
            super.init()

            textView.delegate = self
            textView.isRichText = false
            textView.importsGraphics = false
            textView.usesFindBar = true
            textView.allowsUndo = true
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: 15, weight: .regular)
            textView.textContainerInset = NSSize(width: 0, height: 2)
            textView.textContainer?.lineFragmentPadding = 0
            textView.textContainer?.widthTracksTextView = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.minSize = .zero
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.insertionPointColor = .labelColor
            textView.focusDidChange = { [weak self] isFocused in
                self?.parent.isFocused = isFocused
            }
        }

        func textDidChange(_ notification: Notification) {
            parent.text = textView.string
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            let newlineSelectors: Set<Selector> = [
                #selector(NSResponder.insertNewline(_:)),
                #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            ]
            guard newlineSelectors.contains(commandSelector) else {
                return false
            }

            let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.shift, .control, .option, .command]) ?? []
            guard modifiers.isEmpty else {
                return false
            }

            parent.onSubmit()
            parent.isFocused = true
            return true
        }
    }
}

@MainActor
private final class AgentComposerNSTextView: NSTextView {
    var focusDidChange: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            focusDidChange?(true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            focusDidChange?(false)
        }
        return didResignFirstResponder
    }
}
