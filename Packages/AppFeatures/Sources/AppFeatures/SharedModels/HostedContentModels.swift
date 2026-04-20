import ACPClientKit
import Foundation

public struct HostedEditorDocumentSummary: Equatable, Sendable, Identifiable {
    public var url: URL
    public var title: String
    public var isDirty: Bool
    public var isLoading: Bool

    public init(
        url: URL,
        title: String,
        isDirty: Bool,
        isLoading: Bool
    ) {
        self.url = url.standardizedFileURL
        self.title = title
        self.isDirty = isDirty
        self.isLoading = isLoading
    }

    public var id: String {
        url.absoluteString
    }
}

public struct HostedChatSessionSummary: Equatable, Sendable, Identifiable {
    public var sessionID: ChatSessionID
    public var kind: ACPAgentKind
    public var title: String
    public var icon: String
    public var subtitle: String?
    public var isBusy: Bool
    public var isRestorable: Bool
    public var createdAt: Date
    public var lastActivityAt: Date

    public init(
        sessionID: ChatSessionID,
        kind: ACPAgentKind,
        title: String,
        icon: String,
        subtitle: String? = nil,
        isBusy: Bool,
        isRestorable: Bool,
        createdAt: Date,
        lastActivityAt: Date
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.isBusy = isBusy
        self.isRestorable = isRestorable
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
    }

    public var id: String {
        sessionID.rawValue
    }

    public var tabTitle: String {
        title
    }

    public var tabIcon: String {
        icon
    }

    public var tabIsBusy: Bool {
        isBusy
    }

    public var stateSummary: String {
        if let subtitle, !subtitle.isEmpty {
            return subtitle
        }
        return isBusy ? "Busy" : "Idle"
    }
}

public struct HostedBrowserSessionSummary: Equatable, Sendable, Identifiable {
    public var sessionID: UUID
    public var url: URL
    public var title: String
    public var icon: String

    public init(
        sessionID: UUID,
        url: URL,
        title: String,
        icon: String
    ) {
        self.sessionID = sessionID
        self.url = url
        self.title = title
        self.icon = icon
    }

    public var id: UUID {
        sessionID
    }
}

public struct HostedWorkspaceContentState: Equatable, Sendable {
    public var editorDocuments: [HostedEditorDocumentSummary]
    public var browserSessions: [HostedBrowserSessionSummary]
    public var chatSessions: [HostedChatSessionSummary]

    public init(
        editorDocuments: [HostedEditorDocumentSummary] = [],
        browserSessions: [HostedBrowserSessionSummary] = [],
        chatSessions: [HostedChatSessionSummary] = []
    ) {
        self.editorDocuments = editorDocuments
        self.browserSessions = browserSessions
        self.chatSessions = chatSessions
    }

    public var dirtyEditorCount: Int {
        editorDocuments.filter(\.isDirty).count
    }
}
