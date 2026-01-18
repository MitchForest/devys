//
//  AgentType.swift
//  devys
//
//  The type of AI backend (Codex or Claude Code).
//

import Foundation

/// The type of AI backend.
enum AgentType: String, Hashable, CaseIterable {
    case codex
    case claudeCode
    
    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        }
    }
    
    var icon: String {
        switch self {
        case .codex: return "cpu"
        case .claudeCode: return "brain"
        }
    }
}
