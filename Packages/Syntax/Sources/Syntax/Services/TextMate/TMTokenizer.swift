// TMTokenizer.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Core tokenization engine that processes text using TextMate grammars.
// Produces tokens with scope stacks for theme resolution.

import Foundation
import OSLog

private let tokenizerLogger = Logger(subsystem: "com.devys.syntax", category: "TMTokenizer")

// MARK: - Tokenizer

/// TextMate-compatible tokenizer
public final class TMTokenizer: Sendable {
    /// The grammar being used
    public let grammar: TMGrammar
    
    /// The regex engine to use for pattern matching
    let engine: any RegexEngine

    /// Cached compiled scanners for regex patterns
    private let regexCache = RegexCache()

    /// Additional grammars keyed by scope name (for include "source.swift", etc.)
    let scopeNameToGrammar: [String: TMGrammar]

    // MARK: - Initialization

    /// Create a tokenizer with the specified grammar.
    /// - Parameters:
    ///   - grammar: The TextMate grammar to use
    public init(
        grammar: TMGrammar,
        scopeNameToGrammar: [String: TMGrammar] = [:]
    ) {
        self.grammar = grammar
        self.engine = defaultRegexEngine
        self.scopeNameToGrammar = scopeNameToGrammar
    }

    // MARK: - Tokenization

    /// Tokenize a single line
    public func tokenizeLine(line: String, prevState: RuleStack?) -> TokenizeResult {
        let context = makeTokenizeContext(line: line, prevState: prevState)

        // Track scope at each position for gap filling
        var positionScopes: [Int: [String]] = [:]
        var tokens: [TMToken] = []

        appendWhileTokensIfNeeded(
            line: context.matchLine,
            state: context.state,
            baseScopes: context.defaultScopes,
            grammar: context.initialGrammar,
            tokens: &tokens
        )

        let endState = tokenizeLineContent(
            line: context.matchLine,
            lineLength: context.lineLength,
            state: context.state,
            tokens: &tokens,
            positionScopes: &positionScopes
        )

        logRawTokensIfNeeded(tokens: tokens, line: line)

        // Fill gaps with position-aware scopes
        let filledTokens = fillGapsWithPositionScopes(
            tokens: tokens,
            lineLength: context.lineLength,
            positionScopes: positionScopes,
            defaultScopes: context.defaultScopes
        )

        let resolvedEndState = resolveEndStateAtLineEnd(line: line, state: endState)
        return TokenizeResult(tokens: filledTokens, endState: resolvedEndState)
    }

    private struct TokenizeContext {
        let matchLine: String
        let state: RuleStack
        let lineLength: Int
        let initialGrammar: TMGrammar
        let defaultScopes: [String]
    }

    private func makeTokenizeContext(line: String, prevState: RuleStack?) -> TokenizeContext {
        let matchLine = line + "\n"
        var state = prevState ?? RuleStack.initial(scopeName: grammar.scopeName)
        state = resolveWhileStateAtLineStart(line: matchLine, state: state)
        let lineLength = line.utf16Count
        let initialGrammar = grammarForScopeName(state.grammarScopeName) ?? grammar
        let defaultScopes = baseScopes(for: state)

        return TokenizeContext(
            matchLine: matchLine,
            state: state,
            lineLength: lineLength,
            initialGrammar: initialGrammar,
            defaultScopes: defaultScopes
        )
    }

    private func logRawTokensIfNeeded(tokens: [TMToken], line: String) {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_RAW"] == "1" else { return }

        for token in tokens {
            let start = line.utf16Index(at: token.startIndex)
            let end = line.utf16Index(at: token.endIndex)
            let text = String(line[start..<end])
            tokenizerLogger.debug(
                "Raw token: \(token.startIndex) \(token.endIndex) \(text, privacy: .public) \(token.scopes)"
            )
        }
    }

