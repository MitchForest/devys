package import DevysClient
import Foundation

/// A message sent from this device that the conversation doesn't show yet.
package struct PendingMessage: Equatable, Sendable, Identifiable {
    package enum Delivery: Equatable, Sendable { case sending, failed }

    /// The client id; a retry reuses it, so the server never posts it twice.
    package let id: String
    package let text: String
    package var replyTo: String?
    package var mentions: [String] = []
    package var viaVoice = false
    /// The record on screen as it was sent, as the message's ref.
    package var ref: Ref?
    package var delivery: Delivery = .sending

    package var failed: Bool { delivery == .failed }
    package var outgoing: NewMessage {
        NewMessage(id: id, text: text, replyTo: replyTo, mentions: mentions, viaVoice: viaVoice, ref: ref)
    }
}

/// The open conversation in the middle: Home's, a direct chat, a project's channel or a thread.
package struct OpenConversation {
    package let key: ConversationKey
    /// Oldest first.
    package var messages: Loadable<[ConversationMessage]> = .loading
    /// Who answers the owner's next plain message, as the server last said.
    package var respondent: String?
    package var hasOlder = false
    package var isLoadingOlder = false
    package var pending: [PendingMessage] = []
    package var draft = ""
    /// The draft includes dictated words, so the employee hears it may have transcription errors.
    package var draftUsedVoice = false
    package var replyingTo: String?
    /// Employees added from @-autocomplete; each counts while its "@Name" is still in the draft.
    package var mentions: [String] = []
    /// Picked from the To chip: the next message's sole mention.
    package var responderOverride: String?
    /// Why the last send was refused, in the server's words, e.g. "Growth is paused. Resume them to send."
    package var error: String?
    /// Employees the owner's last message went to, until each has answered and stopped working.
    package var awaiting: [String] = []
    /// The owner's last posted message; answers to it come after it.
    package var awaitingAfter: String?
    /// Fast polling for the last message has ended; whoever stopped working stops being waited on.
    package var stoppedPolling = false
    /// The newest created_at this device marked read.
    package var readAt: String?
    /// Answers ticked on a pick-many question card, and the message they answer.
    package var picked: [String] = []
    package var pickedFor: String?
    /// A business file attached with the composer's +: the next message's ref.
    package var attachment: Ref?
    /// A file from this device going up to the business folder, to be attached.
    package var isUploading = false

    package init(key: ConversationKey) {
        self.key = key
    }

    package func message(_ id: String) -> ConversationMessage? {
        messages.value?.first { $0.id == id }
    }

    /// The employees @mentioned by the draft: the To chip's pick alone, else every mention in the text.
    package func mentioned(team: [Employee]) -> [String] {
        if let responderOverride { return [responderOverride] }
        let typed = Set(Mentions.recipients(in: draft, team: team))
        let picked = Set(mentions.filter { id in
            team.first { $0.id == id }.map { draft.range(of: "@\($0.name)", options: .caseInsensitive) != nil } ?? false
        })
        return team.map(\.id).filter { typed.contains($0) || picked.contains($0) }
    }

    /// Who answers the draft, by the conversation's rules: those mentioned, else the
    /// author of the message being replied to, else whoever spoke last (or the default).
    package func recipients(team: [Employee], fallback: String?) -> [String] {
        let mentioned = mentioned(team: team)
        if !mentioned.isEmpty { return mentioned }
        if let replyingTo, let author = message(replyingTo)?.employeeID { return [author] }
        return (respondent ?? fallback).map { [$0] } ?? []
    }

    /// Whether an employee has answered since the owner's last message.
    package func hasAnswered(_ employeeID: String) -> Bool {
        guard let messages = messages.value else { return false }
        // A message no longer on the page is older than all of it.
        let start = awaitingAfter.flatMap { id in messages.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0
        return messages[start...].contains { $0.employeeID == employeeID && !$0.isEvent }
    }

    /// The newest page replaces what it overlaps; older pages go in front.
    mutating func merge(_ page: ConversationPage, older: Bool) {
        let current = messages.value ?? []
        if older {
            let known = Set(current.map(\.id))
            messages = .loaded(page.messages.filter { !known.contains($0.id) } + current)
            hasOlder = page.messages.count >= ConversationPage.size
            isLoadingOlder = false
            return
        }
        let fresh = Set(page.messages.map(\.id))
        let overlaps = current.contains { fresh.contains($0.id) }
        let earlier = overlaps ? Array(current.prefix { !fresh.contains($0.id) }) : []
        if messages.value == nil || !overlaps { hasOlder = page.messages.count >= ConversationPage.size }
        messages = .loaded(earlier + page.messages)
        respondent = page.respondent
    }
}

/// Who a message mentions as "@Name", and the "@" autocomplete.
package enum Mentions {
    /// Every employee the text mentions as "@Name", in team order. Longer names win, so
    /// "@Growth Lead" isn't also read as "@Growth".
    package static func recipients(in text: String, team: [Employee]) -> [String] {
        var remaining = text
        var mentioned: Set<String> = []
        for employee in team.sorted(by: { $0.name.count > $1.name.count }) {
            let token = "@\(employee.name)"
            guard remaining.range(of: token, options: .caseInsensitive) != nil else { continue }
            mentioned.insert(employee.id)
            remaining = remaining.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        return team.map(\.id).filter(mentioned.contains)
    }

    /// The name being typed after a trailing "@", if any.
    package static func query(in draft: String) -> String? {
        guard let sign = draft.lastIndex(of: "@") else { return nil }
        if sign > draft.startIndex, !draft[draft.index(before: sign)].isWhitespace { return nil }
        let query = String(draft[draft.index(after: sign)...])
        return query.contains(where: \.isNewline) ? nil : query
    }

    /// Employees whose names complete the "@" being typed.
    package static func suggestions(for draft: String, team: [Employee]) -> [Employee] {
        guard let query = query(in: draft)?.lowercased() else { return [] }
        return team.filter { $0.name.lowercased().hasPrefix(query) }
    }

    /// Completes the "@" being typed with "@Name ", or adds "@Name " at the end.
    package static func insert(_ name: String, into draft: String) -> String {
        if let query = query(in: draft) {
            return String(draft.dropLast(query.count + 1)) + "@\(name) "
        }
        let separator = draft.isEmpty || draft.hasSuffix(" ") ? "" : " "
        return "\(draft)\(separator)@\(name) "
    }
}

package enum ConversationIntent {
    case summariesLoaded(businessID: String, [ConversationSummary])
    case pageLoaded(ConversationKey, ConversationPage, older: Bool)
    case pageFailed(ConversationKey, String)
    case loadOlderTapped(ConversationKey)
    case draftChanged(ConversationKey, String)
    /// Chosen from the "@" suggestions: completes the name and mentions the employee.
    case mentionPicked(ConversationKey, employeeID: String)
    /// Chosen from the To chip; nil goes back to the rules.
    case responderPicked(ConversationKey, employeeID: String?)
    case replyTapped(ConversationKey, messageID: String)
    case replyCancelled(ConversationKey)
    case sendTapped(ConversationKey)
    /// An answer on a question card: sent as the reply to it, or ticked when several may be picked.
    case answerPicked(ConversationKey, messageID: String, answer: String)
    /// Done on a pick-many card: the ticked answers, in the card's order, as one reply.
    case answersDone(ConversationKey, messageID: String)
    /// "Something else": the composer takes the answer.
    case somethingElseTapped(ConversationKey)
    /// The composer's +: a business file to go with the next message, or nil to remove it.
    case attachmentSet(ConversationKey, Ref?)
    /// The composer's + › Upload a file…: it goes into the business folder's Uploads, then is attached.
    case uploadChosen(ConversationKey, ChosenFile)
    case uploadFailed(ConversationKey)
    case posted(ConversationKey, clientID: String, PostedMessage)
    /// `refusal` is the server's own words when it declined the message (409).
    case sendFailed(ConversationKey, clientID: String, refusal: String?)
    case retryTapped(ConversationKey, clientID: String)
    case reactionTapped(ConversationKey, messageID: String, emoji: String)
    case errorDismissed(ConversationKey)
    /// Hear each milestone of a work item and keep it in the sidebar, or only its outcome.
    case followToggled(workItemID: String)
    /// Fast polling after a message ended, answered or not.
    case waitEnded(ConversationKey, after: String)
    /// "Worked for …" opened under a reply: its steps are read from its employee once.
    case stepsRequested(ConversationKey, messageID: String)
    case stepsLoaded(messageID: String, Loadable<[String]>)
}
