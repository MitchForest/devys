//
//  ToolCall.swift
//  devys
//
//  A tool call from the CLI stream.
//  NOT persisted - parsed from CLI output.
//

import Foundation

/// A tool call made by the agent.
/// Parsed from CLI JSON-RPC events.
struct ToolCall: Identifiable, Hashable {
    let id: String
    let name: String
    let arguments: [String: String]
    var result: String?
    var status: ToolCallStatus
    let timestamp: Date
    
    init(
        id: String = UUID().uuidString,
        name: String,
        arguments: [String: String] = [:],
        result: String? = nil,
        status: ToolCallStatus = .pending,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.result = result
        self.status = status
        self.timestamp = timestamp
    }
    
    /// Icon for this tool type
    var icon: String {
        switch name {
        case "read_file", "read": return "doc.text"
        case "write_file", "write", "edit": return "doc.text.fill"
        case "shell", "bash", "command": return "terminal"
        case "search", "grep": return "magnifyingglass"
        case "list_dir", "ls": return "folder"
        default: return "wrench"
        }
    }
    
    /// Human-readable description
    var displayDescription: String {
        switch name {
        case "read_file", "read":
            return "Read \(arguments["path"] ?? "file")"
        case "write_file", "write":
            return "Write \(arguments["path"] ?? "file")"
        case "shell", "bash", "command":
            let cmd = arguments["command"] ?? ""
            return cmd.count > 40 ? String(cmd.prefix(40)) + "..." : cmd
        case "search", "grep":
            return "Search: \(arguments["pattern"] ?? "...")"
        case "list_dir", "ls":
            return "List \(arguments["path"] ?? ".")"
        case "edit":
            return "Edit \(arguments["path"] ?? "file")"
        default:
            return name
        }
    }
}

// MARK: - Status

enum ToolCallStatus: String, Hashable {
    case pending
    case running
    case completed
    case failed
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}
