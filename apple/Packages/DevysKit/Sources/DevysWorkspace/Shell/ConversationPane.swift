import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// The middle of the screen, always a conversation: Home's chat with the Chief of Staff, a direct
/// chat, a project's channel or a work item's thread. It also takes dictation and hands-free voice.
struct ConversationPane: View {
    let store: StoreOf<Workspace>

    var body: some View {
        ZStack(alignment: .top) {
            if let key = store.main?.key {
                VStack(spacing: 0) {
                    ScrollView {
                        ConversationMessages(store: store, key: key)
                            .padding(.horizontal, DevysSpacing.regular)
                            .padding(.vertical, 14)
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                    }
                    // Opens at the newest message and follows new ones; a short conversation starts at the top.
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
                    ConversationComposer(store: store, key: key)
                        .frame(maxWidth: 780)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                }
                .id(key)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let notice = store.notice {
                NoticeBanner(text: notice) { store.send(.noticeDismissed) }
                    .padding(.top, DevysSpacing.compact)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DevysMotion.quick, value: store.notice)
    }
}

private struct NoticeBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(DevysTypography.body).foregroundStyle(DevysColors.ink)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(DevysColors.ink3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(DevysColors.sheet, in: Capsule())
        .devysElevation(.raised)
    }
}

/// The messages of one conversation, oldest first, then who is working on an answer and
/// any request waiting on the owner here.
struct ConversationMessages: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey

    var body: some View {
        if let open = store.state.conversation(key) {
            switch open.messages {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            case .failed(let message):
                Text(message).font(DevysTypography.body).foregroundStyle(DevysColors.ink3).frame(maxWidth: .infinity)
            case .loaded(let messages):
                loaded(open, messages)
            }
        }
    }

    @ViewBuilder private func loaded(_ open: OpenConversation, _ messages: [ConversationMessage]) -> some View {
        let timeline = ChatTimeline(messages: messages, pending: open.pending, now: .now)
        if open.hasOlder {
            Button(open.isLoadingOlder ? "Loading…" : "Earlier messages") { store.send(.loadOlderTapped(key)) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
                .frame(maxWidth: .infinity)
                .disabled(open.isLoadingOlder)
        }
        if timeline.items.isEmpty { empty }
        LazyVStack(spacing: 0) {
            ForEach(timeline.items) { item in
                switch item {
                case .heading(let date):
                    TimeHeading(date: date)
                case .event(let event):
                    if event.isCard, case .workItem(let id)? = event.ref {
                        WorkProgressCard(store: store, workItemID: id, text: event.text, inThread: key.kind == .work)
                    } else {
                        EventCard(store: store, event: event)
                    }
                    if !event.replies.isEmpty {
                        SuggestedReplies(replies: event.replies) { store.send(.suggestedReplyTapped(key, event.id, $0)) }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 3)
                    }
                case .bubble(let bubble):
                    MessageRow(store: store, key: key, bubble: bubble)
                        .padding(.top, bubble.startsGroup ? 10 : 2)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.92, anchor: bubble.isOwner ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                            removal: .identity
                        ))
                }
            }
            ForEach(store.snapshot.employees.filter { open.awaiting.contains($0.id) }) { employee in
                WorkingIndicator(store: store, employee: employee).padding(.top, 10)
            }
            ForEach(decisions) { decision in
                DecisionCard(store: store, decision: decision)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
            if key.kind == .work { BrowserThumbnail(store: store, workID: key.ref) }
        }
        .animation(DevysMotion.arrive, value: timeline.items.map(\.id))
        .animation(DevysMotion.quick, value: open.awaiting)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            if key.kind == .direct, let employee = store.state.employee(key.ref) {
                Portrait(store.state.portrait(for: employee), size: 48)
            }
            Text(emptyText)
                .font(DevysTypography.body)
                .foregroundStyle(DevysColors.ink3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var emptyText: String {
        let name = store.state.employee(key.ref)?.name
        return switch store.place {
        case .home: "Tell \(name ?? "Chief of Staff") what you need. @mention anyone to bring them in."
        case .direct: "Message \(name ?? "them"). @mention a colleague to bring them in."
        case .project(let id): "Tell the team what \(store.state.project(id)?.name ?? "the project") needs. Each piece of work gets its own thread."
        case .thread: "Nothing said about this yet."
        }
    }

    /// Requests waiting on the owner stay inline at the bottom where they were asked: a work item's
    /// in its thread, others in the employee's direct chat. Home's are in Needs you beside it.
    private var decisions: [Decision] {
        guard store.place != .home else { return [] }
        // A connect request is its app's card, already in the conversation.
        let all = store.state.decisions.filter { $0.kind != .connect }
        return switch key.kind {
        case .direct: all.filter { $0.employeeID == key.ref && $0.workItemID == nil }
        case .work: all.filter { $0.workItemID == key.ref }
        case .project: []
        }
    }
}

/// The composer: who answers (their face inside the field, named by the placeholder), what's
/// on screen going with the message (the reference chip), "@" suggestions, the message being replied to, the server's refusal when
/// everyone who'd answer is paused, and voice.
struct ConversationComposer: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey

