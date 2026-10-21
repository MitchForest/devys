import ComposableArchitecture2
import Dependencies
package import DevysClient
import Foundation

// MARK: - The conversation in the middle: Home's, a direct chat, a project's channel or a thread

extension EmployeeStatus {
    /// Pi is running something for the employee right now.
    package var isRunning: Bool { state.run.map { !$0.stopped } ?? false }
}

extension Workspace.State {
    package func conversation(_ key: ConversationKey) -> OpenConversation? {
        main?.key == key ? main : nil
    }

    package func unread(_ key: ConversationKey) -> Int { summaries[key.rawValue]?.unread ?? 0 }

    /// Work items the signed-in person follows.
    package func isFollowing(_ workItemID: String) -> Bool {
        summaries[ConversationKey.work(workItemID).rawValue]?.following ?? false
    }

    /// Who answers when nobody has spoken yet: a direct chat's employee, a project's lead, a work item's owner.
    package func defaultResponder(for key: ConversationKey) -> String? {
        switch key.kind {
        case .direct: key.ref
        case .project: projects.value?.first { $0.id == key.ref }?.leadEmployeeID
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
        let answering = main?.awaiting.contains(employeeID) == true
        return status?.isRunning == true || answering || unfinished
    }
}

extension Workspace {
    func reduceConversation(_ intent: ConversationIntent, state: inout State) {
        switch intent {
        case .summariesLoaded, .followToggled:
            reduceSummaries(intent, state: &state)
        case .pageLoaded(let key, let page, let older):
            guard let open = state.conversation(key) else { return }
            // Messages that arrived since the last look; nothing counts as arriving on first load.
            let known = open.messages.value.map { Set($0.map(\.id)) }
            update(key, &state) { $0.merge(page, older: older) }
            settleAwaiting(&state)
            speakReplies(&state)
            markRead(key, state: &state)
            if let known, !older, let page = state.main?.messages.value?.last(where: { !known.contains($0.id) && $0.isEvent && $0.ref?.page != nil }) {
                pageArrived(page, state: &state)
            }
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
            guard let open = state.conversation(key), !open.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if state.voice.mode == .dictation { cancelCapture(&state) }
            // The layer the owner is looking at goes with the message, so "this" means what is on screen.
            let text = state.reference.map { open.draft.trimmingCharacters(in: .whitespacesAndNewlines) + $0.line } ?? open.draft
            send(text, viaVoice: open.draftUsedVoice, in: key, state: &state)
            state.isReferencing = false
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
        }
    }

    /// What's open and already seen stays read, whatever an older count says.
    func loadedSummaries(_ summaries: [ConversationSummary], state: inout State) {
        state.summaries = Dictionary(summaries.map { ($0.key, $0) }) { first, _ in first }
        guard let open = state.main, let seen = state.summaries[open.key.rawValue], seen.last?.createdAt == open.readAt else { return }
        state.summaries[open.key.rawValue] = ConversationSummary(key: seen.key, last: seen.last, unread: 0, following: seen.following)
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

    /// The place's conversation opens in the middle; Home's waits for Operations to load.
    func openConversation(_ state: inout State) {
        let key = state.mainKey
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

    /// Every few seconds: unread counts, the open conversation, and whoever is being waited on.
    func refreshConversations(_ state: State) {
        loadSummaries(state)
        if let key = state.main?.key { loadPage(key, state: state) }
    }

    /// The conversation list: loaded from the server, or a work thread followed or not.
    func reduceSummaries(_ intent: ConversationIntent, state: inout State) {
        switch intent {
        case .summariesLoaded(let businessID, let summaries):
            guard businessID == state.businessID else { return }
            loadedSummaries(summaries, state: &state)
        case .followToggled(let workItemID):
            toggleFollowing(workItemID, state: &state)
        default:
            return
        }
    }

    /// Follows a work item's thread, or stops; the sidebar and bell update before the server answers.
    func toggleFollowing(_ workItemID: String, state: inout State) {
        let key = ConversationKey.work(workItemID)
        let following = !state.isFollowing(workItemID)
        let summary = state.summaries[key.rawValue]
        state.summaries[key.rawValue] = ConversationSummary(key: key.rawValue, last: summary?.last, unread: summary?.unread ?? 0, following: following)
        let businessID = state.businessID
        let runtime = runtime
        store.addTask { try? await runtime.follow(businessID, key, following) }
    }

    /// While a conversation is on screen, everything in it up to the newest message is read.
    func markRead(_ key: ConversationKey, state: inout State) {
        guard let open = state.conversation(key), let newest = open.messages.value?.last, newest.createdAt != open.readAt else { return }
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
        guard let key = state.main?.key else { return }
        let waiting = state.main?.awaiting.isEmpty == false
        update(key, &state) { conversation in
            let open = conversation
            conversation.awaiting.removeAll { id in
                statuses[id]?.isRunning != true && (open.hasAnswered(id) || open.stoppedPolling)
            }
        }
        if waiting, state.main?.awaiting.isEmpty == true { state.turns += 1 }
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
        if state.isConversationMode || voiceSettings.load().speaksReplies {
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
