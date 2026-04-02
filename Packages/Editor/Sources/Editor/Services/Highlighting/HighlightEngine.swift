// HighlightEngine.swift
// DevysEditor - Metal-accelerated code editor
//
// Async tokenization engine integrated with Syntax.

import Foundation
import OSLog
import Syntax

private let logger = Logger(subsystem: "com.devys.editor", category: "HighlightEngine")

// MARK: - Highlighted Token

/// A token with resolved styling
struct HighlightedToken: Sendable {
    /// Character range in the line
    let range: Range<Int>

    /// Foreground color (hex)
    let foregroundColor: String

    /// Background color (hex, optional)
    let backgroundColor: String?

    /// Font style flags
    let fontStyle: FontStyle

    init(
        range: Range<Int>,
        foregroundColor: String,
        backgroundColor: String? = nil,
        fontStyle: FontStyle = []
    ) {
        self.range = range
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.fontStyle = fontStyle
    }
}

// MARK: - Highlighted Line

/// A line with syntax highlighting applied
struct HighlightedLine: Sendable {
    /// Line index in document
    let lineIndex: Int

    /// Original text
    let text: String

    /// Styled tokens
    let tokens: [HighlightedToken]

    /// End state for continuation
    let endState: RuleStack

}

// MARK: - Highlight Engine

/// Manages async syntax highlighting for the editor.
actor HighlightEngine {

    // MARK: - Properties

    /// Language being highlighted
    private let language: String
    /// Tokenizer instance
    private var tokenizer: TMTokenizer?

    /// Theme resolver
    private var resolver: ThemeResolver?

    /// Cached line states (line index → end state)
    private var lineStates: [Int: RuleStack] = [:]

    /// Cached highlighted lines
    private var highlightedLines: [Int: HighlightedLine] = [:]

    /// Lines that need re-tokenization
    private var dirtyLines: Set<Int> = []

    /// Default foreground color
    private var defaultForeground: String

    // MARK: - Initialization

    init(
        language: String,
        themeName: String = "github-dark",
        highlightingService: HighlightingService? = nil
    ) async {
        self.language = language
        self.defaultForeground = "#d4d4d4"
        let resolvedHighlightingService = await resolveHighlightingService(
            provided: highlightingService
        )

        // Load grammar
        do {
            self.tokenizer = try await resolvedHighlightingService.tokenizer(for: language)
            #if DEBUG
            logger.debug("Loaded grammar for language: \(language, privacy: .public)")
            #endif
        } catch {
            logger.error("Failed to load grammar for \(language, privacy: .public)")
            logger.error("Grammar error: \(String(describing: error), privacy: .public)")
            logger.error(
                "Available languages: \(TMRegistry.availableLanguages, privacy: .public)"
            )
        }

        // Load theme
        do {
            let resolver = try await resolvedHighlightingService.resolver(themeName: themeName)
            self.resolver = resolver
            self.defaultForeground = resolver.defaultForeground
            #if DEBUG
            logger.debug("Loaded theme '\(resolver.theme.name, privacy: .public)'")
            logger.debug(
                "Default foreground \(resolver.defaultForeground, privacy: .public)"
            )
            #endif
        } catch {
            logger.error(
                "Failed to load theme \(themeName, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func resolveHighlightingService(
        provided: HighlightingService?
    ) async -> HighlightingService {
        if let provided {
            return provided
        }

        let themeService = await MainActor.run { ThemeRegistry() }
        return DefaultHighlightingService(themeService: themeService)
    }

    // MARK: - Highlighting

    /// Highlight a range of lines
    func highlightLines(
        _ lines: [String],
        startingAt startIndex: Int
    ) -> [HighlightedLine] {
        guard let tokenizer = tokenizer, let resolver = resolver else {
            return fallbackLines(lines, startIndex: startIndex)
        }

        var results: [HighlightedLine] = []
        var prevState = cachedState(before: startIndex)

        for (offset, text) in lines.enumerated() {
            let lineIndex = startIndex + offset
            let highlighted = highlightLine(
                lineIndex: lineIndex,
                text: text,
                tokenizer: tokenizer,
                resolver: resolver,
                prevState: &prevState
            )
            results.append(highlighted)
        }

        return results
    }

    private func fallbackLines(_ lines: [String], startIndex: Int) -> [HighlightedLine] {
        lines.enumerated().map { offset, text in
            HighlightedLine(
                lineIndex: startIndex + offset,
                text: text,
                tokens: [
                    HighlightedToken(
                        range: 0..<text.utf16.count,
                        foregroundColor: defaultForeground
                    )
                ],
                endState: RuleStack.initial(scopeName: "source.\(language)")
            )
        }
    }

    private func cachedState(before startIndex: Int) -> RuleStack? {
        guard startIndex > 0 else { return nil }
        return lineStates[startIndex - 1]
    }

    private func highlightLine(
        lineIndex: Int,
        text: String,
        tokenizer: TMTokenizer,
        resolver: ThemeResolver,
        prevState: inout RuleStack?
    ) -> HighlightedLine {
        if let cached = highlightedLines[lineIndex],
           !dirtyLines.contains(lineIndex),
           cached.text == text {
            prevState = cached.endState
            return cached
        }

        let tokenResult = tokenizer.tokenizeLine(line: text, prevState: prevState)
        let styledTokens = styleTokens(tokenResult.tokens, resolver: resolver)

        let highlighted = HighlightedLine(
            lineIndex: lineIndex,
            text: text,
            tokens: styledTokens,
            endState: tokenResult.endState
        )

        highlightedLines[lineIndex] = highlighted
        lineStates[lineIndex] = tokenResult.endState
        dirtyLines.remove(lineIndex)

        prevState = tokenResult.endState
        return highlighted
    }

    private func styleTokens(
        _ tokens: [TMToken],
        resolver: ThemeResolver
    ) -> [HighlightedToken] {
        tokens.compactMap { token -> HighlightedToken? in
            guard !token.range.isEmpty else { return nil }

            let style = resolver.resolve(scopes: token.scopes)
            let fontStyle = style.fontStyle

            return HighlightedToken(
                range: token.range,
                foregroundColor: style.foreground,
                backgroundColor: style.background,
                fontStyle: fontStyle
            )
        }
    }

}
