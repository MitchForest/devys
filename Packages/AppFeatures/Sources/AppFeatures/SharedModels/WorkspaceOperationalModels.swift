// swiftlint:disable file_length
import Foundation
import Git
import Workspace

public struct WorktreeInfoEntry: Equatable, Sendable {
    public var refreshToken: UUID?
    public var isRepositoryAvailable: Bool
    public var branchName: String?
    public var repositoryInfo: GitRepositoryInfo?
    public var lineChanges: WorktreeLineChanges?
    public var statusSummary: WorktreeStatusSummary?
    public var changes: [GitFileChange]
    public var isLoading: Bool
    public var errorMessage: String?
    public var pullRequest: PullRequest?

    public init(
        refreshToken: UUID? = nil,
        isRepositoryAvailable: Bool = false,
        branchName: String? = nil,
        repositoryInfo: GitRepositoryInfo? = nil,
        lineChanges: WorktreeLineChanges? = nil,
        statusSummary: WorktreeStatusSummary? = nil,
        changes: [GitFileChange] = [],
        isLoading: Bool = false,
        errorMessage: String? = nil,
        pullRequest: PullRequest? = nil
    ) {
        self.refreshToken = refreshToken
        self.isRepositoryAvailable = isRepositoryAvailable
        self.branchName = branchName
        self.repositoryInfo = repositoryInfo
        self.lineChanges = lineChanges
        self.statusSummary = statusSummary
        self.changes = changes
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.pullRequest = pullRequest
    }

    public var hasChanges: Bool {
        !changes.isEmpty
    }

    public var stagedChanges: [GitFileChange] {
        changes.filter(\.isStaged)
    }

    public var unstagedChanges: [GitFileChange] {
        changes.filter {
            !$0.isStaged &&
            $0.status != .untracked &&
            $0.status != .ignored
        }
    }

    public var untrackedChanges: [GitFileChange] {
        changes.filter { !$0.isStaged && $0.status == .untracked }
    }

    public var ignoredChanges: [GitFileChange] {
        changes.filter { !$0.isStaged && $0.status == .ignored }
    }

    public var changeCount: Int {
        changes.count
    }
}

public enum WorkspacePortOwnership: String, Equatable, Sendable, Codable {
    case owned
    case conflicted
}

public struct WorkspacePort: Identifiable, Equatable, Sendable {
    public let workspaceID: Workspace.ID
    public let port: Int
    public let processIDs: [Int32]
    public let processNames: [String]
    public let ownership: WorkspacePortOwnership

    public init(
        workspaceID: Workspace.ID,
        port: Int,
        processIDs: [Int32],
        processNames: [String],
        ownership: WorkspacePortOwnership
    ) {
        self.workspaceID = workspaceID
        self.port = port
        self.processIDs = processIDs
        self.processNames = processNames
        self.ownership = ownership
    }

    public var id: String {
        "\(workspaceID):\(port)"
    }
}

public struct WorkspacePortSummary: Equatable, Sendable {
    public let totalCount: Int
    public let conflictCount: Int

    public init(
        totalCount: Int,
        conflictCount: Int
    ) {
        self.totalCount = totalCount
        self.conflictCount = conflictCount
    }

    public var hasPorts: Bool {
        totalCount > 0
    }

    public var hasConflicts: Bool {
        conflictCount > 0
    }
}

public struct ManagedWorkspaceProcess: Equatable, Sendable {
    public let processID: Int32
    public let displayName: String

    public init(
        processID: Int32,
        displayName: String
    ) {
        self.processID = processID
        self.displayName = displayName
    }
}

public enum WorkspaceAttentionSource: String, Codable, CaseIterable, Sendable {
    case terminal
    case claude
    case codex
    case run
    case build

    public var displayName: String {
        switch self {
        case .terminal:
            return "Shell"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .run:
            return "Run"
        case .build:
            return "Build"
        }
    }
}

public enum WorkspaceAttentionKind: String, Codable, Sendable {
    case unread
    case waiting
    case completed
}

