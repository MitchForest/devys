// WorkspaceAttentionIngress.swift
// Devys - Cross-process workspace attention ingress.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Workspace

struct WorkspaceAttentionIngressPayload: Codable, Equatable, Sendable {
    let workspaceID: Workspace.ID
    let source: WorkspaceAttentionSource
    let kind: WorkspaceAttentionKind
    let terminalID: UUID?
    let title: String
    let subtitle: String?
}

struct WorkspaceAttentionHookInput: Codable, Equatable, Sendable {
    let message: String?
    let title: String?
    let notificationType: String?
    let lastAssistantMessage: String?
    let errorType: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case title
        case notificationType = "notification_type"
        case lastAssistantMessage = "last_assistant_message"
        case errorType = "error_type"
    }
}

enum WorkspaceAttentionIngress {
    static let userInfoPayloadKey = "payload"

    enum Error: LocalizedError {
        case missingWorkspaceID
        case invalidWorkspaceID(String)
        case invalidTerminalID(String)
        case invalidSource(String)
        case invalidKind(String)
        case invalidPayload

        var errorDescription: String? {
            switch self {
            case .missingWorkspaceID:
                return "A workspace ID is required for workspace attention notifications."
            case .invalidWorkspaceID(let value):
                return "Invalid workspace ID: \(value)"
            case .invalidTerminalID(let value):
                return "Invalid terminal ID: \(value)"
            case .invalidSource(let value):
                return "Invalid attention source: \(value)"
            case .invalidKind(let value):
                return "Invalid attention kind: \(value)"
            case .invalidPayload:
                return "Workspace attention payload is missing or malformed."
            }
        }
    }

    static func makePayload(
        workspaceID: String?,
        terminalID: String?,
        source: String,
        kind: String,
        title: String,
        subtitle: String?
    ) throws -> WorkspaceAttentionIngressPayload {
        guard let workspaceID else {
            throw Error.missingWorkspaceID
        }
        guard !workspaceID.isEmpty else {
            throw Error.invalidWorkspaceID(workspaceID)
        }

        guard let decodedSource = WorkspaceAttentionSource(rawValue: source.lowercased()) else {
            throw Error.invalidSource(source)
        }
        guard let decodedKind = WorkspaceAttentionKind(rawValue: kind.lowercased()) else {
            throw Error.invalidKind(kind)
        }

        let decodedTerminalID: UUID?
        if let terminalID, !terminalID.isEmpty {
            guard let value = UUID(uuidString: terminalID) else {
                throw Error.invalidTerminalID(terminalID)
            }
            decodedTerminalID = value
        } else {
            decodedTerminalID = nil
        }

        return WorkspaceAttentionIngressPayload(
            workspaceID: workspaceID,
            source: decodedSource,
            kind: decodedKind,
            terminalID: decodedTerminalID,
            title: title,
            subtitle: subtitle
        )
    }

    static func makePayload(
        fromHookInput data: Data,
        workspaceID: String?,
        terminalID: String?,
        source: String,
        kind: String
    ) throws -> WorkspaceAttentionIngressPayload {
        let decoder = JSONDecoder()
        let hookInput = try decoder.decode(WorkspaceAttentionHookInput.self, from: data)
        return try makePayload(
            workspaceID: workspaceID,
            terminalID: terminalID,
            source: source,
            kind: kind,
            title: title(for: hookInput, source: source, kind: kind),
            subtitle: subtitle(for: hookInput)
        )
    }

    static func encode(_ payload: WorkspaceAttentionIngressPayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let encodedPayload = String(bytes: data, encoding: .utf8) else {
            throw Error.invalidPayload
        }
        return encodedPayload
    }

    static func decode(userInfo: [AnyHashable: Any]?) throws -> WorkspaceAttentionIngressPayload {
        guard let payloadString = userInfo?[userInfoPayloadKey] as? String,
              let data = payloadString.data(using: .utf8)
        else {
            throw Error.invalidPayload
        }
        return try JSONDecoder().decode(WorkspaceAttentionIngressPayload.self, from: data)
    }

    private static func title(
        for hookInput: WorkspaceAttentionHookInput,
        source: String,
        kind: String
    ) -> String {
        let sourceLabel = sourceLabel(for: source)
        if let title = hookInput.title, !title.isEmpty {
            return title
        }
        if let message = hookInput.message, !message.isEmpty {
            return message
        }
        if let message = hookInput.lastAssistantMessage, !message.isEmpty {
            return "\(sourceLabel) completed"
        }
        switch kind.lowercased() {
        case WorkspaceAttentionKind.waiting.rawValue:
            return "\(sourceLabel) needs attention"
        case WorkspaceAttentionKind.completed.rawValue:
            return "\(sourceLabel) completed"
        case WorkspaceAttentionKind.unread.rawValue:
            return "\(sourceLabel) unread"
        default:
            return sourceLabel
        }
    }

    private static func subtitle(for hookInput: WorkspaceAttentionHookInput) -> String? {
        if let notificationType = hookInput.notificationType, !notificationType.isEmpty {
            return notificationType.replacingOccurrences(of: "_", with: " ")
        }
        if let errorType = hookInput.errorType, !errorType.isEmpty {
            return errorType.replacingOccurrences(of: "_", with: " ")
        }
        if let message = hookInput.lastAssistantMessage, !message.isEmpty {
            return message
        }
        return nil
    }

    private static func sourceLabel(for rawValue: String) -> String {
        switch rawValue.lowercased() {
        case WorkspaceAttentionSource.claude.rawValue:
            return "Claude"
        case WorkspaceAttentionSource.codex.rawValue:
            return "Codex"
        case WorkspaceAttentionSource.run.rawValue:
            return "Run"
        case WorkspaceAttentionSource.build.rawValue:
            return "Build"
        case WorkspaceAttentionSource.terminal.rawValue:
            return "Terminal"
        default:
            return rawValue.capitalized
        }
    }
}
