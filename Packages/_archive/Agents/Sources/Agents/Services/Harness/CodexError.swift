// CodexError.swift
// Errors for Codex client integration.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

enum CodexError: Error, LocalizedError {
    case binaryNotFound
    case alreadyRunning
    case notReady
    case processStartFailed(String)
    case rpcError(code: Int, message: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Codex CLI not found. Install from: https://github.com/openai/codex"
        case .alreadyRunning:
            return "Codex is already running"
        case .notReady:
            return "Codex is not ready"
        case .processStartFailed(let msg):
            return "Failed to start Codex: \(msg)"
        case .rpcError(let code, let message):
            return "Codex error (\(code)): \(message)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        }
    }
}