public struct WorkspaceAttentionNotification: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let workspaceID: Workspace.ID
    public let source: WorkspaceAttentionSource
    public let kind: WorkspaceAttentionKind
    public let terminalID: UUID?
    public var title: String
    public var subtitle: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        kind: WorkspaceAttentionKind,
        terminalID: UUID? = nil,
        title: String,
        subtitle: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.source = source
        self.kind = kind
        self.terminalID = terminalID
        self.title = title
        self.subtitle = subtitle
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

public struct WorkspaceAttentionSummary: Equatable, Sendable {
    public let unreadCount: Int
    public let waitingCount: Int
    public let latestWaitingSource: WorkspaceAttentionSource?

    public init(
        unreadCount: Int,
        waitingCount: Int,
        latestWaitingSource: WorkspaceAttentionSource?
    ) {
        self.unreadCount = unreadCount
        self.waitingCount = waitingCount
        self.latestWaitingSource = latestWaitingSource
    }

    public var hasAttention: Bool {
        unreadCount > 0
    }
}

public struct WorkspaceAttentionIngressPayload: Codable, Equatable, Sendable {
    public let workspaceID: Workspace.ID
    public let source: WorkspaceAttentionSource
    public let kind: WorkspaceAttentionKind
    public let terminalID: UUID?
    public let title: String
    public let subtitle: String?

    public init(
        workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        kind: WorkspaceAttentionKind,
        terminalID: UUID?,
        title: String,
        subtitle: String?
    ) {
        self.workspaceID = workspaceID
        self.source = source
        self.kind = kind
        self.terminalID = terminalID
        self.title = title
        self.subtitle = subtitle
    }
}

public struct WorkspaceRunState: Equatable, Sendable {
    public var profileID: StartupProfile.ID
    public var terminalIDs: Set<UUID>
    public var backgroundProcessIDs: Set<UUID>

    public init(
        profileID: StartupProfile.ID,
        terminalIDs: Set<UUID> = [],
        backgroundProcessIDs: Set<UUID> = []
    ) {
        self.profileID = profileID
        self.terminalIDs = terminalIDs
        self.backgroundProcessIDs = backgroundProcessIDs
    }

    public var isRunning: Bool {
        !terminalIDs.isEmpty || !backgroundProcessIDs.isEmpty
    }
}

public struct WorkspaceOperationalCatalogContext: Equatable, Sendable {
    public var repositories: [Repository]
    public var worktreesByRepository: [Repository.ID: [Worktree]]
    public var selectedRepositoryID: Repository.ID?
    public var selectedWorkspaceID: Workspace.ID?

    public init(
        repositories: [Repository] = [],
        worktreesByRepository: [Repository.ID: [Worktree]] = [:],
        selectedRepositoryID: Repository.ID? = nil,
        selectedWorkspaceID: Workspace.ID? = nil
    ) {
        self.repositories = repositories
        self.worktreesByRepository = worktreesByRepository
        self.selectedRepositoryID = selectedRepositoryID
        self.selectedWorkspaceID = selectedWorkspaceID
    }
}

public struct WorkspaceOperationalSnapshot: Equatable, Sendable {
    public var metadataEntriesByWorkspaceID: [Workspace.ID: WorktreeInfoEntry]
    public var portsByWorkspaceID: [Workspace.ID: [WorkspacePort]]
    public var portSummariesByWorkspaceID: [Workspace.ID: WorkspacePortSummary]
    public var unreadTerminalIDsByWorkspaceID: [Workspace.ID: Set<UUID>]

    public init(
        metadataEntriesByWorkspaceID: [Workspace.ID: WorktreeInfoEntry] = [:],
        portsByWorkspaceID: [Workspace.ID: [WorkspacePort]] = [:],
        portSummariesByWorkspaceID: [Workspace.ID: WorkspacePortSummary] = [:],
        unreadTerminalIDsByWorkspaceID: [Workspace.ID: Set<UUID>] = [:]
    ) {
        self.metadataEntriesByWorkspaceID = metadataEntriesByWorkspaceID
        self.portsByWorkspaceID = portsByWorkspaceID
        self.portSummariesByWorkspaceID = portSummariesByWorkspaceID
        self.unreadTerminalIDsByWorkspaceID = unreadTerminalIDsByWorkspaceID
    }
}

