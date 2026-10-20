import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - Shared conversations: DMs and spaces in the main pane, work threads in the right panel

extension EmployeeStatus {
    /// Pi is running something for the employee right now.
    package var isRunning: Bool { state.run.map { !$0.stopped } ?? false }
}

extension Workspace.State {
    /// The conversation a page shows in the main pane: a DM or a space.
    package static func conversationKey(for page: Page) -> ConversationKey? {
        switch page {
        case .direct(let id): .direct(id)
        case .space(let id): .space(id)
        default: nil
        }
    }

    /// The work item open in the right panel (pushed on iPhone).
    package var selectedWorkID: String? { panel?.key.ref }

    package func conversation(_ key: ConversationKey) -> OpenConversation? {
        if main?.key == key { return main }
        if panel?.key == key { return panel }
        return nil
    }

    package func unread(_ key: ConversationKey) -> Int { summaries[key.rawValue]?.unread ?? 0 }

    /// Work items the signed-in person follows.
    package func isFollowing(_ commitmentID: String) -> Bool {
        summaries[ConversationKey.work(commitmentID).rawValue]?.following ?? false
    }

    /// Who answers when nobody has spoken yet: a DM's employee, a space's lead, a work item's owner.
    package func defaultResponder(for key: ConversationKey) -> String? {
        switch key.kind {
        case .direct: key.ref
        case .space: spaces.value?.first { $0.id == key.ref }?.leadEmployeeID
        case .work: work.value?.first { $0.id == key.ref }?.ownerEmployeeID
        }
    }

    /// Who the composer's draft goes to, for the To chip.
    package func recipients(in key: ConversationKey) -> [String] {
        conversation(key)?.recipients(team: snapshot.employees, fallback: defaultResponder(for: key)) ?? []
    }

    /// Pi is running something for the employee, it owes an answer in an open conversation, or
    /// its inbox has unfinished messages. The same rule as the web's `workingOf`.
    package func isWorking(_ employeeID: String) -> Bool {
        let status = statuses[employeeID]
        let unfinished = status?.state.inbox.contains { $0.status != "done" && $0.status != "failed" } ?? false
        let answering = [main, panel].contains { $0?.awaiting.contains(employeeID) == true }
        return status?.isRunning == true || answering || unfinished
    }

    /// The main pane's conversation is on screen (a space shows it on its Conversation tab).
    var isMainVisible: Bool {
        switch page {
        case .direct: true
        case .space: spaceTab == .conversation
        default: false
        }
    }

    func isVisible(_ key: ConversationKey) -> Bool {
        key == main?.key ? isMainVisible : key == panel?.key
    }
}

extension Workspace {
    func reduceConversation(_ intent: ConversationIntent, state: inout State) {
        switch intent {
        case .summariesLoaded, .followToggled:
            reduceSummaries(intent, state: &state)
        case .pageLoaded(let key, let page, let older):
            update(key, &state) { $0.merge(page, older: older) }
            settleAwaiting(&state)
            if key == state.main?.key { speakReplies(&state) }
            markRead(key, state: &state)
        case .pageFailed(let key, let message):
            update(key, &state) { conversation in
                conversation.isLoadingOlder = false
                if conversation.messages.value == nil { conversation.messages = .failed(message) }
            }
        case .loadOlderTapped(let key):
            guard let open = state.conversation(key), open.hasOlder, !open.isLoadingOlder, let oldest = open.messages.value?.first?.id else { return }
            update(key, &state) { $0.isLoadingOlder = true }
            loadPage(key, before: oldest, state: state)
        case .draftChanged, .mentionPicked, .responderPicked, .replyTapped, .replyCancelled, .errorDismissed:
            reduceDraft(intent, state: &state)
        case .sendTapped(let key):
            guard let open = state.conversation(key) else { return }
            if key == state.main?.key, state.voice.mode == .dictation { cancelCapture(&state) }
            send(open.draft, viaVoice: open.draftUsedVoice, in: key, state: &state)
        case .posted(let key, let clientID, let message):
            posted(message, clientID: clientID, in: key, state: &state)
        case .sendFailed(let key, let clientID, let refusal):
            sendFailed(clientID, refusal: refusal, in: key, state: &state)
        case .retryTapped(let key, let clientID):
            retry(clientID, in: key, state: &state)
        case .reactionTapped(let key, let messageID, let emoji):
            toggleReaction(emoji, on: messageID, in: key, state: &state)
        case .waitEnded(let key, let messageID):
            update(key, &state) { conversation in
                if conversation.awaitingAfter == messageID { conversation.stoppedPolling = true }
            }
            settleAwaiting(&state)
        case .workOpened(let id):
            openWork(id, state: &state)
        case .workClosed:
            state.panel = nil
        }
    }

