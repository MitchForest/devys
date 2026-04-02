// HighlightProvider.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Provides the main interface for syntax highlighting text.
// Combines tokenization with theme resolution.

import Foundation
import SwiftUI

// MARK: - Highlight Provider

/// Main interface for syntax highlighting
public actor HighlightProvider {
    /// Theme registry for color resolution
    private let themeService: ThemeService
    /// Grammar registry for tokenization
    private let grammarService: GrammarService

    /// Tokenizer cache
    private var tokenizerCache: [String: TMTokenizer] = [:]

    // MARK: - Initialization

    @MainActor
    public init(
        themeService: ThemeService = ThemeRegistry(),
        grammarService: GrammarService = TMRegistry()
    ) {
        self.themeService = themeService
        self.grammarService = grammarService
    }

    // MARK: - Public API

    /// Highlight a single line of code
    func highlight(
        line: String,
        language: String,
        prevState: RuleStack? = nil
    ) async -> HighlightedLine {
        let resolver = await resolverSnapshot()
        return await highlightLine(
            line: line,
            language: language,
            prevState: prevState,
            resolver: resolver
        )
    }

    /// Highlight multiple lines of code
    func highlight(text: String, language: String) async -> [HighlightedLine] {
        let lines = text.components(separatedBy: .newlines)
        var results: [HighlightedLine] = []
        var state: RuleStack?
        let resolver = await resolverSnapshot()

        for line in lines {
            let result = await highlightLine(
                line: line,
                language: language,
                prevState: state,
                resolver: resolver
            )
            results.append(result)
            state = result.endState
        }

        return results
    }

    /// Get an AttributedString for a line of code
    public func attributedLine(
        _ line: String,
        language: String,
        fontSize: CGFloat = 12,
        fontName: String = "Menlo"
    ) async -> AttributedString {
        let highlighted = await highlight(line: line, language: language)
        return highlighted.toAttributedString(fontSize: fontSize, fontName: fontName)
    }

    /// Get AttributedString for full text
    public func attributedText(
        _ text: String,
        language: String,
        fontSize: CGFloat = 12,
        fontName: String = "Menlo"
    ) async -> AttributedString {
        let lines = await highlight(text: text, language: language)
        var result = AttributedString()

        for (index, line) in lines.enumerated() {
            result.append(line.toAttributedString(fontSize: fontSize, fontName: fontName))
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }

    // MARK: - Private

    private func getTokenizer(for language: String) async -> TMTokenizer? {
        if let cached = tokenizerCache[language] {
            return cached
        }

        do {
            let grammar = try await grammarService.grammar(for: language)
            let scopeNameToGrammar = try await grammarService.grammarsByScope()
            let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeNameToGrammar)
            tokenizerCache[language] = tokenizer
            return tokenizer
        } catch {
            return nil
        }
    }

    private func resolveStyles(tokens: [TMToken], resolver: ThemeResolver?) -> [StyledToken] {
        guard let resolver else {
            return tokens.map { token in
                StyledToken(range: token.range, foregroundColor: nil, fontStyle: [])
            }
        }

        return tokens.map { token in
            let style = resolver.resolve(scopes: token.scopes)
            return StyledToken(
                range: token.range,
                foregroundColor: style.foreground,
                fontStyle: style.fontStyle
            )
        }
    }

    private func resolverSnapshot() async -> ThemeResolver? {
        await MainActor.run { themeService.currentResolver }
    }

    private func highlightLine(
        line: String,
        language: String,
        prevState: RuleStack?,
        resolver: ThemeResolver?
    ) async -> HighlightedLine {
        guard let tokenizer = await getTokenizer(for: language) else {
            return HighlightedLine(
                text: line,
                styledTokens: [],
                endState: RuleStack.initial(scopeName: "source.\(language)")
            )
        }

        let result = tokenizer.tokenizeLine(line: line, prevState: prevState)
        let styledTokens = resolveStyles(tokens: result.tokens, resolver: resolver)

        return HighlightedLine(
            text: line,
            styledTokens: styledTokens,
            endState: result.endState
        )
    }
}

// MARK: - Highlighted Line

/// Result of highlighting a single line
struct HighlightedLine: Sendable {
    /// Original text
    let text: String

    /// Tokens with resolved styles
    let styledTokens: [StyledToken]

    /// State at end of line (for continuing)
    let endState: RuleStack

    /// Convert to AttributedString
    func toAttributedString(fontSize: CGFloat = 12, fontName: String = "Menlo") -> AttributedString {
        var result = AttributedString(text)

        let font = Font.custom(fontName, size: fontSize)
        result.font = font

        for styledToken in styledTokens {
            // Convert Int range to String.Index range
            guard styledToken.range.lowerBound >= 0,
                  styledToken.range.upperBound <= text.utf16Count else { continue }

            let startIdx = text.utf16Index(at: styledToken.range.lowerBound)
            let endIdx = text.utf16Index(at: styledToken.range.upperBound)
            let stringRange = startIdx..<endIdx

            // Convert to AttributedString range
            guard let attrStart = AttributedString.Index(stringRange.lowerBound, within: result),
                  let attrEnd = AttributedString.Index(stringRange.upperBound, within: result) else {
                continue
            }
            let attrRange = attrStart..<attrEnd

            // Apply foreground color
            if let colorHex = styledToken.foregroundColor,
               let color = Color(hex: colorHex) {
                result[attrRange].foregroundColor = color
            }

            // Apply font style
            if styledToken.fontStyle.contains(.bold) || styledToken.fontStyle.contains(.italic) {
                if styledToken.fontStyle.contains(.bold) && styledToken.fontStyle.contains(.italic) {
                    result[attrRange].font = font.bold().italic()
                } else if styledToken.fontStyle.contains(.bold) {
                    result[attrRange].font = font.bold()
                } else if styledToken.fontStyle.contains(.italic) {
                    result[attrRange].font = font.italic()
                }
            }

            // Apply underline
            if styledToken.fontStyle.contains(.underline) {
                result[attrRange].underlineStyle = .single
            }
        }

        return result
    }
}
