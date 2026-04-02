// CodexThread.swift
// Thread model for Codex conversations.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Represents a conversation thread from Codex.
public struct CodexThread: Identifiable, Codable, Sendable, Equatable {
    public let id: String

    /// Creates a Thread from Codex JSON response.
    init(from json: [String: Any]) {
        self.id = json["id"] as? String ?? UUID().uuidString
    }
}

// MARK: - Approval Request

/// A request for user approval before executing a command.
struct ApprovalRequest: Identifiable, Codable, Sendable {
    /// JSON-RPC request ID (used to respond)
    let id: Int

    let itemId: String
    let kind: ApprovalKind
    let command: String?
    let cwd: String?
    let reason: String?

    enum ApprovalKind: String, Codable, Sendable {
        case commandExecution
        case fileChange
        case tool
        case unknown
    }

    /// Creates from Codex JSON-RPC params.
    init(from params: [String: Any], requestId: Int, kind: ApprovalKind = .unknown) {
        self.id = requestId
        self.itemId = params["itemId"] as? String ?? ""
        self.kind = kind
        self.command = params["command"] as? String
        self.cwd = params["cwd"] as? String
        self.reason = params["reason"] as? String
    }
}

/// User's decision on an approval request.
enum ApprovalDecision: String, Codable, Sendable {
    case accept
    case decline
}
