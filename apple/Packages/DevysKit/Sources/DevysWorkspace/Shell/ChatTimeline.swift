package import DevysClient
package import Foundation

/// A conversation as a group chat lays it out: messages grouped by author, a time
/// heading when the day changes or an hour passes, hand-off events as centred cards,
/// and sent-but-unposted messages last.
package struct ChatTimeline: Equatable {
    package enum Position: Equatable { case single, first, middle, last }

    /// The message a reply answers, quoted above it.
    package struct Quote: Equatable {
        package let messageID: String
        package let text: String
        /// nil when the owner wrote it.
        package let employeeID: String?
    }

    package struct Bubble: Equatable, Identifiable {
        package let id: String
        /// The employee who wrote it; nil for the owner.
        package let employeeID: String?
        package let isOwner: Bool
        package let text: String
        package let quote: Quote?
        package let viaVoice: Bool
        package let reactions: [String]
        package let sentAt: Date?
        /// The record the message was about ("Viewing …"), which opens it.
        package var ref: Ref?
        package var position: Position
        /// Set for messages sent from this device that the server hasn't posted yet.
        package var delivery: PendingMessage.Delivery?

        package var endsGroup: Bool { position == .single || position == .last }
        package var startsGroup: Bool { position == .single || position == .first }
    }

    /// A hand-off or other system event; `ref` is the record it is about.
    package struct Event: Equatable, Identifiable {
        package let id: String
        package let text: String
        package let ref: Ref?
    }

    package enum Item: Equatable, Identifiable {
        case heading(Date)
        case bubble(Bubble)
        case event(Event)

        package var id: String {
            switch self {
            case .heading(let date): "heading-\(date.timeIntervalSince1970)"
            case .bubble(let bubble): bubble.id
            case .event(let event): event.id
            }
        }
    }

    package let items: [Item]

    /// A new group starts when the author changes or the gap exceeds this.
    static let groupGap: TimeInterval = 5 * 60
    static let headingGap: TimeInterval = 60 * 60

    package init(messages: [ConversationMessage], pending: [PendingMessage], now: Date, calendar: Calendar = .current) {
        let byID = Dictionary(messages.map { ($0.id, $0) }) { first, _ in first }
        func quote(_ id: String?) -> Quote? {
            id.flatMap { byID[$0] }.map { Quote(messageID: $0.id, text: $0.text, employeeID: $0.employeeID) }
        }
        // A reply to the message right above it needs no quote; the order already says it.
        var entries: [(date: Date?, item: Item)] = messages.enumerated().map { index, message in
            if message.isEvent {
                return (message.date, .event(Event(id: message.id, text: message.text, ref: message.ref)))
            }
            return (message.date, .bubble(Bubble(
                id: message.id,
                employeeID: message.employeeID,
                isOwner: message.employeeID == nil,
                text: message.text,
                quote: index > 0 && messages[index - 1].id == message.replyTo ? nil : quote(message.replyTo),
                viaVoice: message.viaVoice,
                reactions: message.reactions,
                sentAt: message.date,
                ref: message.ref,
                position: .single
            )))
        }
        entries += pending.map { message in
            (now, .bubble(Bubble(
                id: message.id,
                employeeID: nil,
                isOwner: true,
                text: message.text,
                quote: quote(message.replyTo),
                viaVoice: message.viaVoice,
                reactions: [],
                sentAt: now,
                position: .single,
                delivery: message.delivery
            )))
        }
        items = Self.layout(entries, calendar: calendar)
    }

    private static func layout(_ entries: [(date: Date?, item: Item)], calendar: Calendar) -> [Item] {
        var items: [Item] = []
        var previousDate: Date?
        var previous: Bubble?
        for (date, item) in entries {
            let gap = both(previousDate, date).map { $1.timeIntervalSince($0) }
            let newDay = both(previousDate, date).map { !calendar.isDate($0, inSameDayAs: $1) } ?? false
            if let date, previousDate == nil || newDay || (gap ?? 0) > headingGap {
                items.append(.heading(date))
                previous = nil
            }
            if let date { previousDate = date }
            guard case .bubble(var bubble) = item else {
                items.append(item)
                previous = nil
                continue
            }
            let continues = previous.map {
                $0.isOwner == bubble.isOwner && $0.employeeID == bubble.employeeID && (gap ?? 0) <= groupGap
            } ?? false
            if continues, case .bubble(var last) = items.last {
                last.position = last.position == .single ? .first : .middle
                items[items.count - 1] = .bubble(last)
                bubble.position = .last
            }
            items.append(.bubble(bubble))
            previous = bubble
        }
        return items
    }
}

private func both<A, B>(_ first: A?, _ second: B?) -> (A, B)? {
    guard let first, let second else { return nil }
    return (first, second)
}
