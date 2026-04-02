// ChatItemBlock.swift
// Structured attachments/blocks for chat rendering.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// A tool call for display in chat and for event translation.
public struct ToolCallDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var title: String?
    public var input: String
    public var output: String
    public var status: Status
    public var isExpanded: Bool
    public var cwd: String?
    public var exitCode: Int?
    public var isError: Bool
    public var structuredOutput: String?
    public var approval: AgentApproval?
    public var kind: ToolKind
    public var locations: [ToolCatalog.ToolInfo.FileLocation]

    public enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    public init(
        id: String,
        name: String,
        title: String? = nil,
        input: String = "",
        output: String = "",
        status: Status = .running,
        isExpanded: Bool = true,
        cwd: String? = nil,
        exitCode: Int? = nil,
        isError: Bool = false,
        structuredOutput: String? = nil,
        approval: AgentApproval? = nil,
        kind: ToolKind = .other,
        locations: [ToolCatalog.ToolInfo.FileLocation] = []
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.input = input
        self.output = output
        self.status = status
        self.isExpanded = isExpanded
        self.cwd = cwd
        self.exitCode = exitCode
        self.isError = isError
        self.structuredOutput = structuredOutput
        self.approval = approval
        self.kind = kind
        self.locations = locations
    }
}

/// Structured blocks attached to a chat message (diffs, plans, todo lists, etc.).
public enum ChatItemBlock: Identifiable, Equatable, Sendable {
    case tool(ToolCallDisplay)
    case diff(DiffBlock)
    case patch(PatchBlock)
    case mcpTool(MCPToolBlock)
    case webSearch(WebSearchBlock)
    case todoList(TodoListBlock)
    case plan(PlanBlock)
    case userInput(UserInputBlock)
    case reasoning(ReasoningBlock)
    case systemStatus(SystemStatusBlock)

    public var id: String {
        switch self {
        case .tool(let block):
            return block.id
        case .diff(let block):
            return block.id
        case .patch(let block):
            return block.id
        case .mcpTool(let block):
            return block.id
        case .webSearch(let block):
            return block.id
        case .todoList(let block):
            return block.id
        case .plan(let block):
            return block.id
        case .userInput(let block):
            return block.id
        case .reasoning(let block):
            return block.id
        case .systemStatus(let block):
            return block.id
        }
    }
}

// MARK: - Diff / Patch

public struct DiffBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var diff: String
    public var filePath: String?
    public var isTruncated: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        diff: String,
        filePath: String? = nil,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = title
        self.diff = diff
        self.filePath = filePath
        self.isTruncated = isTruncated
    }
}

public struct PatchBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var summary: String?
    public var files: [PatchFileChange]
    public var status: PatchStatus
    public var approval: AgentApproval?

    public enum PatchStatus: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        summary: String? = nil,
        files: [PatchFileChange] = [],
        status: PatchStatus = .running,
        approval: AgentApproval? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.files = files
        self.status = status
        self.approval = approval
    }
}

public struct PatchFileChange: Identifiable, Equatable, Sendable {
    public let id: String
    public var path: String
    public var status: String
    public var additions: Int
    public var deletions: Int
    public var diff: String?

    public init(
        id: String = UUID().uuidString,
        path: String,
        status: String,
        additions: Int = 0,
        deletions: Int = 0,
        diff: String? = nil
    ) {
        self.id = id
        self.path = path
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.diff = diff
    }
}

// MARK: - MCP Tool

public struct MCPToolBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var server: String
    public var tool: String
    public var input: String
    public var output: String
    public var isError: Bool

    public init(
        id: String = UUID().uuidString,
        server: String,
        tool: String,
        input: String = "",
        output: String = "",
        isError: Bool = false
    ) {
        self.id = id
        self.server = server
        self.tool = tool
        self.input = input
        self.output = output
        self.isError = isError
    }
}

// MARK: - Web Search

public struct WebSearchBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var query: String
    public var status: WebSearchStatus
    public var summary: String

    public enum WebSearchStatus: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    public init(
        id: String = UUID().uuidString,
        query: String,
        status: WebSearchStatus = .running,
        summary: String = ""
    ) {
        self.id = id
        self.query = query
        self.status = status
        self.summary = summary
    }
}

// MARK: - Todo / Plan

public struct TodoListBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var items: [TodoItem]

    public init(
        id: String = UUID().uuidString,
        title: String,
        items: [TodoItem] = []
    ) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct TodoItem: Identifiable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var isComplete: Bool

    public init(
        id: String = UUID().uuidString,
        text: String,
        isComplete: Bool = false
    ) {
        self.id = id
        self.text = text
        self.isComplete = isComplete
    }
}

public struct PlanBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var steps: [PlanStep]
    public var status: PlanStatus

    public enum PlanStatus: String, Codable, Sendable {
        case proposed
        case inProgress
        case completed
        case rejected
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        steps: [PlanStep] = [],
        status: PlanStatus = .proposed
    ) {
        self.id = id
        self.title = title
        self.steps = steps
        self.status = status
    }
}

public struct PlanStep: Identifiable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var isComplete: Bool

    public init(
        id: String = UUID().uuidString,
        text: String,
        isComplete: Bool = false
    ) {
        self.id = id
        self.text = text
        self.isComplete = isComplete
    }
}

// MARK: - User Input

public struct UserInputBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var questions: [UserQuestion]
    public var answers: [String]
    public var status: UserInputStatus

    public enum UserInputStatus: String, Codable, Sendable {
        case pending
        case answered
        case cancelled
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        questions: [UserQuestion] = [],
        answers: [String] = [],
        status: UserInputStatus = .pending
    ) {
        self.id = id
        self.title = title
        self.questions = questions
        self.answers = answers
        self.status = status
    }
}

public struct UserQuestion: Identifiable, Equatable, Sendable {
    public let id: String
    public var question: String
    public var options: [String]
    public var allowFreeform: Bool

    public init(
        id: String = UUID().uuidString,
        question: String,
        options: [String] = [],
        allowFreeform: Bool = true
    ) {
        self.id = id
        self.question = question
        self.options = options
        self.allowFreeform = allowFreeform
    }
}

// MARK: - Reasoning

public struct ReasoningBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var text: String
    public var isStreaming: Bool

    public init(
        id: String = UUID().uuidString,
        text: String,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.text = text
        self.isStreaming = isStreaming
    }
}

// MARK: - System Status

public struct SystemStatusBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var detail: String
    public var level: StatusLevel

    public enum StatusLevel: String, Codable, Sendable {
        case info
        case warning
        case error
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        detail: String,
        level: StatusLevel = .info
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.level = level
    }
}
