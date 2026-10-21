import ComposableArchitecture2
import DevysCharacter
import DevysClient
import DevysDesignSystem
import SwiftUI

/// One message, laid out like a group chat: the owner's words on the right in indigo,
/// an employee's on the left with their portrait and name.
struct MessageRow: View {
    let store: StoreOf<Workspace>
    let key: ConversationKey
    let bubble: ChatTimeline.Bubble
    @State private var isHovering = false
    @State private var isPickingReaction = false
    @State private var swipe: CGFloat = 0

    private var isOwner: Bool { bubble.isOwner }
    private var canAct: Bool { bubble.delivery == nil }
    /// A thread starts from a message anywhere but inside a thread.
    private var startsThreads: Bool { canAct && key.kind != .work }
    static let avatarSize: CGFloat = 26

    var body: some View {
        VStack(alignment: isOwner ? .trailing : .leading, spacing: 3) {
            if !isOwner, bubble.startsGroup, let author {
                Text(author.name)
                    .font(DevysTypography.caption.weight(.semibold))
                    .foregroundStyle(DevysColors.ink2)
                    .padding(.leading, Self.avatarSize + 8)
            }
            if let quote = bubble.quote {
                QuotedReply(author: quoteAuthor(quote), text: quote.text, isOwner: isOwner)
                    .padding(.leading, isOwner ? 0 : Self.avatarSize + 8)
            }
            HStack(alignment: .bottom, spacing: 8) {
                if isOwner {
                    Spacer(minLength: 48)
                    if isHovering, canAct { actions }
                } else {
                    avatar
                }
                bubbleView
                if !isOwner {
                    if isHovering, canAct { actions }
                    Spacer(minLength: 48)
                }
            }
            viewed
            footer
        }
        .frame(maxWidth: .infinity, alignment: isOwner ? .trailing : .leading)
        .offset(x: swipe)
        .onHover { hovering in withAnimation(DevysMotion.quick) { isHovering = hovering } }
        #if os(iOS)
            .simultaneousGesture(swipeToReply)
        #endif
    }

