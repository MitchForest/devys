// TerminalNotificationStore.swift
// Devys - Terminal bell notification tracking.

import Foundation
import Observation
import GhosttyTerminal

@MainActor
@Observable
final class TerminalNotificationStore {
    private var lastSeenBellCounts: [UUID: Int] = [:]
    private(set) var unreadTerminalIds: Set<UUID> = []

    func sync(with sessions: [UUID: GhosttyTerminalSession]) {
        let validIds = Set(sessions.keys)
        unreadTerminalIds = unreadTerminalIds.filter { validIds.contains($0) }
        lastSeenBellCounts = lastSeenBellCounts.filter { validIds.contains($0.key) }

        for (id, session) in sessions {
            let current = session.bellCount
            let lastSeen = lastSeenBellCounts[id] ?? 0
            if current > lastSeen {
                unreadTerminalIds.insert(id)
            }
        }
    }

    func markRead(terminalId: UUID, currentBellCount: Int?) {
        let count = currentBellCount ?? lastSeenBellCounts[terminalId] ?? 0
        lastSeenBellCounts[terminalId] = count
        unreadTerminalIds.remove(terminalId)
    }

    func isUnread(_ terminalId: UUID) -> Bool {
        unreadTerminalIds.contains(terminalId)
    }
}
