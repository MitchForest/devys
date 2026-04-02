// ToolCatalog.swift
// Maps tool names to structured metadata for display.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Centralized catalog of tool name → display metadata.
///
/// This covers all tools emitted by Claude Code and Codex CLIs.
/// Kept in sync with Zed's `claude-code-acp/src/tools.ts` mappings.
///
/// Last synced: 2026-02-06 (claude-code-acp v0.15.0, codex-acp v0.9.2)
public enum ToolCatalog {

    /// Structured metadata about a tool call.
    public struct ToolInfo: Equatable, Sendable {
        public let title: String
        public let kind: ToolKind
        public let locations: [FileLocation]

        public struct FileLocation: Equatable, Sendable {
            public let path: String
            public let line: Int?
        }
    }

    // MARK: - Complete tool name set (for sync checks)

    /// All Claude Code tool names tracked by Zed's adapter (as of v0.15.0).
    public static let claudeCodeToolNames: Set<String> = [
        "Read", "Write", "Edit", "Bash", "BashOutput", "KillShell",
        "Glob", "Grep", "LS", "WebFetch", "WebSearch", "Task",
        "TodoWrite", "NotebookEdit", "NotebookRead", "ExitPlanMode",
    ]

    /// All Codex item types we track.
    public static let codexItemTypes: Set<String> = [
        "commandexecution", "filechange", "patch", "mcptoolcall",
        "websearch", "todolist", "planimplementation", "plan",
        "diff", "agentmessage", "reasoning",
    ]

    /// Tool names we handle in Devys.
    public static let handledToolNames: Set<String> = [
        "Read", "Write", "Edit", "Bash", "BashOutput", "KillShell",
        "Glob", "Grep", "LS", "WebFetch", "WebSearch", "Task",
        "TodoWrite", "NotebookEdit", "NotebookRead", "ExitPlanMode",
        // Codex item types (normalized to lowercase for matching)
        "commandexecution", "filechange", "mcptoolcall", "websearch",
        "todolist", "plan", "diff",
    ]

    /// Tool names in Zed's catalog that we DON'T yet handle.
    public static var gapsVsZed: Set<String> {
        claudeCodeToolNames.subtracting(handledToolNames)
    }

    // MARK: - Lookup

    /// Returns display metadata for a Claude Code tool call.
    ///
    /// - Parameters:
    ///   - name: The tool name from the `tool_use` event (e.g. "Edit", "Bash").
    ///   - input: The raw input dictionary from the tool call.
    /// - Returns: Structured metadata for UI display.
    public static func info(forClaudeTool name: String, input: [String: Any]? = nil) -> ToolInfo {
        let input = input ?? [:]
        if let info = staticClaudeToolInfo[name] {
            return info
        }
        return dynamicClaudeToolInfo(name: name, input: input)
    }

    private static let staticClaudeToolInfo: [String: ToolInfo] = [
        "BashOutput": ToolInfo(title: "Tail Logs", kind: .execute, locations: []),
        "KillShell": ToolInfo(title: "Kill Process", kind: .execute, locations: []),
        "TodoWrite": ToolInfo(title: "Update TODOs", kind: .think, locations: []),
        "ExitPlanMode": ToolInfo(title: "Ready to code?", kind: .switchMode, locations: []),
    ]

    private typealias ClaudeToolBuilder = @Sendable ([String: Any]) -> ToolInfo

    private static let claudeToolBuilders: [String: ClaudeToolBuilder] = [
        "Read": buildReadInfo,
        "Write": { buildWriteEditInfo(name: "Write", input: $0) },
        "Edit": { buildWriteEditInfo(name: "Edit", input: $0) },
        "Bash": buildBashInfo,
        "Glob": buildGlobInfo,
        "Grep": buildGrepInfo,
        "LS": buildListInfo,
        "WebFetch": buildWebFetchInfo,
        "WebSearch": buildWebSearchInfo,
        "Task": buildTaskInfo,
        "NotebookEdit": buildNotebookEditInfo,
        "NotebookRead": buildNotebookReadInfo,
    ]

    private static func dynamicClaudeToolInfo(name: String, input: [String: Any]) -> ToolInfo {
        if let builder = claudeToolBuilders[name] {
            return builder(input)
        }
        return ToolInfo(title: name.isEmpty ? "Unknown Tool" : name, kind: .other, locations: [])
    }

    private static func buildReadInfo(input: [String: Any]) -> ToolInfo {
        let filePath = input["file_path"] as? String
        let offset = input["offset"] as? Int
        let limit = input["limit"] as? Int
        let suffix = readSuffix(offset: offset, limit: limit)

        return ToolInfo(
            title: "Read \(filePath ?? "File")\(suffix)",
            kind: .read,
            locations: filePath.map { [.init(path: $0, line: offset)] } ?? []
        )
    }

    private static func readSuffix(offset: Int?, limit: Int?) -> String {
        if let limit {
            let start = (offset ?? 0) + 1
            return " (\(start)-\(start + limit - 1))"
        }
        if let offset, offset > 0 {
            return " (from line \(offset + 1))"
        }
        return ""
    }