    /// The work item opens in the right panel with its thread; on iPhone it pushes.
    func openWork(_ id: String, state: inout State) {
        state.isInspectorVisible = true
        guard state.panel?.key != .work(id) else { return }
        state.panel = OpenConversation(key: .work(id))
        loadPage(.work(id), state: state)
    }

    /// What's open and already seen stays read, whatever an older count says.
    func loadedSummaries(_ summaries: [ConversationSummary], state: inout State) {
        state.summaries = Dictionary(summaries.map { ($0.key, $0) }) { first, _ in first }
        for open in [state.main, state.panel].compactMap(\.self) where state.isVisible(open.key) {
            guard let seen = state.summaries[open.key.rawValue], seen.last?.createdAt == open.readAt else { continue }
            state.summaries[open.key.rawValue] = ConversationSummary(key: seen.key, last: seen.last, unread: 0, following: seen.following)
        }
    }

    /// Posts a failed message again with the same client id.
    func retry(_ clientID: String, in key: ConversationKey, state: inout State) {
        guard let message = state.conversation(key)?.pending.first(where: { $0.id == clientID && $0.failed }) else { return }
        update(key, &state) { conversation in
            if let index = conversation.pending.firstIndex(where: { $0.id == clientID }) { conversation.pending[index].delivery = .sending }
        }
        deliver(message, in: key, state: state)
    }

    /// What the owner is writing: the draft, its mentions, who answers, and what it replies to.
    func reduceDraft(_ intent: ConversationIntent, state: inout State) {
        switch intent {
        case .draftChanged(let key, let text):
            update(key, &state) { conversation in
                conversation.draft = text
                conversation.error = nil
                if text.isEmpty {
                    conversation.draftUsedVoice = false
                    conversation.mentions = []
                }
            }
        case .mentionPicked(let key, let employeeID):
            guard let name = state.snapshot.employees.first(where: { $0.id == employeeID })?.name else { return }
            update(key, &state) { conversation in
                conversation.draft = Mentions.insert(name, into: conversation.draft)
                if !conversation.mentions.contains(employeeID) { conversation.mentions.append(employeeID) }
            }
        case .responderPicked(let key, let employeeID):
            update(key, &state) { $0.responderOverride = employeeID }
        case .replyTapped(let key, let messageID):
            update(key, &state) { conversation in
                guard let message = conversation.message(messageID), !message.isEvent else { return }
                conversation.replyingTo = messageID
            }
        case .replyCancelled(let key):
            update(key, &state) { $0.replyingTo = nil }
        case .errorDismissed(let key):
            update(key, &state) { $0.error = nil }
        default:
            break
        }
    }

    /// Opening a DM or a space opens its conversation in the main pane; other pages close it.
    func openConversation(for page: Page, state: inout State) {
        let key = State.conversationKey(for: page)
        guard key != state.main?.key else {
            if let key { markRead(key, state: &state) }
            return
        }
        if state.isConversationMode { endConversation(&state) } else if state.voice.isCapturing { cancelCapture(&state) }
        state.main = key.map(OpenConversation.init)
        if let key { loadPage(key, state: state) }
    }

    func update(_ key: ConversationKey, _ state: inout State, _ change: (inout OpenConversation) -> Void) {
        if var open = state.main, open.key == key {
            change(&open)
            state.main = open
        }
        if var open = state.panel, open.key == key {
            change(&open)
            state.panel = open
        }
    }