// swiftlint:disable:next type_body_length
public struct WorkspaceOperationalState: Equatable, Sendable {
    public var metadataEntriesByWorkspaceID: [Workspace.ID: WorktreeInfoEntry] = [:]
    public var portsByWorkspaceID: [Workspace.ID: [WorkspacePort]] = [:]
    public var portSummariesByWorkspaceID: [Workspace.ID: WorkspacePortSummary] = [:]
    public var unreadTerminalIDsByWorkspaceID: [Workspace.ID: Set<UUID>] = [:]
    public var notificationsByWorkspaceID: [Workspace.ID: [WorkspaceAttentionNotification]] = [:]
    public var runStatesByWorkspaceID: [Workspace.ID: WorkspaceRunState] = [:]

    public init() {}

    public var attentionSummariesByWorkspace: [Workspace.ID: WorkspaceAttentionSummary] {
        notificationsByWorkspaceID.reduce(into: [:]) { partialResult, entry in
            let summary = attentionSummary(for: entry.key)
            if summary.hasAttention {
                partialResult[entry.key] = summary
            }
        }
    }

    public var pendingNotifications: [WorkspaceAttentionNotification] {
        notificationsByWorkspaceID.values
            .flatMap { $0 }
            .sorted(by: notificationSort(lhs:rhs:))
    }

    public func notifications(for workspaceID: Workspace.ID?) -> [WorkspaceAttentionNotification] {
        guard let workspaceID else { return [] }
        return (notificationsByWorkspaceID[workspaceID] ?? [])
            .sorted(by: notificationSort(lhs:rhs:))
    }

    public func attentionSummary(for workspaceID: Workspace.ID) -> WorkspaceAttentionSummary {
        let notifications = notificationsByWorkspaceID[workspaceID] ?? []
        let waiting = notifications.filter { $0.kind == .waiting }
        let latestWaiting = waiting.max { $0.updatedAt < $1.updatedAt }
        return WorkspaceAttentionSummary(
            unreadCount: notifications.count,
            waitingCount: waiting.count,
            latestWaitingSource: latestWaiting?.source
        )
    }

    public func latestUnreadNotification() -> WorkspaceAttentionNotification? {
        pendingNotifications.first
    }

    public mutating func applySnapshot(
        _ snapshot: WorkspaceOperationalSnapshot,
        terminalNotificationsEnabled: Bool,
        now: Date
    ) {
        metadataEntriesByWorkspaceID = snapshot.metadataEntriesByWorkspaceID
        portsByWorkspaceID = snapshot.portsByWorkspaceID
        portSummariesByWorkspaceID = snapshot.portSummariesByWorkspaceID
        unreadTerminalIDsByWorkspaceID = snapshot.unreadTerminalIDsByWorkspaceID
        syncTerminalNotifications(isEnabled: terminalNotificationsEnabled, now: now)
    }

    // swiftlint:disable:next function_body_length
    public mutating func ingest(
        _ payload: WorkspaceAttentionIngressPayload,
        chatNotificationsEnabled: Bool,
        terminalNotificationsEnabled: Bool,
        now: Date
    ) {
        let isEnabled: Bool
        switch payload.source {
        case .terminal:
            isEnabled = terminalNotificationsEnabled
        case .claude, .codex, .run, .build:
            isEnabled = chatNotificationsEnabled
        }
        guard isEnabled else { return }

        switch payload.kind {
        case .waiting:
            recordWaiting(
                in: payload.workspaceID,
                source: payload.source,
                terminalID: payload.terminalID,
                title: payload.title,
                subtitle: payload.subtitle,
                now: now
            )
        case .completed:
            recordCompleted(
                in: payload.workspaceID,
                source: payload.source,
                terminalID: payload.terminalID,
                title: payload.title,
                subtitle: payload.subtitle,
                now: now
            )
        case .unread:
            upsertNotification(
                matching: { notification in
                    notification.source == payload.source
                        && notification.kind == .unread
                        && notification.terminalID == payload.terminalID
                },
                in: payload.workspaceID,
                create: {
                    WorkspaceAttentionNotification(
                        workspaceID: payload.workspaceID,
                        source: payload.source,
                        kind: .unread,
                        terminalID: payload.terminalID,
                        title: payload.title,
                        subtitle: payload.subtitle,
                        createdAt: now
                    )
                },
                update: { notification in
                    notification.title = payload.title
                    notification.subtitle = payload.subtitle
                    notification.updatedAt = now
                }
            )
        }
    }

