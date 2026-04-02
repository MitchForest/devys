// TMRegistry.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Manages loading and caching of TextMate grammars.

import Foundation

public protocol GrammarService: Sendable {
    func grammar(for languageId: String) async throws -> TMGrammar
    func grammarForScope(_ scopeName: String) async throws -> TMGrammar?
    func clearCache() async
    func grammarsByScope() async throws -> [String: TMGrammar]
}

// MARK: - Grammar Registry

/// Registry for loading and caching TextMate grammars
public actor TMRegistry: GrammarService {
    /// Cached grammars by language ID
    private var grammars: [String: TMGrammar] = [:]

    /// Mapping from scope name to language ID
    private var scopeToLanguage: [String: String] = [:]

    /// Bundle to load resources from
    private let bundle: Bundle

    // MARK: - Initialization

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? Bundle.moduleBundle
    }

    // MARK: - Grammar Loading

    /// Get grammar for a language ID
    public func grammar(for languageId: String) async throws -> TMGrammar {
        // Check cache
        if let cached = grammars[languageId] {
            return cached
        }

        // Load from bundle
        let grammar = try TMGrammar.load(languageId: languageId, bundle: bundle)

        // Cache it
        grammars[languageId] = grammar
        scopeToLanguage[grammar.scopeName] = languageId

        return grammar
    }

    /// Get grammar by scope name (for embedded languages)
    public func grammarForScope(_ scopeName: String) async throws -> TMGrammar? {
        // Check if we know the language for this scope
        if let languageId = scopeToLanguage[scopeName] {
            return try await grammar(for: languageId)
        }

        // Try to find it in available grammars
        for id in Self.availableLanguages {
            do {
                let g = try await grammar(for: id)
                if g.scopeName == scopeName {
                    return g
                }
            } catch {
                continue
            }
        }

        return nil
    }

    /// Clear the cache
    public func clearCache() async {
        grammars.removeAll()
        scopeToLanguage.removeAll()
    }

    /// Load all bundled grammars and return a scope-name map.
    public func grammarsByScope() async throws -> [String: TMGrammar] {
        var map: [String: TMGrammar] = [:]
        for id in Self.availableLanguages {
            let grammar = try await grammar(for: id)
            map[grammar.scopeName] = grammar
        }
        return map
    }

    // MARK: - Available Languages

    /// List of bundled language IDs
    public static let availableLanguages: [String] = [
        "swift",
        "python",
        "javascript",
        "typescript",
        "tsx",
        "jsx",
        "html",
        "css",
        "json",
        "yaml",
        "markdown",
        "ruby",
        "rust",
        "c",
        "cpp",
        "go",
        "php",
        "java",
        "csharp",
        "lua",
        "kotlin",
        "make",
        "shellscript",
        "plaintext"
    ]

    /// Check if a language is available
    public static func isLanguageAvailable(_ languageId: String) -> Bool {
        availableLanguages.contains(languageId)
    }
}