    func loadPage(_ key: ConversationKey, before: String? = nil, state: State) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            do {
                let page = try await runtime.conversation(businessID, key, before)
                try store.send(Action(.conversation(.pageLoaded(key, page, older: before != nil))))
            } catch {
                try store.send(Action(.conversation(.pageFailed(key, before == nil ? "Couldn't load the conversation." : "Couldn't load earlier messages."))))
            }
        }
    }

    func loadSummaries(_ state: State) {
        let businessID = state.businessID
        guard !businessID.isEmpty else { return }
        let runtime = runtime
        store.addTask {
            guard let summaries = try? await runtime.conversations(businessID) else { return }
            try store.send(Action(.conversation(.summariesLoaded(businessID: businessID, summaries))))
        }
    }

    /// Every few seconds: unread counts, the open conversations, and whoever is being waited on.
    func refreshConversations(_ state: State) {
        loadSummaries(state)
        for key in [state.main?.key, state.panel?.key].compactMap(\.self) { loadPage(key, state: state) }
    }

    /// The conversation list: loaded from the server, or a work thread followed or not.
    func reduceSummaries(_ intent: ConversationIntent, state: inout State) {
        switch intent {
        case .summariesLoaded(let businessID, let summaries):
            guard businessID == state.businessID else { return }
            loadedSummaries(summaries, state: &state)
        case .followToggled(let commitmentID):
            toggleFollowing(commitmentID, state: &state)
        default:
            return
        }
    }

    /// Follows a work item's thread, or stops; the sidebar and bell update before the server answers.
    func toggleFollowing(_ commitmentID: String, state: inout State) {
        let key = ConversationKey.work(commitmentID)
        let following = !state.isFollowing(commitmentID)
        let summary = state.summaries[key.rawValue]
        state.summaries[key.rawValue] = ConversationSummary(key: key.rawValue, last: summary?.last, unread: summary?.unread ?? 0, following: following)
        let businessID = state.businessID
        let runtime = runtime
        store.addTask { try? await runtime.follow(businessID, key, following) }
    }

    /// While a conversation is on screen, everything in it up to the newest message is read.
    func markRead(_ key: ConversationKey, state: inout State) {
        guard state.isVisible(key), let open = state.conversation(key), let newest = open.messages.value?.last, newest.createdAt != open.readAt else { return }
        update(key, &state) { $0.readAt = newest.createdAt }
        if let summary = state.summaries[key.rawValue] {
            state.summaries[key.rawValue] = ConversationSummary(key: summary.key, last: summary.last, unread: 0, following: summary.following)
        }
        let businessID = state.businessID
        let runtime = runtime
        store.addTask { try? await runtime.markRead(businessID, key, newest.createdAt) }
    }

    /// An employee stops being waited on once it has answered and stopped working, or
    /// stopped working after fast polling gave up.
    func settleAwaiting(_ state: inout State) {
        let statuses = state.statuses
        for key in [state.main?.key, state.panel?.key].compactMap(\.self) {
            update(key, &state) { conversation in
                let open = conversation
                conversation.awaiting.removeAll { id in
                    statuses[id]?.isRunning != true && (open.hasAnswered(id) || open.stoppedPolling)
                }
            }
        }
    }

    /// Shows the message at once and posts it; returns its client id.
    @discardableResult
    func send(_ text: String, viaVoice: Bool, in key: ConversationKey, state: inout State) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let open = state.conversation(key) else { return nil }
        let message = PendingMessage(
            id: uuid().uuidString.lowercased(),
            text: text,
            replyTo: open.replyingTo,
            mentions: open.mentioned(team: state.snapshot.employees),
            viaVoice: viaVoice
        )
        update(key, &state) { conversation in
            conversation.pending.append(message)
            conversation.draft = ""
            conversation.draftUsedVoice = false
            conversation.replyingTo = nil
            conversation.mentions = []
            conversation.responderOverride = nil
            conversation.error = nil
        }
        if key == state.main?.key, state.isConversationMode || voiceSettings.load().speaksReplies {
            state.repliesToSpeak.insert(message.id)
        }
        deliver(message, in: key, state: state)
        return message.id
    }

    /// Posts (or reposts, with the same client id) one message.
    func deliver(_ message: PendingMessage, in key: ConversationKey, state: State) {
        let businessID = state.businessID
        let runtime = runtime
        store.addTask {
            do {
                let posted = try await runtime.postMessage(businessID, key, message.outgoing)
                try store.send(Action(.conversation(.posted(key, clientID: message.id, posted))))
            } catch DevysHTTPError.rejected(status: 409, let text) {
                let refusal = text.isEmpty ? "Everyone who would answer is paused. Resume them to send." : text
                try store.send(Action(.conversation(.sendFailed(key, clientID: message.id, refusal: refusal))))
            } catch {
                try store.send(Action(.conversation(.sendFailed(key, clientID: message.id, refusal: nil))))
            }
        }
    }

    func posted(_ posted: PostedMessage, clientID: String, in key: ConversationKey, state: inout State) {
        update(key, &state) { conversation in
            conversation.pending.removeAll { $0.id == clientID }
            if var messages = conversation.messages.value, !messages.contains(where: { $0.id == posted.message.id }) {
                messages.append(posted.message)
                conversation.messages = .loaded(messages)
            }
            conversation.awaiting = posted.recipients
            conversation.awaitingAfter = posted.message.id
            conversation.stoppedPolling = false
        }
        if state.repliesToSpeak.remove(clientID) != nil { state.repliesToSpeak.insert(posted.message.id) }
        if state.voice == .awaitingReply(messageID: clientID) { state.voice = .awaitingReply(messageID: posted.message.id) }
        markRead(key, state: &state)
        awaitAnswers(posted, in: key, state: state)
    }

    /// A refusal (everyone who'd answer is paused) shows inline and gives the words back;
    /// any other failure keeps the message with a retry.
    func sendFailed(_ clientID: String, refusal: String?, in key: ConversationKey, state: inout State) {
        update(key, &state) { conversation in
            guard let index = conversation.pending.firstIndex(where: { $0.id == clientID }) else { return }
            guard let refusal else {
                conversation.pending[index].delivery = .failed
                return
            }
            let message = conversation.pending.remove(at: index)
            conversation.error = refusal
            if conversation.draft.isEmpty { conversation.draft = message.text }
        }
        guard refusal != nil else { return }
        state.repliesToSpeak.remove(clientID)
        if state.voice == .awaitingReply(messageID: clientID) { state.voice = .idle }
    }

    /// Polls about every two seconds, for up to ~90 seconds, until everyone asked has answered
    /// and stopped working; the regular refresh carries on after that.
    func awaitAnswers(_ posted: PostedMessage, in key: ConversationKey, state: State) {
        guard !posted.recipients.isEmpty else { return }
        let businessID = state.businessID
        let runtime = runtime
        let clock = clock
        store.addTask {
            defer { _ = try? store.send(Action(.conversation(.waitEnded(key, after: posted.message.id)))) }
            for _ in 0..<45 {
                try await clock.sleep(for: .seconds(2))
                guard let page = try? await runtime.conversation(businessID, key, nil) else { continue }
                try store.send(Action(.conversation(.pageLoaded(key, page, older: false))))
                var working = false
                for id in posted.recipients {
                    let scope = EmployeeScope(businessID: businessID, employeeID: id)
                    guard let status = try? await runtime.status(scope) else { continue }
                    try store.send(Action(.statusLoaded(scope, status)))
                    working = working || status.isRunning
                }
                let start = page.messages.firstIndex { $0.id == posted.message.id }.map { $0 + 1 } ?? 0
                let answered = posted.recipients.allSatisfy { id in page.messages[start...].contains { $0.employeeID == id && !$0.isEvent } }
                if answered, !working { return }
            }
        }
    }

    /// One tapback per message, like Messages: a new one replaces the old. It goes to the author.
    func toggleReaction(_ emoji: String, on messageID: String, in key: ConversationKey, state: inout State) {
        guard let message = state.conversation(key)?.message(messageID), let author = message.employeeID, !message.isEvent else { return }
        let removing = message.reactions.contains(emoji)
        let changes = message.reactions.map { Reaction(targetId: message.id, targetText: message.text, emoji: $0, isOn: false) }
            + (removing ? [] : [Reaction(targetId: message.id, targetText: message.text, emoji: emoji, isOn: true)])
        update(key, &state) { conversation in
            guard var messages = conversation.messages.value, let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
            messages[index].reactions = removing ? [] : [emoji]
            conversation.messages = .loaded(messages)
        }
        let scope = EmployeeScope(businessID: state.businessID, employeeID: author)
        let runtime = runtime
        store.addTask {
            do {
                for change in changes { try await runtime.react(scope, change) }
            } catch {
                try store.send(Action(.stopFinished("That reaction couldn't be saved.")))
            }
        }
    }

    /// Reads aloud the first answer to a message sent by voice (or when replies are spoken).
    func speakReplies(_ state: inout State) {
        guard let messages = state.main?.messages.value else { return }
        for id in state.repliesToSpeak {
            guard let index = messages.firstIndex(where: { $0.id == id }),
                  let reply = messages[(index + 1)...].first(where: { $0.employeeID != nil && !$0.isEvent })
            else { continue }
            state.repliesToSpeak.remove(id)
            guard state.voice == .awaitingReply(messageID: id) || state.voice == .idle else { continue }
            state.voice = .speaking
            let playback = playback
            let settings = voiceSettings.load()
            store.addTask {
                try? await playback.speak(reply.text, settings.voiceID, settings.rate)
                try store.send(Action(.speakingFinished))
            }
            return
        }
    }
}