    public mutating func markTerminalRead(
        _ terminalID: UUID,
        in workspaceID: Workspace.ID?
    ) {
        guard let workspaceID else { return }
        unreadTerminalIDsByWorkspaceID[workspaceID]?.remove(terminalID)
        if unreadTerminalIDsByWorkspaceID[workspaceID]?.isEmpty == true {
            unreadTerminalIDsByWorkspaceID.removeValue(forKey: workspaceID)
        }
        removeNotifications(in: workspaceID) { $0.terminalID == terminalID }
    }

    public mutating func clearNotification(_ notificationID: UUID) {
        for workspaceID in Array(notificationsByWorkspaceID.keys) {
            removeNotifications(in: workspaceID) { $0.id == notificationID }
        }
    }

    public mutating func syncAttentionPreferences(
        terminalNotificationsEnabled: Bool,
        chatNotificationsEnabled: Bool,
        now: Date
    ) {
        syncTerminalNotifications(isEnabled: terminalNotificationsEnabled, now: now)
        if !chatNotificationsEnabled {
            clearNotifications(from: [.claude, .codex, .run, .build])
        }
    }

    public mutating func removeWorkspace(_ workspaceID: Workspace.ID) {
        metadataEntriesByWorkspaceID.removeValue(forKey: workspaceID)
        portsByWorkspaceID.removeValue(forKey: workspaceID)
        portSummariesByWorkspaceID.removeValue(forKey: workspaceID)
        unreadTerminalIDsByWorkspaceID.removeValue(forKey: workspaceID)
        notificationsByWorkspaceID.removeValue(forKey: workspaceID)
        runStatesByWorkspaceID.removeValue(forKey: workspaceID)
    }

    public mutating func setRunState(
        _ runState: WorkspaceRunState?,
        for workspaceID: Workspace.ID
    ) {
        if let runState, runState.isRunning {
            runStatesByWorkspaceID[workspaceID] = runState
        } else {
            runStatesByWorkspaceID.removeValue(forKey: workspaceID)
        }
    }

    public mutating func removeRunTerminal(_ terminalID: UUID) {
        updateRunStatesRemovingResource { state in
            state.terminalIDs.remove(terminalID)
        }
    }

    public mutating func removeRunBackgroundProcess(_ processID: UUID) {
        updateRunStatesRemovingResource { state in
            state.backgroundProcessIDs.remove(processID)
        }
    }

    private mutating func updateRunStatesRemovingResource(
        _ mutation: (inout WorkspaceRunState) -> Void
    ) {
        var nextStates: [Workspace.ID: WorkspaceRunState] = [:]
        for (workspaceID, var state) in runStatesByWorkspaceID {
            mutation(&state)
            if state.isRunning {
                nextStates[workspaceID] = state
            }
        }
        runStatesByWorkspaceID = nextStates
    }

