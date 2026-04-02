// HighlightingService.swift
// DevysEditor - Metal-accelerated code editor
//
// Theme + grammar loading service.

import Foundation
import Syntax

protocol HighlightingService: Sendable {
    func tokenizer(for language: String) async throws -> TMTokenizer
    func resolver(themeName: String) async throws -> ThemeResolver
}

actor DefaultHighlightingService: HighlightingService {
    private let grammarService: GrammarService
    private let themeService: ThemeService

    init(
        grammarService: GrammarService = TMRegistry(),
        themeService: ThemeService
    ) {
        self.grammarService = grammarService
        self.themeService = themeService
    }

    func tokenizer(for language: String) async throws -> TMTokenizer {
        let grammar = try await grammarService.grammar(for: language)
        let scopeNameToGrammar = try await grammarService.grammarsByScope()
        return TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeNameToGrammar)
    }

    func resolver(themeName: String) async throws -> ThemeResolver {
        let resolver = await themeService.resolver(for: themeName)
        guard let resolver else {
            throw HighlightingServiceError.missingTheme(themeName)
        }
        return resolver
    }
}

enum HighlightingServiceError: Error {
    case missingTheme(String)
}