    private static func buildWriteEditInfo(name: String, input: [String: Any]) -> ToolInfo {
        let filePath = input["file_path"] as? String
        let verb = name == "Write" ? "Write" : "Edit"
        return ToolInfo(
            title: filePath.map { "\(verb) \($0)" } ?? "\(verb) File",
            kind: .edit,
            locations: filePath.map { [.init(path: $0, line: nil)] } ?? []
        )
    }

    private static func buildBashInfo(input: [String: Any]) -> ToolInfo {
        let command = input["command"] as? String
        let title = command.map { "`\($0.replacingOccurrences(of: "`", with: "\\`"))`" } ?? "Terminal"
        return ToolInfo(title: title, kind: .execute, locations: [])
    }

    private static func buildGlobInfo(input: [String: Any]) -> ToolInfo {
        var label = "Find"
        if let path = input["path"] as? String { label += " `\(path)`" }
        if let pattern = input["pattern"] as? String { label += " `\(pattern)`" }
        return ToolInfo(
            title: label,
            kind: .search,
            locations: (input["path"] as? String).map { [.init(path: $0, line: nil)] } ?? []
        )
    }

    private static func buildGrepInfo(input: [String: Any]) -> ToolInfo {
        var label = "grep"
        if let pattern = input["pattern"] as? String { label += " \"\(pattern)\"" }
        if let path = input["path"] as? String { label += " \(path)" }
        return ToolInfo(title: label, kind: .search, locations: [])
    }

    private static func buildListInfo(input: [String: Any]) -> ToolInfo {
        let path = input["path"] as? String
        return ToolInfo(
            title: "List \(path.map { "`\($0)`" } ?? "directory") contents",
            kind: .search,
            locations: []
        )
    }

    private static func buildWebFetchInfo(input: [String: Any]) -> ToolInfo {
        let url = input["url"] as? String
        return ToolInfo(
            title: url.map { "Fetch \($0)" } ?? "Fetch",
            kind: .fetch,
            locations: []
        )
    }

    private static func buildWebSearchInfo(input: [String: Any]) -> ToolInfo {
        let query = input["query"] as? String ?? "web"
        return ToolInfo(title: "\"\(query)\"", kind: .fetch, locations: [])
    }

    private static func buildTaskInfo(input: [String: Any]) -> ToolInfo {
        let desc = input["description"] as? String
        return ToolInfo(title: desc ?? "Task", kind: .think, locations: [])
    }

    private static func buildNotebookEditInfo(input: [String: Any]) -> ToolInfo {
        let path = input["notebook_path"] as? String
        return ToolInfo(
            title: path.map { "Edit Notebook \($0)" } ?? "Edit Notebook",
            kind: .edit,
            locations: path.map { [.init(path: $0, line: nil)] } ?? []
        )
    }

    private static func buildNotebookReadInfo(input: [String: Any]) -> ToolInfo {
        let path = input["notebook_path"] as? String
        return ToolInfo(
            title: path.map { "Read Notebook \($0)" } ?? "Read Notebook",
            kind: .read,
            locations: path.map { [.init(path: $0, line: nil)] } ?? []
        )
    }

    /// Returns display metadata for a Codex item type.
    ///
    /// - Parameters:
    ///   - type: The item type from `item/started` (e.g. "commandExecution").
    ///   - payload: The raw item payload dictionary.
    /// - Returns: Structured metadata for UI display.
    public static func info(forCodexItem type: String, payload: [String: Any]? = nil) -> ToolInfo {
        let payload = payload ?? [:]
        let normalized = type.lowercased().replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        let isKnownCodexType = codexItemTypes.contains(normalized)

        switch normalized {
        case "commandexecution":
            let command = payload["command"] as? String
            return ToolInfo(
                title: command.map { "`\($0)`" } ?? "Command",
                kind: .execute,
                locations: []
            )

        case "filechange", "patch":
            let title = payload["title"] as? String ?? "File Changes"
            return ToolInfo(title: title, kind: .edit, locations: [])

        case "mcptoolcall":
            let tool = payload["toolName"] as? String ?? payload["tool"] as? String ?? "MCP Tool"
            return ToolInfo(title: "MCP: \(tool)", kind: .other, locations: [])

        case "websearch":
            let query = payload["query"] as? String ?? payload["search"] as? String ?? "web"
            return ToolInfo(title: "\"\(query)\"", kind: .fetch, locations: [])

        case "todolist":
            return ToolInfo(title: "TODO List", kind: .think, locations: [])

        case "planimplementation", "plan":
            let title = payload["title"] as? String ?? "Implementation Plan"
            return ToolInfo(title: title, kind: .think, locations: [])

        case "diff":
            let title = payload["title"] as? String ?? "Diff"
            return ToolInfo(title: title, kind: .edit, locations: [])

        case "agentmessage":
            return ToolInfo(title: "Message", kind: .other, locations: [])

        case "reasoning":
            return ToolInfo(title: "Reasoning", kind: .think, locations: [])

        default:
            let fallbackTitle = isKnownCodexType
                ? "Unhandled \(type)"
                : (type.isEmpty ? "Unknown" : type)
            return ToolInfo(title: fallbackTitle, kind: .other, locations: [])
        }
    }
}