    private var bubbleView: some View {
        MessageBubble(bubble: bubble)
            .overlay(alignment: isOwner ? .topLeading : .topTrailing) {
                if !bubble.reactions.isEmpty { ReactionBadge(emoji: bubble.reactions, isOwner: isOwner) }
            }
            .padding(.top, bubble.reactions.isEmpty ? 0 : 12)
            .contextMenu { menu }
            .popover(isPresented: $isPickingReaction, arrowEdge: .top) {
                ReactionPicker(selected: bubble.reactions) { emoji in
                    isPickingReaction = false
                    store.send(.reactionTapped(key, bubble.id, emoji))
                }
            }
            .help(bubble.sentAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
    }

    private var author: Employee? {
        bubble.employeeID.flatMap { id in store.snapshot.employees.first { $0.id == id } }
    }

    private func quoteAuthor(_ quote: ChatTimeline.Quote) -> String {
        quote.employeeID.map(store.state.employeeName) ?? "You"
    }

    @ViewBuilder private var avatar: some View {
        if bubble.endsGroup, let author {
            Portrait(store.state.portrait(for: author), size: Self.avatarSize, label: author.name)
        } else {
            Color.clear.frame(width: Self.avatarSize, height: 1)
        }
    }

    /// Hover affordances on the Mac; the context menu carries the same actions everywhere.
    private var actions: some View {
        HStack(spacing: 2) {
            if !isOwner {
                ChatActionButton("React", symbol: "face.smiling") { isPickingReaction = true }
            }
            ChatActionButton("Reply", symbol: "arrowshape.turn.up.left") { store.send(.replyTapped(key, bubble.id)) }
            if startsThreads {
                ChatActionButton("Start a thread", symbol: "bubble.left.and.text.bubble.right") { store.send(.startThreadTapped(bubble.id)) }
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder private var menu: some View {
        if !isOwner {
            ForEach(ReactionPicker.quick, id: \.self) { emoji in
                Button(bubble.reactions.contains(emoji) ? "\(emoji) Remove" : emoji) {
                    store.send(.reactionTapped(key, bubble.id, emoji))
                }
            }
            Divider()
        }
        if canAct {
            Button("Reply", systemImage: "arrowshape.turn.up.left") { store.send(.replyTapped(key, bubble.id)) }
        }
        if startsThreads {
            Button("Start a thread", systemImage: "bubble.left.and.text.bubble.right") { store.send(.startThreadTapped(bubble.id)) }
        }
        Button("Copy", systemImage: "doc.on.doc") { DevysPasteboard.copy(bubble.text) }
    }

    #if os(iOS)
        /// Drag a message toward the middle to reply to it, as in Messages.
        private var swipeToReply: some Gesture {
            DragGesture(minimumDistance: 24)
                .onChanged { value in
                    guard canAct, abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                    let toward = isOwner ? min(0, value.translation.width) : max(0, value.translation.width)
                    swipe = max(-70, min(70, toward))
                }
                .onEnded { _ in
                    if abs(swipe) >= 56 { store.send(.replyTapped(key, bubble.id)) }
                    withAnimation(DevysMotion.quick) { swipe = 0 }
                }
        }
    #endif

    /// The record the message was about, "Viewing Pricing", which opens it where the registry says.
    @ViewBuilder private var viewed: some View {
        if let ref = bubble.ref, let target = Records.open(ref, work: store.state.threadItem?.id) {
            Button {
                switch target {
                case .layer(let layer): store.send(.layerOpened(layer))
                case .place(.thread(let id)): store.send(.threadOpened(id))
                case .place(let place): store.send(.placeSelected(place))
                }
            } label: {
                Text("Viewing \(store.state.recordTitle(ref))")
                    .font(DevysTypography.caption)
                    .foregroundStyle(DevysColors.ink3)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .padding(.leading, isOwner ? 0 : Self.avatarSize + 8)
        }
    }

    @ViewBuilder private var footer: some View {
        switch bubble.delivery {
        case .sending:
            Text("Sending…").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
        case .failed:
            Button {
                store.send(.retryTapped(key, bubble.id))
            } label: {
                Label("Not delivered · Try again", systemImage: "exclamationmark.circle.fill")
                    .font(DevysTypography.caption)
                    .foregroundStyle(DevysColors.red)
            }
            .buttonStyle(.plain)
        case nil:
            if bubble.viaVoice, bubble.endsGroup {
                Label("Dictated", systemImage: "waveform")
                    .font(DevysTypography.caption)
                    .foregroundStyle(DevysColors.ink3)
                    .labelStyle(VoiceMarkStyle())
            }
        }
    }
}

private struct VoiceMarkStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// One bubble. The corner toward the sender's edge tightens inside a group,
/// and the group's last bubble keeps the tail corner.
struct MessageBubble: View {
    let bubble: ChatTimeline.Bubble

    private var isOwner: Bool { bubble.isOwner }

    var body: some View {
        Text(Self.rendered(bubble.text))
            .font(DevysTypography.body)
            .foregroundStyle(isOwner ? Color.white : DevysColors.ink)
            .tint(isOwner ? Color.white : DevysColors.indigo)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOwner ? DevysColors.indigo : DevysColors.track, in: shape)
            .opacity(bubble.delivery == .sending ? 0.75 : bubble.delivery == .failed ? 0.55 : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var shape: UnevenRoundedRectangle {
        let round: CGFloat = 18
        let joined: CGFloat = 6
        let tail: CGFloat = 4
        let top = bubble.startsGroup ? round : joined
        let bottom = bubble.endsGroup ? tail : joined
        return isOwner
            ? UnevenRoundedRectangle(topLeadingRadius: round, bottomLeadingRadius: round, bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: round, topTrailingRadius: round, style: .continuous)
    }

    /// Inline Markdown (bold, links, code) without block layout.
    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// The message being answered, faded above the reply, with who said it.
private struct QuotedReply: View {
    let author: String
    let text: String
    let isOwner: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isOwner { Spacer(minLength: 64) }
            Image(systemName: "arrowshape.turn.up.left.fill")
                .imageScale(.small)
                .foregroundStyle(DevysColors.ink3)
                .accessibilityHidden(true)
            Text("\(Text(author).fontWeight(.semibold)) \(text)")
                .font(DevysTypography.secondary)
                .foregroundStyle(DevysColors.ink2)
                .lineLimit(2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(DevysColors.hairline, lineWidth: 1)
                }
            if !isOwner { Spacer(minLength: 64) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("In reply to \(author): \(text)")
    }
}

private struct ReactionBadge: View {
    let emoji: [String]
    let isOwner: Bool
    @ScaledMetric(relativeTo: .footnote) private var size = 13.0

    var body: some View {
        Text(emoji.joined())
            .font(.system(size: size))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DevysColors.sheet, in: Capsule())
            .overlay { Capsule().strokeBorder(DevysColors.hairline, lineWidth: 1) }
            .devysElevation(.raised)
            .offset(x: isOwner ? -10 : 10, y: -14)
            .transition(.scale(scale: 0.4).combined(with: .opacity))
            .accessibilityLabel("Reacted \(emoji.joined())")
    }
}

/// Tapbacks: the common six, or any emoji.
struct ReactionPicker: View {
    static let quick = ["👍", "👎", "❤️", "‼️", "❓", "😂"]

    let selected: [String]
    let pick: (String) -> Void
    @State private var custom = ""

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.quick, id: \.self) { emoji in
                Button { pick(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 20))
                        .frame(width: 34, height: 34)
                        .background(selected.contains(emoji) ? DevysColors.indigo.opacity(0.18) : .clear, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
            }
            TextField("", text: $custom, prompt: Text("+").foregroundStyle(DevysColors.ink3))
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .multilineTextAlignment(.center)
                .frame(width: 34, height: 34)
                .background(DevysColors.well, in: Circle())
                .accessibilityLabel("Any emoji")
                .onChange(of: custom) { _, value in
                    if let emoji = value.first(where: { $0.unicodeScalars.first?.properties.isEmojiPresentation == true || $0.unicodeScalars.count > 1 }) {
                        custom = ""
                        pick(String(emoji))
                    }
                }
        }
        .padding(8)
    }
}

private struct ChatActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(DevysColors.ink3)
            .frame(width: 24, height: 24)
            .contentShape(Circle())
            .help(title)
    }
}

/// A hand-off or other event, opened through the record registry. A hand-off is the work item's
/// card: its owner, live status and whether it has unread replies; it opens the thread. A
/// published page opens as a layer, any other record where the registry says; a record kind this
/// client does not know is only its text.
struct EventCard: View {
    let store: StoreOf<Workspace>
    let event: ChatTimeline.Event

    private var target: RecordTarget? { event.ref.flatMap { Records.open($0, work: store.state.threadItem?.id) } }

    private var artifactID: String? {
        guard case .layer(.artifact(let id, _)) = target else { return nil }
        return id
    }

    private var workItem: WorkItem? {
        guard case .place(.thread(let id)) = target else { return nil }
        return store.work.value?.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let artifactID {
                ConversationCard(help: "Open the page") { store.send(.layerOpened(.artifact(artifactID))) } label: {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DevysColors.indigo)
                        .frame(width: 22, height: 22)
                        .background(DevysColors.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    lines(store.artifacts.contains { $0.id == artifactID } ? store.state.artifactName(artifactID) : event.text, pageDetail(artifactID))
                }
            } else if let item = workItem {
                handoff(item)
            } else if let target, let ref = event.ref {
                // Named as the web names it: the record's title over its kind.
                ConversationCard(help: "Open") { open(target) } label: {
                    Image(systemName: Self.symbol(ref))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DevysColors.indigo)
                        .frame(width: 22, height: 22)
                        .background(DevysColors.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .accessibilityHidden(true)
                    lines(store.state.recordTitle(ref), store.state.recordDetail(ref))
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checklist").foregroundStyle(DevysColors.indigo).accessibilityHidden(true)
                    Text(event.text).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DevysColors.sheetTint, in: Capsule())
                .overlay { Capsule().strokeBorder(DevysColors.hairline, lineWidth: 1) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func handoff(_ item: WorkItem) -> some View {
        let owner = store.state.employee(item.ownerEmployeeID)
        let unread = store.state.unread(.work(item.id))
        let next = item.state == .waiting ? item.waitCondition.map { "waiting on \($0)" } : item.nextAction
        return ConversationCard(help: "Open the thread") { store.send(.threadOpened(item.id)) } label: {
            if let owner {
                Portrait(store.state.portrait(for: owner), size: 22, isAnimated: false)
            } else {
                Image(systemName: "checklist").foregroundStyle(DevysColors.indigo).accessibilityHidden(true)
            }
            lines(item.title, [owner?.name, next].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
            Spacer(minLength: 4)
            if unread > 0 {
                Text("\(unread) new").font(DevysTypography.caption.weight(.semibold)).foregroundStyle(DevysColors.indigo)
            }
            item.state.chip(size: .small)
        }
    }

    private static func symbol(_ ref: Ref) -> String {
        switch ref.recordKind {
        case "code/session": "chevron.left.forwardslash.chevron.right"
        case "work/item": "checklist"
        case "work/project": "folder"
        case "work/routine": "repeat"
        default: "doc.text"
        }
    }

    private func open(_ target: RecordTarget) {
        switch target {
        case .layer(let layer): store.send(.layerOpened(layer))
        case .place(.thread(let id)): store.send(.threadOpened(id))
        case .place(let place): store.send(.placeSelected(place))
        }
    }

    /// "Page", or "Page · v2" for a later version of the same page.
    private func pageDetail(_ id: String) -> String {
        guard let page = store.artifacts.first(where: { $0.id == id }) else { return "Page" }
        let version = store.artifacts.filter { $0.filename == page.filename && $0.createdAt <= page.createdAt }.count
        return version > 1 ? "Page · v\(version)" : "Page"
    }

    private func lines(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(DevysTypography.control.weight(.semibold)).foregroundStyle(DevysColors.ink)
            if !detail.isEmpty { Text(detail).font(DevysTypography.caption).foregroundStyle(DevysColors.ink3) }
        }
        .lineLimit(1)
    }
}

/// A card in the conversation that opens what it is about.
private struct ConversationCard<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { label }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: 520, alignment: .leading)
                .background(hovering ? DevysColors.sheetTint : DevysColors.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DevysColors.hairline, lineWidth: 1) }
                .devysElevation(.resting)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityHint(help)
    }
}

/// "<Name> is working…" with their face and three dots.
struct WorkingIndicator: View {
    let store: StoreOf<Workspace>
    let employee: Employee

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Portrait(store.state.portrait(for: employee), size: MessageRow.avatarSize, mood: .thinking)
            TypingDots()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(DevysColors.track, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
            Text("\(employee.name) is working…").font(DevysTypography.caption).foregroundStyle(DevysColors.ink3)
            Spacer(minLength: 24)
        }
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(employee.name) is working")
    }
}

struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate * 4
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(DevysColors.ink3)
                        .frame(width: 6, height: 6)
                        .opacity(reduceMotion ? 0.6 : 0.3 + 0.7 * max(0, sin(time - Double(index) * 0.7)))
                }
            }
        }
        .accessibilityLabel("Working")
    }
}

/// "Today 2:21 PM", "Yesterday 9:04 AM", "Mon 9:04 AM" or a date, centred.
struct TimeHeading: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(DevysTypography.caption)
            .foregroundStyle(DevysColors.ink3)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 2)
    }

    private var label: String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Today \(time)" }
        if calendar.isDateInYesterday(date) { return "Yesterday \(time)" }
        if let days = calendar.dateComponents([.day], from: date, to: .now).day, days < 7 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

/// Shown above the composer while replying to a message.
struct ReplyBanner: View {
    let author: String
    let text: String
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(DevysColors.indigo).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Replying to \(author)").font(DevysTypography.label).foregroundStyle(DevysColors.indigo)
                Text(text).font(DevysTypography.secondary).foregroundStyle(DevysColors.ink2).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Cancel reply", systemImage: "xmark.circle.fill", action: cancel)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(DevysColors.ink3)
        }
        .padding(.horizontal, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
