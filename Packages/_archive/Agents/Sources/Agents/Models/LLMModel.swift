// LLMModel.swift
// Type-safe LLM model definitions with verified API IDs.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

// MARK: - LLM Provider

/// Supported LLM providers.
public enum LLMProvider: String, CaseIterable, Sendable, Codable {
    case anthropic
    case openai
}

// MARK: - LLM Model

/// Type-safe LLM model definitions.
///
/// These model IDs are verified against the provider APIs.
/// Update this enum when new models are released.
public enum LLMModel: String, CaseIterable, Sendable, Codable, Identifiable {

    // MARK: - Anthropic Claude 4.5 Series

    /// Claude Opus 4.5 - Anthropic's most intelligent model.
    /// Best for: Frontier tasks, professional software engineering, complex agentic workflows.
    /// Pricing: $5/$25 per million tokens. Context: 200K.
    case claudeOpus45 = "claude-opus-4-5-20251101"

    /// Claude Sonnet 4.5 - Best coding model, strongest for building complex agents.
    /// Substantial gains in reasoning and math over Sonnet 4.
    /// Pricing: $3/$15 per million tokens.
    case claudeSonnet45 = "claude-sonnet-4-5-20250929"

    /// Claude Haiku 4.5 - Fastest and most compact model.
    /// Best for: High-speed tasks, cost-sensitive applications.
    case claudeHaiku45 = "claude-haiku-4-5-20251001"

    // MARK: - OpenAI Codex 5.x Series

    /// GPT-5.2 Codex - OpenAI's flagship coding model.
    /// Best for: Complex code generation, multi-file editing, deep reasoning.
    case codex52 = "gpt-5.2-codex"

    /// GPT-5.1 Codex Mini - Faster, more cost-effective Codex variant.
    /// Best for: Quick code completions, simpler tasks.
    case codex51Mini = "gpt-5.1-codex-mini"

    // MARK: - Identifiable

    public var id: String { rawValue }

    // MARK: - Provider

    /// The provider for this model.
    public var provider: LLMProvider {
        switch self {
        case .claudeOpus45, .claudeSonnet45, .claudeHaiku45:
            return .anthropic
        case .codex52, .codex51Mini:
            return .openai
        }
    }

    // MARK: - Display Names

    /// Full display name for UI.
    public var displayName: String {
        switch self {
        case .claudeOpus45: return "Claude Opus 4.5"
        case .claudeSonnet45: return "Claude Sonnet 4.5"
        case .claudeHaiku45: return "Claude Haiku 4.5"
        case .codex52: return "GPT-5.2 Codex"
        case .codex51Mini: return "GPT-5.1 Codex Mini"
        }
    }

    /// Short name for compact UI.
    public var shortName: String {
        switch self {
        case .claudeOpus45: return "Opus 4.5"
        case .claudeSonnet45: return "Sonnet 4.5"
        case .claudeHaiku45: return "Haiku 4.5"
        case .codex52: return "Codex 5.2"
        case .codex51Mini: return "Codex Mini"
        }
    }

    // MARK: - Model Tiers

    /// Model capability tier.
    public var tier: ModelTier {
        switch self {
        case .claudeOpus45, .codex52:
            return .flagship
        case .claudeSonnet45:
            return .balanced
        case .claudeHaiku45, .codex51Mini:
            return .fast
        }
    }

    // MARK: - Defaults

    /// Recommended models per harness (native first).
    public static func recommended(for harness: HarnessType) -> [LLMModel] {
        switch harness {
        case .codex:
            return [.codex52, .codex51Mini, .claudeOpus45, .claudeSonnet45]
        case .claudeCode:
            return [.claudeOpus45, .claudeSonnet45, .claudeHaiku45, .codex52]
        }
    }

    // MARK: - Lookup

    /// Find model by raw ID string.
    public static func from(id: String) -> LLMModel? {
        allCases.first { $0.rawValue == id }
    }
}

// MARK: - Model Tier

/// Model capability/speed tier.
public enum ModelTier: String, Sendable, Codable {
    /// Flagship models - highest capability, slower, more expensive
    case flagship

    /// Balanced models - good capability/speed tradeoff
    case balanced

    /// Fast models - optimized for speed and cost
    case fast

    public var label: String {
        switch self {
        case .flagship: return "Flagship"
        case .balanced: return "Balanced"
        case .fast: return "Fast"
        }
    }
}
