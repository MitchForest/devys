import Foundation

public enum MessageRole: String, Codable, Sendable, CaseIterable {
    case user
    case assistant
    case system
}

public enum StreamingState: String, Codable, Sendable, CaseIterable {
    case idle
    case streaming
    case complete
    case failed
}

public enum MessageBlockKind: String, Codable, Sendable, CaseIterable {
    case toolCall = "tool.call"
    case patch = "patch"
    case diff = "diff"
    case hunkList = "hunk.list"
    case plan = "plan"
    case todoList = "todo.list"
    case userInputRequest = "user.input.request"
    case reasoning = "reasoning"
    case systemStatus = "system.status"
    case fileSnippet = "file.snippet"
    case gitCommitSummary = "git.commit.summary"
    case pullRequestSummary = "pr.summary"
}

public struct HunkRef: Codable, Sendable, Equatable {
    public enum Action: String, Codable, Sendable, CaseIterable {
        case stage
        case unstage
        case discard
        case applyPatch = "apply.patch"
        case openFullDiff = "open.full.diff"
    }

    public let repoID: String
    public let path: String
    public let staged: Bool
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let header: String
    public let diffText: String
    public let actions: [Action]

    enum CodingKeys: String, CodingKey {
        case repoID = "repoId"
        case path
        case staged
        case oldStart
        case oldCount
        case newStart
        case newCount
        case header
        case diffText
        case actions
    }

    public init(
        repoID: String,
        path: String,
        staged: Bool,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        header: String,
        diffText: String,
        actions: [Action] = Action.allCases
    ) {
        self.repoID = repoID
        self.path = path
        self.staged = staged
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.header = header
        self.diffText = diffText
        self.actions = actions
    }
}

public struct MessageBlock: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: MessageBlockKind
    public let summary: String?
    public let payload: Payload?

    public init(
        id: String = UUID().uuidString,
        kind: MessageBlockKind,
        summary: String? = nil,
        payload: Payload? = nil
    ) {
        self.id = id
        self.kind = kind
        self.summary = summary
        self.payload = payload
    }
}

public struct Message: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let sessionID: String
    public let role: MessageRole
    public let text: String
    public let blocks: [MessageBlock]
    public let streamingState: StreamingState
    public let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "sessionId"
        case role
        case text
        case blocks
        case streamingState
        case timestamp
    }

    public init(
        id: String = UUID().uuidString,
        sessionID: String,
        role: MessageRole,
        text: String,
        blocks: [MessageBlock] = [],
        streamingState: StreamingState = .idle,
        timestamp: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.text = text
        self.blocks = blocks
        self.streamingState = streamingState
        self.timestamp = timestamp
    }
}
