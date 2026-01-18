//
//  Message.swift
//  devys
//
//  A message from the CLI stream.
//  NOT persisted - parsed from CLI output.
//

import Foundation

/// A message in a conversation.
/// Parsed from CLI JSON-RPC events.
struct Message: Identifiable, Hashable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date
    
    /// Tool calls made in this message (assistant only)
    var toolCalls: [ToolCall]
    
    /// File diffs produced (assistant only)
    var diffs: [FileDiff]
    
    /// Reasoning/thinking text (assistant only)
    var reasoning: String?
    
    init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall] = [],
        diffs: [FileDiff] = [],
        reasoning: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.diffs = diffs
        self.reasoning = reasoning
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Message Role

enum MessageRole: String, Codable, Hashable {
    case user
    case assistant
    case system
    
    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Agent"
        case .system: return "System"
        }
    }
    
    var icon: String {
        switch self {
        case .user: return "person.circle.fill"
        case .assistant: return "cpu.fill"
        case .system: return "info.circle.fill"
        }
    }
}