    private mutating func syncTerminalNotifications(
        isEnabled: Bool,
        now: Date
    ) {
        if !isEnabled {
            clearNotifications(from: [.terminal])
            return
        }

        let workspaceIDs = Set(unreadTerminalIDsByWorkspaceID.keys)
        for workspaceID in Array(notificationsByWorkspaceID.keys)
        where !workspaceIDs.contains(workspaceID) {
            removeNotifications(in: workspaceID) { $0.source == .terminal }
        }

        for (workspaceID, unreadTerminalIDs) in unreadTerminalIDsByWorkspaceID {
            removeNotifications(in: workspaceID) { notification in
                guard notification.source == .terminal,
                      notification.kind == .unread,
                      let terminalID = notification.terminalID else {
                    return false
                }
                return !unreadTerminalIDs.contains(terminalID)
            }

            for terminalID in unreadTerminalIDs {
                upsertNotification(
                    matching: { notification in
                        notification.source == .terminal
                            && notification.kind == .unread
                            && notification.terminalID == terminalID
                    },
                    in: workspaceID,
                    create: {
                        WorkspaceAttentionNotification(
                            workspaceID: workspaceID,
                            source: .terminal,
                            kind: .unread,
                            terminalID: terminalID,
                            title: "Terminal needs attention",
                            subtitle: nil,
                            createdAt: now
                        )
                    },
                    update: { notification in
                        notification.updatedAt = now
                    }
                )
            }
        }
    }

    private mutating func recordWaiting(
        in workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        terminalID: UUID?,
        title: String,
        subtitle: String?,
        now: Date
    ) {
        upsertNotification(
            matching: { notification in
                notification.source == source
                    && notification.kind == .waiting
                    && notification.terminalID == terminalID
            },
            in: workspaceID,
            create: {
                WorkspaceAttentionNotification(
                    workspaceID: workspaceID,
                    source: source,
                    kind: .waiting,
                    terminalID: terminalID,
                    title: title,
                    subtitle: subtitle,
                    createdAt: now
                )
            },
            update: { notification in
                notification.title = title
                notification.subtitle = subtitle
                notification.updatedAt = now
            }
        )
    }

    private mutating func recordCompleted(
        in workspaceID: Workspace.ID,
        source: WorkspaceAttentionSource,
        terminalID: UUID?,
        title: String,
        subtitle: String?,
        now: Date
    ) {
        removeNotifications(in: workspaceID) { notification in
            notification.source == source
                && notification.kind == .waiting
                && notification.terminalID == terminalID
        }
        upsertNotification(
            matching: { notification in
                notification.source == source
                    && notification.kind == .completed
                    && notification.terminalID == terminalID
            },
            in: workspaceID,
            create: {
                WorkspaceAttentionNotification(
                    workspaceID: workspaceID,
                    source: source,
                    kind: .completed,
                    terminalID: terminalID,
                    title: title,
                    subtitle: subtitle,
                    createdAt: now
                )
            },
            update: { notification in
                notification.title = title
                notification.subtitle = subtitle
                notification.updatedAt = now
            }
        )
    }

    private mutating func clearNotifications(
        from sources: Set<WorkspaceAttentionSource>
    ) {
        guard !sources.isEmpty else { return }
        for workspaceID in Array(notificationsByWorkspaceID.keys) {
            removeNotifications(in: workspaceID) { sources.contains($0.source) }
        }
    }

    private mutating func upsertNotification(
        matching predicate: (WorkspaceAttentionNotification) -> Bool,
        in workspaceID: Workspace.ID,
        create: () -> WorkspaceAttentionNotification,
        update: (inout WorkspaceAttentionNotification) -> Void
    ) {
        var notifications = notificationsByWorkspaceID[workspaceID] ?? []
        if let index = notifications.firstIndex(where: predicate) {
            update(&notifications[index])
        } else {
            notifications.append(create())
        }
        notificationsByWorkspaceID[workspaceID] = notifications
    }

    private mutating func removeNotifications(
        in workspaceID: Workspace.ID,
        _ shouldRemove: (WorkspaceAttentionNotification) -> Bool
    ) {
        let remainingNotifications = (notificationsByWorkspaceID[workspaceID] ?? [])
            .filter { !shouldRemove($0) }
        if remainingNotifications.isEmpty {
            notificationsByWorkspaceID.removeValue(forKey: workspaceID)
        } else {
            notificationsByWorkspaceID[workspaceID] = remainingNotifications
        }
    }
}

private func notificationSort(
    lhs: WorkspaceAttentionNotification,
    rhs: WorkspaceAttentionNotification
) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
        return lhs.updatedAt > rhs.updatedAt
    }
    return lhs.createdAt > rhs.createdAt
}