    private func appendWhileTokensIfNeeded(
        line: String,
        state: RuleStack,
        baseScopes: [String],
        grammar: TMGrammar,
        tokens: inout [TMToken]
    ) {
        guard let whilePattern = state.whilePattern,
              let whileCaptures = state.whileCaptures,
              let match = tryMatch(
                pattern: whilePattern,
                in: line,
                at: 0,
                anchorPosition: state.anchorPosition
              ),
              match.startOffset == 0 else {
            return
        }

        let whileTokens = tokensForCaptures(
            whileCaptures,
            match: match,
            baseScopes: baseScopes,
            line: line,
            grammar: grammar
        )
        tokens.append(contentsOf: whileTokens)
    }

    private func tokenizeLineContent(
        line: String,
        lineLength: Int,
        state: RuleStack,
        tokens: inout [TMToken],
        positionScopes: inout [Int: [String]]
    ) -> RuleStack {
        var position = 0
        var currentState = state
        var guardCount = 0
        let guardLimit = max(200, lineLength * 8)

        while position < lineLength {
            guardCount += 1
            if guardCount > guardLimit {
                position = handleTokenizerGuardExceeded(
                    line: line,
                    position: position,
                    state: currentState
                )
                continue
            }
            positionScopes[position] = baseScopes(for: currentState)

            let result = matchAtPosition(
                line: line,
                position: position,
                state: currentState
            )

            if let result {
                let matchContext = TokenizeMatchContext(line: line)
                position = applyMatchResult(
                    result,
                    position: position,
                    context: matchContext,
                    currentState: &currentState,
                    tokens: &tokens,
                    positionScopes: &positionScopes
                )
            } else {
                position = line.nextCharacterBoundary(afterUtf16Offset: position)
            }
        }

        return finalizeEndState(
            line: line,
            lineLength: lineLength,
            state: currentState,
            tokens: &tokens
        )
    }

    private func handleTokenizerGuardExceeded(
        line: String,
        position: Int,
        state: RuleStack
    ) -> Int {
        if ProcessInfo.processInfo.environment["DEVYS_TOKENIZER_GUARD"] == "1" {
            tokenizerLogger.debug(
                """
                Tokenizer guard triggered: \(line, privacy: .public) position: \(position) state: \(state.scopePath)
                """
            )
        }
        return line.nextCharacterBoundary(afterUtf16Offset: position)
    }

    private func applyMatchResult(
        _ result: MatchResult,
        position: Int,
        context: TokenizeMatchContext,
        currentState: inout RuleStack,
        tokens: inout [TMToken],
        positionScopes: inout [Int: [String]]
    ) -> Int {
        if result.tokens.isEmpty && result.newPosition == position {
            currentState = result.newState
            return position
        }

        tokens.append(contentsOf: result.tokens)
        let matchEnd = result.newPosition
        let gapScopes: [String]
        if result.newState.depth < currentState.depth {
            gapScopes = currentState.scopesWithoutContent
        } else {
            gapScopes = baseScopes(for: currentState)
        }
        for pos in position..<matchEnd where positionScopes[pos] == nil {
            positionScopes[pos] = gapScopes
        }

        if result.newPosition == position {
            if result.newState != currentState {
                currentState = result.newState
                return position
            }
            return context.line.nextCharacterBoundary(afterUtf16Offset: position)
        }

        let nextBoundary = context.line.nextCharacterBoundary(afterUtf16Offset: position)
        currentState = result.newState
        return max(result.newPosition, nextBoundary)
    }

    private struct TokenizeMatchContext {
        let line: String
    }

    private func finalizeEndState(
        line: String,
        lineLength: Int,
        state: RuleStack,
        tokens: inout [TMToken]
    ) -> RuleStack {
        var endState = state
        var endGuard = 0

        while endGuard < 50 {
            endGuard += 1
            guard let endResult = matchAtPosition(
                line: line,
                position: lineLength,
                state: endState
            ) else {
                break
            }

            if endResult.tokens.isEmpty && endResult.newPosition == lineLength && endResult.newState != endState {
                endState = endResult.newState
                continue
            }

            if !endResult.tokens.isEmpty {
                tokens.append(contentsOf: endResult.tokens)
            }

            if endResult.newPosition == lineLength && endResult.newState != endState {
                endState = endResult.newState
                continue
            }

            break
        }

        return endState
    }

    func scanner(for pattern: String) throws -> any PatternScanner {
        try regexCache.scanner(for: pattern, engine: engine)
    }
}
