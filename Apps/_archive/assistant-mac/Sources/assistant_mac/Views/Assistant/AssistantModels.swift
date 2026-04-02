// AssistantModels.swift
// Devys Assistant Phase 1 mock models.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

enum AssistantMode: String, CaseIterable, Identifiable {
    case calendar
    case gmail
    case gchat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Calendar"
        case .gmail: return "Gmail"
        case .gchat: return "Google Chat"
        }
    }

    var shortTitle: String {
        switch self {
        case .calendar: return "calendar"
        case .gmail: return "gmail"
        case .gchat: return "gchat"
        }
    }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .gmail: return "envelope"
        case .gchat: return "bubble.left.and.bubble.right"
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

    var defaultLastSync: String {
        switch self {
        case .calendar:
            return "just now"
        case .gmail:
            return "2m ago"
        case .gchat:
            return "never"
        }
    }

    var accent: Color {
        switch self {
        case .calendar: return DevysColors.success
        case .gmail: return AccentColor.coral.color
        case .gchat: return AccentColor.cyan.color
        }
    }
}

enum AssistantIntegrationStatus: Equatable {
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

enum AssistantCardDensity: Equatable {
    case compact
    case medium
    case expanded
}

struct AssistantModeStatus {
    let metric: String
    let headline: String
    let detail: String
}

struct AssistantCalendarEvent: Identifiable {
    let id = UUID()
    let title: String
    let timeRange: String
    let duration: String
}

struct AssistantMailThread: Identifiable {
    let id = UUID()
    let sender: String
    let subject: String
    let snippet: String
    let time: String
    let isUnread: Bool
}

struct AssistantChatSpace: Identifiable {
    let id = UUID()
    let name: String
    let preview: String
    let time: String
    let unreadCount: Int
}

extension AssistantMode {
    var defaultIntegrationStatus: AssistantIntegrationStatus {
        switch self {
        case .calendar, .gmail:
            return .connected
        case .gchat:
            return .disconnected
        }
    }

    var allCaughtUpLabel: String {
        switch self {
        case .calendar:
            return "Nothing scheduled"
        case .gmail:
            return "Inbox zero"
        case .gchat:
            return "All caught up"
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

    var hasExpandedData: Bool {
        switch self {
        case .calendar:
            return !calendarEvents.isEmpty
        case .gmail:
            return !mailThreads.isEmpty
        case .gchat:
            return !chatSpaces.isEmpty
        }
    }

    var status: AssistantModeStatus {
        switch self {
        case .calendar:
            return AssistantModeStatus(
                metric: "6m",
                headline: "Brainstorming with Jace",
                detail: "12:40 - 14:10 · 1h 30m"
            )
        case .gmail:
            return AssistantModeStatus(
                metric: "3 unread",
                headline: "2 priority threads need review",
                detail: "Last update · 2m ago"
            )
        case .gchat:
            return AssistantModeStatus(
                metric: "2 mentions",
                headline: "Design team is waiting on feedback",
                detail: "1 space active · 5m ago"
            )
        }
    }

    var calendarEvents: [AssistantCalendarEvent] {
        [
            AssistantCalendarEvent(title: "Brainstorming with Jace", timeRange: "12:40 - 14:10", duration: "1h 30m"),
            AssistantCalendarEvent(title: "Sprint Planning", timeRange: "15:00 - 16:00", duration: "1h"),
            AssistantCalendarEvent(title: "1:1 with Mitch", timeRange: "17:30 - 18:00", duration: "30m"),
        ]
    }

    var mailThreads: [AssistantMailThread] {
        [
            AssistantMailThread(
                sender: "Sara Kim",
                subject: "Launch copy draft",
                snippet: "Can you review the updated hero and CTA blocks?",
                time: "2m",
                isUnread: true
            ),
            AssistantMailThread(
                sender: "Infra Alerts",
                subject: "Billing threshold reached",
                snippet: "Usage crossed 80% of monthly budget.",
                time: "9m",
                isUnread: true
            ),
            AssistantMailThread(
                sender: "Jason Reed",
                subject: "Design handoff notes",
                snippet: "Uploaded final icon set and motion timings.",
                time: "22m",
                isUnread: false
            ),
        ]
    }

    var chatSpaces: [AssistantChatSpace] {
        [
            AssistantChatSpace(
                name: "product-design",
                preview: "@mitchwhite can you confirm handoff for today?",
                time: "1m",
                unreadCount: 1
            ),
            AssistantChatSpace(
                name: "engineering",
                preview: "Need quick input on migration order.",
                time: "7m",
                unreadCount: 3
            ),
            AssistantChatSpace(
                name: "ops",
                preview: "No blockers for tonight's rollout.",
                time: "24m",
                unreadCount: 0
            ),
        ]
    }
}

extension Dictionary where Key == AssistantMode, Value == AssistantIntegrationStatus {
    static var assistantDefaults: [AssistantMode: AssistantIntegrationStatus] {
        AssistantMode.allCases.reduce(into: [:]) { map, mode in
            map[mode] = mode.defaultIntegrationStatus
        }
    }
}