    var body: some View {
        if let open = store.state.conversation(key) {
            let recipients = store.state.recipients(in: key)
            VStack(alignment: .leading, spacing: 8) {
                if let error = store.voiceError {
                    InlineNotice(text: error, tone: DevysColors.amber) { store.send(.voiceErrorDismissed) }
                }
                if let error = open.error {
                    InlineNotice(text: error, tone: DevysColors.red) { store.send(.conversationErrorDismissed(key)) }
                }
                if let replying = open.replyingTo.flatMap(open.message), !store.isConversationMode {
                    ReplyBanner(author: replying.employeeID.map(store.state.employeeName) ?? "yourself", text: replying.text) {
                        store.send(.replyCancelled(key))
                    }
                }
                MentionSuggestions(store: store, key: key, draft: open.draft)
                if let reference = store.state.reference { ReferenceChip(store: store, reference: reference) }
                if recipients.count == 1, let answerer = store.state.employee(recipients.first), answerer.paused {
                    PausedBanner(store: store, employee: answerer)
                }
                if store.isConversationMode {
                    ConversationStrip(store: store)
                } else {
                    Composer(
                        placeholder,
                        text: Binding(get: { store.state.conversation(key)?.draft ?? "" }, set: { store.send(.draftChanged(key, $0)) }),
                        volatileText: store.volatileText,
                        isListening: store.voice.isCapturing,
                        level: store.level,
                        onMicTap: { store.send(.micTapped) },
                        onHandsFree: { store.send(.conversationToggled) },
                        leading: AnyView(AnswererPicker(store: store, key: key)),
                        onSend: { store.send(.sendTapped(key)) }
                    )
                }
            }
            .animation(DevysMotion.quick, value: open.replyingTo)
            .animation(DevysMotion.quick, value: open.error)
        }
    }

    /// The field names who answers, so no separate "To" row is needed.
    private var placeholder: String {
        let answering = store.state.recipients(in: key).map(store.state.employeeName).joined(separator: ", ")
        if key.kind == .work { return answering.isEmpty ? "Reply" : "Reply to \(answering)" }
        if !answering.isEmpty { return "Message \(answering)" }
        return key.kind == .project ? "Message \(store.state.project(key.ref)?.name ?? "the team")" : "Message"
    }
}

/// "Viewing launch-plan": the open layer goes with the next message as a reference, not a grant.
private struct ReferenceChip: View {
    let store: StoreOf<Workspace>
    let reference: LayerReference

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye").imageScale(.small).foregroundStyle(DevysColors.ink3).accessibilityHidden(true)
            Text("Viewing \(reference.title)").lineLimit(1)
            Button("Don't send what you're viewing", systemImage: "xmark") { store.send(.referencingSet(false)) }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(DevysColors.ink3)
        }
        .font(DevysTypography.caption)
        .foregroundStyle(DevysColors.ink2)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(DevysColors.sheetTint, in: Capsule())
        .help("What you're looking at goes with your message")
    }
}

