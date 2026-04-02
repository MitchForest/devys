import SwiftUI
import UI

enum IOSAssistantMode: String, CaseIterable, Identifiable {
    case calendar
    case gmail
    case gchat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar:
            return "Calendar"
        case .gmail:
            return "Gmail"
        case .gchat:
            return "Google Chat"
        }
    }

    var shortTitle: String {
        switch self {
        case .calendar:
            return "cal"
        case .gmail:
            return "mail"
        case .gchat:
            return "chat"
        }
    }

    var icon: String {
        switch self {
        case .calendar:
            return "calendar"
        case .gmail:
            return "envelope"
        case .gchat:
            return "bubble.left.and.bubble.right"
        }
    }

    var accent: Color {
        switch self {
        case .calendar:
            return DevysColors.success
        case .gmail:
            return AccentColor.coral.color
        case .gchat:
            return AccentColor.cyan.color
        }
    }

    var status: IOSAssistantModeStatus {
        switch self {
        case .calendar:
            return IOSAssistantModeStatus(
                metric: "6m",
                headline: "Brainstorming with Jace",
                detail: "12:40 - 14:10 · 1h 30m"
            )
        case .gmail:
            return IOSAssistantModeStatus(
                metric: "3 unread",
                headline: "2 priority threads need review",
                detail: "Last update · 2m ago"
            )
        case .gchat:
            return IOSAssistantModeStatus(
                metric: "2 mentions",
                headline: "Design team waiting on feedback",
                detail: "1 space active · 5m ago"
            )
        }
    }

    var scopesSummary: String {
        switch self {
        case .calendar:
            return "calendar.readonly"
        case .gmail:
            return "gmail.readonly"
        case .gchat:
            return "chat.spaces.readonly, chat.messages.readonly"
        }
    }

    var emptyStatePrompt: String {
        switch self {
        case .calendar:
            return "Connect Google Calendar to see your schedule."
        case .gmail:
            return "Connect Gmail to see your inbox."
        case .gchat:
            return "Connect Google Chat to see your spaces."
        }
    }

    var noDataLabel: String {
        switch self {
        case .calendar:
            return "Nothing scheduled"
        case .gmail:
            return "Inbox zero"
        case .gchat:
            return "All caught up"
        }
    }

    var events: [IOSAssistantCalendarEvent] {
        [
            IOSAssistantCalendarEvent(title: "Brainstorming with Jace", timeRange: "12:40 - 14:10", duration: "1h 30m"),
            IOSAssistantCalendarEvent(title: "Sprint Planning", timeRange: "15:00 - 16:00", duration: "1h"),
            IOSAssistantCalendarEvent(title: "1:1 with Mitch", timeRange: "17:30 - 18:00", duration: "30m"),
        ]
    }

    var threads: [IOSAssistantMailThread] {
        [
            IOSAssistantMailThread(
                sender: "Sara Kim",
                subject: "Launch copy draft",
                snippet: "Can you review the updated hero and CTA blocks?",
                time: "2m",
                isUnread: true
            ),
            IOSAssistantMailThread(
                sender: "Infra Alerts",
                subject: "Billing threshold reached",
                snippet: "Usage crossed 80% of monthly budget.",
                time: "9m",
                isUnread: true
            ),
            IOSAssistantMailThread(
                sender: "Jason Reed",
                subject: "Design handoff notes",
                snippet: "Uploaded final icon set and motion timings.",
                time: "22m",
                isUnread: false
            ),
        ]
    }

    var spaces: [IOSAssistantChatSpace] {
        [
            IOSAssistantChatSpace(
                name: "product-design",
                preview: "@mitchwhite can you confirm handoff?",
                time: "1m",
                unreadCount: 1
            ),
            IOSAssistantChatSpace(
                name: "engineering",
                preview: "Need quick input on migration order.",
                time: "7m",
                unreadCount: 3
            ),
            IOSAssistantChatSpace(
                name: "ops",
                preview: "No blockers for tonight's rollout.",
                time: "24m",
                unreadCount: 0
            ),
        ]
    }

    var hasData: Bool {
        switch self {
        case .calendar:
            return !events.isEmpty
        case .gmail:
            return !threads.isEmpty
        case .gchat:
            return !spaces.isEmpty
        }
    }
}

enum IOSAssistantCardDensity {
    case compact
    case medium
    case expanded
}

enum IOSAssistantIntegrationStatus: Equatable {
    case connected
    case disconnected
    case error

    var pillText: String {
        switch self {
        case .connected:
            return "connected"
        case .disconnected:
            return "disconnected"
        case .error:
            return "error"
        }
    }
}

struct IOSAssistantModeStatus {
    let metric: String
    let headline: String
    let detail: String
}

struct IOSAssistantCalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let timeRange: String
    let duration: String
}

struct IOSAssistantMailThread: Identifiable {
    let id = UUID()
    let sender: String
    let subject: String
    let snippet: String
    let time: String
    let isUnread: Bool
}

struct IOSAssistantChatSpace: Identifiable {
    let id = UUID()
    let name: String
    let preview: String
    let time: String
    let unreadCount: Int
}

extension Dictionary where Key == IOSAssistantMode, Value == IOSAssistantIntegrationStatus {
    static var assistantDefaults: [IOSAssistantMode: IOSAssistantIntegrationStatus] {
        [
            .calendar: .connected,
            .gmail: .connected,
            .gchat: .disconnected,
        ]
    }
}
