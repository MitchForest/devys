// ActiveHarness.swift
// Runtime wrapper around concrete harness clients.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Runtime wrapper that holds the active harness client.
///
/// This enum provides a type-safe way to work with either Codex or Claude Code
/// clients without exposing the concrete types everywhere.
@MainActor
enum ActiveHarness {
    case codex(CodexClient)
    case claudeCode(ClaudeCodeClient)

    var type: HarnessType {
        switch self {
        case .codex: return .codex
        case .claudeCode: return .claudeCode
        }
    }

    func stop() async {
        switch self {
        case .codex(let client):
            await client.stop()
        case .claudeCode(let client):
            await client.stop()
        }
    }
}
