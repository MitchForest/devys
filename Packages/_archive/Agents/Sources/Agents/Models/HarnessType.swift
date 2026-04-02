// HarnessType.swift
// Supported agent harnesses.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Available agent harnesses (CLI runtimes).
public enum HarnessType: String, CaseIterable, Codable, Sendable, Identifiable {
    case codex = "codex"
    case claudeCode = "claude-code"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: return "OpenAI Codex"
        case .claudeCode: return "Claude Code"
        }
    }

    public var shortName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude"
        }
    }

    public var defaultModel: LLMModel {
        switch self {
        case .codex: return .codex52
        case .claudeCode: return .claudeOpus45
        }
    }

    /// Icon name for this harness.
    public var iconName: String {
        switch self {
        case .codex: return "circle.square.fill"
        case .claudeCode: return "arrowtriangle.up.square.fill"
        }
    }

    public var supportsSkills: Bool { self == .codex }

    var binaryPaths: [String] {
        switch self {
        case .codex:
            return [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path
            ]
        case .claudeCode:
            return [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/local/claude").path,
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
            ]
        }
    }

    public func isAvailable() -> Bool {
        if binaryPaths.contains(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return true
        }

        // Try `which` as fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [self == .codex ? "codex" : "claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
