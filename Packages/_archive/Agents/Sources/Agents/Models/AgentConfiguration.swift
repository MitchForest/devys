// AgentConfiguration.swift
// Type-safe configuration for agent sandbox and approval settings.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

// MARK: - Sandbox Mode

/// Controls what the agent can technically do when executing commands.
///
/// The sandbox is enforced at the OS level (macOS Seatbelt, Linux Landlock/seccomp).
/// This applies to ALL models (GPT, Claude, etc.) since the runtime enforces these constraints.
public enum SandboxMode: String, CaseIterable, Sendable, Codable {
    /// Agent can only read files and answer questions.
    /// Every edit or command requires approval.
    case readOnly = "read-only"

    /// Agent can read files, make edits, and run commands within the workspace.
    /// The workspace includes the working directory and temp directories like `/tmp`.
    /// Network access is OFF by default in this mode.
    case workspaceWrite = "workspace-write"

    /// No sandbox enforcement. Agent has full system access.
    /// ⚠️ DANGEROUS: Only use in isolated containers or when you fully trust the agent.
    case dangerFullAccess = "danger-full-access"

}

// MARK: - Approval Policy

/// Controls when the agent must ask for user approval before acting.
///
/// Works in combination with SandboxMode - the sandbox controls what's *possible*,
/// the approval policy controls what requires *permission*.
public enum ApprovalPolicy: String, CaseIterable, Sendable, Codable {
    /// Most conservative. Requires approval for most edits and commands.
    /// Use when working with untrusted code or sensitive projects.
    case untrusted = "untrusted"

    /// Default for trusted repos. Only asks for approval when:
    /// - Editing files outside the workspace
    /// - Running commands that need network access
    /// - Running risky or unfamiliar commands
    case onRequest = "on-request"

    /// Only asks for approval if a command fails.
    /// Good for trusted automation workflows.
    case onFailure = "on-failure"

    /// Never asks for approval. Agent acts autonomously.
    /// ⚠️ Use with caution - combine with appropriate sandbox mode.
    case never = "never"

}

// MARK: - Agent Preset

/// Convenience presets that combine sandbox mode and approval policy.
///
/// These match the Codex CLI presets for easy reference.
public enum AgentPreset: String, CaseIterable, Sendable, Codable {
    /// Safe browsing - read files, ask before any changes.
    case safeReadOnly

    /// Auto mode - edit workspace, ask for risky actions.
    case fullAuto

    /// Autonomous editing - edit freely, ask for untrusted commands.
    case autoEdit

    /// Non-interactive read-only (for CI).
    case ciReadOnly

    /// Fully autonomous with workspace constraints.
    case autonomous

    /// No limits. Full access, no approvals.
    case yolo

    /// The sandbox mode for this preset
    public var sandboxMode: SandboxMode {
        switch self {
        case .safeReadOnly, .ciReadOnly:
            return .readOnly
        case .fullAuto, .autoEdit, .autonomous:
            return .workspaceWrite
        case .yolo:
            return .dangerFullAccess
        }
    }

    /// The approval policy for this preset
    public var approvalPolicy: ApprovalPolicy {
        switch self {
        case .safeReadOnly, .fullAuto:
            return .onRequest
        case .autoEdit:
            return .untrusted
        case .ciReadOnly, .autonomous, .yolo:
            return .never
        }
    }

}

// MARK: - Risk Level

/// Indicates the risk level of a configuration or action.
public enum RiskLevel: Int, Comparable, Sendable, Codable {
    case low = 0
    case medium = 1
    case high = 2
    case extreme = 3

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .extreme: return "Extreme"
        }
    }

}

// MARK: - Agent Configuration

/// Complete configuration for an agent session.
public struct AgentConfiguration: Sendable, Codable, Equatable {
    /// The sandbox mode
    public var sandboxMode: SandboxMode

    /// The approval policy
    public var approvalPolicy: ApprovalPolicy

    /// Whether network access is enabled (only applies to workspaceWrite mode)
    public var networkAccess: Bool

    /// Initialize from a preset
    public init(preset: AgentPreset) {
        self.sandboxMode = preset.sandboxMode
        self.approvalPolicy = preset.approvalPolicy
        // Network access only in full access mode by default
        self.networkAccess = preset == .yolo
    }

    /// Default configuration - YOLO mode (user's preference)
    public static let `default` = AgentConfiguration(preset: .yolo)
}
