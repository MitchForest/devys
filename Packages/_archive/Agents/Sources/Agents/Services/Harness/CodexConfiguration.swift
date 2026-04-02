// CodexConfiguration.swift
// Manages ~/.codex/config.toml for provider configuration.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// Manages Codex CLI configuration.
///
/// Codex uses `~/.codex/config.toml` for configuration.
/// Format (TOML with snake_case keys):
/// ```
/// model_provider = "openai"
/// model = "gpt-5.2-codex"
/// ```
///
/// ## Built-in Providers
/// - openai, azure, openrouter, gemini, ollama, mistral, deepseek, xai, groq
struct CodexConfiguration {

    /// Path to the Codex config file.
    static var configPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    }

    /// Gets the current model.
    static func getCurrentModel() -> String? {
        guard let content = try? String(contentsOf: configPath) else {
            return nil
        }

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("model =") {
                if let start = trimmed.firstIndex(of: "\""),
                   let end = trimmed.lastIndex(of: "\""),
                   start < end {
                    return String(trimmed[trimmed.index(after: start)..<end])
                }
            }
        }

        return nil
    }

}
