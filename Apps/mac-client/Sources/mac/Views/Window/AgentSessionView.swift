// swiftlint:disable file_length
import AppKit
import SwiftUI
import UI
import UniformTypeIdentifiers
import Workspace

// swiftlint:disable:next type_body_length
struct AgentSessionView: View {
    @Environment(\.devysTheme) private var theme
    @State private var isComposerFocused = false

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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DevysSpacing.space3) {
                    if session.timeline.isEmpty {
                        emptyState
                    } else {
                        ForEach(session.timeline) { item in
                            timelineRow(item)
                                .id(item.id)
                        }
                    }
                }
                .padding(DevysSpacing.space4)
            }
            .background(theme.base)
            .onAppear {
                scrollToBottom(using: proxy)
            }
            .onChange(of: session.timeline.last?.id) { _, _ in
                scrollToBottom(using: proxy)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space3) {
            if !session.attachmentSummaries.isEmpty {
                attachmentStrip
            }

            if let speechMessage = session.speechState.message {
                Text(speechMessage)
                    .font(DevysTypography.sm)
                    .foregroundStyle(session.speechState.isRecording ? theme.accent : theme.textSecondary)
            }

            if let selectedCommand = session.selectedCommand {
                HStack(spacing: DevysSpacing.space2) {
                    HStack(spacing: 6) {
                        Image(systemName: "command")
                            .font(.system(size: 10, weight: .semibold))
                        Text("/\(selectedCommand.name)")
                            .font(DevysTypography.sm)
                        if let hint = selectedCommand.input?.hint {
                            Text(hint)
                                .font(DevysTypography.xs)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("Clear") {
                        session.clearSelectedSlashCommand()
                        isComposerFocused = true
                    }
                    .buttonStyle(.plain)
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
                }
            }

            if !slashCommandSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DevysSpacing.space2) {
                        ForEach(slashCommandSuggestions) { command in
                            Button {
                                session.selectSlashCommand(command)
                                isComposerFocused = true
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("/\(command.name)")
                                        .font(DevysTypography.sm)
                                        .foregroundStyle(theme.text)
                                    Text(command.description)
                                        .font(DevysTypography.xs)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(theme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.border, lineWidth: 1)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if !session.mentionSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DevysSpacing.space2) {
                        ForEach(session.mentionSuggestions) { suggestion in
                            Button {
                                session.insertMention(suggestion)
                                isComposerFocused = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "at")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(suggestion.displayPath)
                                        .font(DevysTypography.sm)
                                }
                                .foregroundStyle(theme.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(theme.surface)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(theme.border, lineWidth: 1)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: DevysSpacing.space3) {
                composerInput

                VStack(spacing: DevysSpacing.space2) {
                    Button {
                        if session.speechState.isRecording {
                            session.stopDictation()
                        } else {
                            session.startDictation(using: speechService)
                        }
                        isComposerFocused = true
                    } label: {
                        Image(systemName: session.speechState.isRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(session.speechState.isRecording ? theme.accentForeground : theme.text)
                            .background(session.speechState.isRecording ? theme.accent : theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if session.isSendingPrompt {
                            session.cancelPrompt()
                        } else {
                            session.sendDraft()
                        }
                        isComposerFocused = true
                    } label: {
                        Image(systemName: session.isSendingPrompt ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(
                                session.canSendDraft || session.isSendingPrompt
                                    ? theme.accentForeground
                                    : Color.white
                            )
                            .background(
                                session.canSendDraft || session.isSendingPrompt
                                    ? theme.accent
                                    : theme.textTertiary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canSendDraft && !session.isSendingPrompt)
                }
            }

            if session.isSendingPrompt || !session.configOptions.isEmpty {
                composerConfigRow
            }
        }
        .padding(DevysSpacing.space4)
        .background(theme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
        }
    }

    private var composerConfigRow: some View {
        HStack(spacing: DevysSpacing.space3) {
            if session.isSendingPrompt {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Running")
                        .font(DevysTypography.xs)
                        .foregroundStyle(theme.textSecondary)
                }
            }

            ForEach(session.configOptions) { option in
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
                    HStack(spacing: 4) {
                        Image(systemName: icon(for: option))
                            .font(.system(size: 9, weight: .semibold))
                        Text(selectedValueName(for: option))
                            .font(DevysTypography.xs)
                    }
                    .foregroundStyle(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space3) {
            Text("Agents")
                .font(DevysTypography.lg)
                .foregroundStyle(theme.text)

            Text(emptyStateMessage)
                .font(DevysTypography.base)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DevysSpacing.space4)
        .background(theme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.borderSubtle, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func timelineRow(_ item: AgentTimelineItem) -> some View {
        switch item {
        case .message(let message):
            messageRow(message)
        case .toolCall(let toolCall):
            toolCallRow(toolCall)
        case .approval(let approval):
            approvalRow(approval)
        case .plan(let plan):
            planRow(plan)
        case .status(let status):
            statusRow(status)
        }
    }

    private func messageRow(_ item: AgentMessageTimelineItem) -> some View {
        HStack {
            if item.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(roleLabel(for: item.role))
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)

                Text(item.text)
                    .font(DevysTypography.base)
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(12)
            .background(messageBackground(for: item.role))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                Spacer(minLength: 80)
            }
        }
    }

    // swiftlint:disable:next function_body_length
    private func toolCallRow(_ item: AgentToolCallTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space3) {
            HStack(spacing: DevysSpacing.space2) {
                Image(systemName: icon(forToolKind: item.kind))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent)

                Text(item.title)
                    .font(DevysTypography.base)
                    .foregroundStyle(theme.text)

                if let status = item.status {
                    pill(status.replacingOccurrences(of: "_", with: " "), tint: theme.active)
                }

                Spacer()
            }

            if !item.locations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DevysSpacing.space2) {
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
                                pill(
                                    location.line.map { "\(location.path):\($0)" } ?? location.path,
                                    tint: theme.surface
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            ForEach(item.content) { content in
                switch content.kind {
                case .diff:
                    if let diff = content.diff {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: DevysSpacing.space2) {
                                Text(diff.path)
                                    .font(DevysTypography.sm)
                                    .foregroundStyle(theme.text)
                                Spacer()
                                Button("Open Diff") {
                                    onOpenDiffArtifact(diff, false)
                                }
                                .buttonStyle(.plain)
                                .font(DevysTypography.xs)
                                .foregroundStyle(theme.accent)
                            }
                            if let oldText = diff.oldText {
                                diffBlock(oldText, tint: Color.red.opacity(0.12))
                            }
                            diffBlock(diff.newText, tint: Color.green.opacity(0.12))
                        }
                    }
                case .terminal:
                    if let terminalID = content.terminalID,
                       let terminal = session.inlineTerminal(id: terminalID) {
                        terminalRow(terminal)
                    } else {
                        Text(content.summary)
                            .font(DevysTypography.sm)
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                    }
                default:
                    Text(content.summary)
                        .font(DevysTypography.sm)
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(DevysSpacing.space3)
        .background(theme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Copy") {
                copyText(copyText(for: item))
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

    private func approvalRow(_ item: AgentApprovalTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space3) {
            Text(item.title)
                .font(DevysTypography.base)
                .foregroundStyle(theme.text)

            Text(item.toolCallId)
                .font(DevysTypography.xs)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: DevysSpacing.space2) {
                ForEach(item.options) { option in
                    Button(option.name) {
                        session.respondToApproval(
                            requestID: item.requestID,
                            optionID: option.optionId
                        )
                    }
                    .buttonStyle(.plain)
                    .font(DevysTypography.sm)
                    .foregroundStyle(buttonTextColor(for: item, option: option))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(buttonBackground(for: item, option: option))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .disabled(item.isResolved)
                }
            }
        }
        .padding(DevysSpacing.space3)
        .background(theme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Copy") {
                copyText(copyText(for: item))
            }
        }
    }

    private func planRow(_ item: AgentPlanTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            Text("Plan")
                .font(DevysTypography.base)
                .foregroundStyle(theme.text)

            ForEach(Array(item.entries.enumerated()), id: \.offset) { index, entry in
                HStack(alignment: .top, spacing: DevysSpacing.space2) {
                    Text("\(index + 1).")
                        .font(DevysTypography.sm)
                        .foregroundStyle(theme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.content)
                            .font(DevysTypography.sm)
                            .foregroundStyle(theme.text)
                        Text("\(entry.status) • \(entry.priority)")
                            .font(DevysTypography.xs)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
        .padding(DevysSpacing.space3)
        .background(theme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.borderSubtle, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu {
            Button("Copy") {
                copyText(copyText(for: item))
            }
        }
    }

    private func statusRow(_ item: AgentStatusTimelineItem) -> some View {
        HStack {
            Spacer()
            Text(item.text)
                .font(DevysTypography.sm)
                .foregroundStyle(statusColor(for: item.style))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.surface)
                .overlay {
                    Capsule()
                        .stroke(theme.borderSubtle, lineWidth: 1)
                }
            Spacer()
        }
        .contextMenu {
            Button("Copy") {
                copyText(item.text)
            }
        }
    }

    @ViewBuilder
    private func configButtons(
        for option: AgentSessionConfigOption,
        group: AgentSessionConfigValueGroup
    ) -> some View {
        ForEach(group.options) { value in
            Button(value.name) {
                session.setConfigOption(id: option.id, value: value.value)
            }
        }
    }

    private func selectedValueName(for option: AgentSessionConfigOption) -> String {
        option.allValues.first { $0.value == option.currentValue }?.name ?? option.currentValue
    }

    private var slashCommandSuggestions: [AgentAvailableCommand] {
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

    private var emptyStateMessage: String {
        switch session.launchState {
        case .launching:
            "Restoring the prior session and replaying agent state."
        case .failed(let message):
            message
        case .idle, .connected:
            "Send a prompt, adjust the active model or mode, and follow tool activity inline."
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        guard let lastID = session.timeline.last?.id else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            proxy.scrollTo(lastID, anchor: .bottom)
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
        .font(DevysTypography.base)
        .foregroundStyle(theme.text)
        .frame(minHeight: 92, maxHeight: 160)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.content)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.border, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if let hint = session.commandInputHint,
               session.draft.isEmpty {
                Text(hint)
                    .font(DevysTypography.base)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .dropDestination(for: URL.self) { items, _ in
            handleDroppedURLs(items)
        }
        .dropDestination(for: GitDiffTransfer.self) { items, _ in
            session.addAttachments(items.map { .gitDiff(path: $0.path, isStaged: $0.isStaged) })
            return true
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DevysSpacing.space2) {
                ForEach(session.attachmentSummaries) { summary in
                    HStack(spacing: 8) {
                        Image(systemName: summary.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title)
                                .font(DevysTypography.sm)
                                .foregroundStyle(theme.text)
                            if let subtitle = summary.subtitle {
                                Text(subtitle)
                                    .font(DevysTypography.xs)
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }

                        pill(summary.delivery.rawValue.capitalized, tint: theme.content)

                        Button {
                            session.removeAttachment(id: summary.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    // swiftlint:disable:next function_body_length
    private func terminalRow(_ terminal: AgentInlineTerminalViewState) -> some View {
        VStack(alignment: .leading, spacing: DevysSpacing.space2) {
            HStack(spacing: DevysSpacing.space2) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text(terminal.command)
                    .font(DevysTypography.sm)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer()
                if terminal.isRunning {
                    pill("Running", tint: theme.active)
                } else if let exitCode = terminal.exitCode {
                    pill("Exit \(exitCode)", tint: theme.content)
                } else if let signal = terminal.signal {
                    pill("Signal \(signal)", tint: theme.content)
                }
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
                .font(DevysTypography.xs)
                .foregroundStyle(theme.accent)
                .disabled(!terminal.isRunning)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(terminal.output.isEmpty ? "Waiting for output…" : terminal.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 84, maxHeight: 180)
            .background(theme.base)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if terminal.truncated {
                Text("Output truncated to the retained byte limit.")
                    .font(DevysTypography.xs)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func roleLabel(for role: AgentMessageRole) -> String {
        switch role {
        case .user:
            "You"
        case .assistant:
            session.descriptor.displayName
        case .thought:
            "Reasoning"
        }
    }

    private func messageBackground(for role: AgentMessageRole) -> Color {
        switch role {
        case .user:
            theme.active
        case .assistant:
            theme.surface
        case .thought:
            theme.content
        }
    }

    private func icon(for option: AgentSessionConfigOption) -> String {
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

    private func buttonBackground(
        for item: AgentApprovalTimelineItem,
        option: AgentPermissionOption
    ) -> Color {
        if item.selectedOptionID == option.optionId {
            return theme.accent
        }
        return theme.content
    }

    private func buttonTextColor(
        for item: AgentApprovalTimelineItem,
        option: AgentPermissionOption
    ) -> Color {
        if item.selectedOptionID == option.optionId {
            return theme.accentForeground
        }
        return theme.text
    }

    private func statusColor(for style: AgentStatusStyle) -> Color {
        switch style {
        case .neutral:
            theme.textSecondary
        case .warning:
            Color.orange
        case .error:
            Color.red
        }
    }

    private func isLastUserMessage(_ item: AgentMessageTimelineItem) -> Bool {
        guard let lastUserItem = session.timeline.last(where: {
            if case .message(let msg) = $0, msg.role == .user { return true }
            return false
        }),
        case .message(let msg) = lastUserItem else {
            return false
        }
        return msg.id == item.id
    }

    private func pill(
        _ text: String,
        tint: Color
    ) -> some View {
        Text(text)
            .font(DevysTypography.xs)
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint)
            .overlay {
                Capsule()
                    .stroke(theme.borderSubtle, lineWidth: 1)
            }
            .clipShape(Capsule())
    }

    private func diffBlock(
        _ text: String,
        tint: Color
    ) -> some View {
        Text(text)
            .font(DevysTypography.sm)
            .foregroundStyle(theme.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(tint)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.borderSubtle, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func handleDroppedURLs(_ items: [URL]) -> Bool {
        guard !items.isEmpty else { return false }
        session.addAttachments(items.map(attachment(from:)))
        return true
    }

    private func attachment(from url: URL) -> AgentAttachment {
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        if let mimeType,
           let type = UTType(mimeType: mimeType),
           type.conforms(to: .image) {
            return .image(url: url)
        }
        return .file(url: url)
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

    private func copyText(for item: AgentApprovalTimelineItem) -> String {
        [
            item.title,
            item.toolCallId,
            item.options.map(\.name).joined(separator: ", ")
        ]
        .joined(separator: "\n")
    }

    private func copyText(for item: AgentPlanTimelineItem) -> String {
        item.entries.enumerated().map { index, entry in
            "\(index + 1). \(entry.content) [\(entry.status) • \(entry.priority)]"
        }
        .joined(separator: "\n")
    }

    private func copyText(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

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
            textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            textView.textContainerInset = NSSize(width: 0, height: 6)
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
