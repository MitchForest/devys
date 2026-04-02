// FixtureLoader.swift
// Loads JSONL fixture files and parses them through the adapters.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
@testable import Agents

/// Loads recorded JSONL fixture files and feeds them through the event parsers.
///
/// Each fixture is a `.jsonl` file where every line is a raw JSON object exactly
/// as the CLI emitted it. The loader parses each line and returns the resulting
/// event arrays for assertion.
enum FixtureLoader {

    /// Root URL for fixture files.
    private static var fixturesURL: URL {
        // Use Bundle.module for SPM test resource access.
        // Falls back to file-relative path for development.
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // Support/
            .deletingLastPathComponent()  // DevysAgentsTests/
            .appendingPathComponent("Fixtures")
    }

    /// Loads raw JSONL lines from a fixture file.
    ///
    /// - Parameters:
    ///   - harness: "claude-code" or "codex"
    ///   - name: Fixture name without extension (e.g. "simple-question")
    static func loadLines(harness: String, name: String) throws -> [String] {
        let url = fixturesURL
            .appendingPathComponent(harness)
            .appendingPathComponent("\(name).jsonl")

        let content = try String(contentsOf: url, encoding: .utf8)
        return content.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Claude Code

    /// Parses raw JSONL lines as Claude Code events.
    static func parseClaudeCodeEvents(_ lines: [String]) -> [[ClaudeCodeEvent]] {
        lines.compactMap { line -> [ClaudeCodeEvent]? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            let events = ClaudeCodeEvent.parseEvents(from: json)
            return events.isEmpty ? nil : events
        }
    }

    /// Parses and converts Claude Code fixture to unified AgentEvents.
    static func claudeCodeAgentEvents(fixture name: String) throws -> [AgentEvent] {
        let lines = try loadLines(harness: "claude-code", name: name)
        return parseClaudeCodeEvents(lines)
            .flatMap { events in events.flatMap { $0.toAgentEvents() } }
    }

    // MARK: - Codex

    /// Parses raw JSONL lines as Codex events.
    static func parseCodexEvents(_ lines: [String]) -> [CodexEvent] {
        lines.compactMap { line -> CodexEvent? in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            let method = json["method"] as? String ?? ""
            let params = json["params"] as? [String: Any] ?? [:]
            let requestId = json["id"] as? Int

            // Skip empty methods (shouldn't happen but defensive)
            guard !method.isEmpty else { return nil }

            return CodexEvent.parse(method: method, params: params, requestId: requestId)
        }
    }

    /// Parses and converts Codex fixture to unified AgentEvents.
    static func codexAgentEvents(fixture name: String) throws -> [AgentEvent] {
        let lines = try loadLines(harness: "codex", name: name)
        return parseCodexEvents(lines).flatMap { $0.toAgentEvents() }
    }

    // MARK: - Inventory

    /// Lists all available fixture names for a harness.
    static func availableFixtures(harness: String) -> [String] {
        let dir = fixturesURL.appendingPathComponent(harness)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