/// Who answers the draft: their face inside the field. Picking someone sends it to them alone.
struct AnswererPicker: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey

    var body: some View {
        let recipients = store.state.recipients(in: key)
        let picked = store.state.conversation(key)?.responderOverride
        Menu {
            Section("Who answers") {
                ForEach(store.snapshot.employees) { employee in
                    Button {
                        store.send(.responderPicked(key, employee.id))
                    } label: {
                        if recipients.contains(employee.id) {
                            Label(employee.name, systemImage: "checkmark")
                        } else {
                            Text(employee.name)
                        }
                    }
                }
            }
            if picked != nil {
                Divider()
                Button("Whoever would answer", systemImage: "xmark") { store.send(.responderPicked(key, nil)) }
            }
        } label: {
            HStack(spacing: -6) {
                if recipients.isEmpty {
                    Circle().strokeBorder(DevysColors.ink3.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .frame(width: 22, height: 22)
                }
                ForEach(store.snapshot.employees.filter { recipients.contains($0.id) }.prefix(3)) { employee in
                    Portrait(store.state.portrait(for: employee), size: 22, isAnimated: false)
                }
            }
            .padding(3)
            .contentShape(Capsule())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Who answers")
        .accessibilityLabel("Change who answers, now \(recipients.map(store.state.employeeName).joined(separator: ", "))")
    }
}

/// Employees matching the "@" being typed; choosing one completes the name and mentions them.
private struct MentionSuggestions: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey
    let draft: String

    var body: some View {
        let matches = Mentions.suggestions(for: draft, team: store.snapshot.employees)
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matches.prefix(5)) { employee in
                    Button { store.send(.mentionPicked(key, employee.id)) } label: {
                        HStack(spacing: 8) {
                            Portrait(store.state.portrait(for: employee), size: 20, isAnimated: false)
                            Text(employee.name).font(DevysTypography.control).foregroundStyle(DevysColors.ink)
                            Text(RoleTemplate.displayName(employee.template)).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(DevysColors.sheet, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(DevysColors.hairline, lineWidth: 1) }
            .devysElevation(.raised)
            .transition(.opacity)
        }
    }
}

/// A one-line message above the composer with a way to dismiss it.
private struct InlineNotice: View {
    let text: String
    let tone: Color
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(tone).accessibilityHidden(true)
            Text(text).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2)
            Spacer(minLength: 4)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(DevysColors.ink3)
        }
        .padding(.horizontal, 6)
        .transition(.opacity)
    }
}

/// Hands-free conversation: what's happening, a live level, and a way out.
struct ConversationStrip: View {
    let store: StoreOf<Workspace>

    var body: some View {
        HStack(spacing: 12) {
            LevelBars(level: store.voice.isCapturing ? store.level : 0, active: store.voice.isCapturing)
            VStack(alignment: .leading, spacing: 2) {
                Text(phase).font(DevysTypography.body.weight(.semibold)).foregroundStyle(DevysColors.ink)
                if !store.volatileText.isEmpty {
                    Text(store.volatileText).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink3).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if store.voice == .speaking {
                Button("Interrupt", systemImage: "hand.raised") { store.send(.stopSpeakingTapped) }
                    .buttonStyle(DevysButtonStyle(.raised, compact: true))
            }
            Button("End", systemImage: "xmark") { store.send(.conversationToggled) }
                .buttonStyle(DevysButtonStyle(.quiet, compact: true))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DevysColors.sheetTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DevysColors.indigo.opacity(store.voice.isCapturing ? 0.45 : 0.15), lineWidth: 1.5)
        }
    }

    private var phase: String {
        switch store.voice {
        case .starting: "Getting ready…"
        case .listening: "Listening"
        case .finishing: "Sending…"
        case .awaitingReply: "Waiting for the answer…"
        case .speaking: "Speaking"
        case .idle: "Paused"
        }
    }
}

private struct LevelBars: View {
    let level: Double
    let active: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(DevysColors.indigo.opacity(active ? 1 : 0.35))
                    .frame(width: 4, height: 6 + CGFloat(level) * [14, 22, 18, 10][index])
            }
        }
        .frame(width: 28, height: 28)
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}
