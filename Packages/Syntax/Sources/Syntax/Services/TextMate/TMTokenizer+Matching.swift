// TMTokenizer+Matching.swift
// DevysSyntax

import Foundation

extension TMTokenizer {
    // MARK: - Pattern Matching

    struct MatchResult {
        let tokens: [TMToken]
        let newPosition: Int
        let newState: RuleStack
    }

    func matchAtPosition(line: String, position: Int, state: RuleStack) -> MatchResult? {
        let currentGrammar = grammarForScopeName(state.grammarScopeName) ?? grammar
        let endMatch = findEndMatch(
            line: line,
            position: position,
            state: state,
            grammar: currentGrammar
        )

        let (patterns, patternGrammar) = collectPatterns(state: state)
        let evaluation = evaluatePatterns(
            patterns,
            line: line,
            position: position,
            state: state,
            grammar: patternGrammar,
            endMatchStart: endMatch.start
        )

        if let immediate = evaluation.immediate {
            return immediate
        }

        return resolveMatch(
            bestMatch: evaluation.bestMatch,
            bestMatchStart: evaluation.bestMatchStart,
            endMatch: endMatch,
            applyEndPatternLast: state.applyEndPatternLast,
            position: position
        )
    }

    private func resolveMatch(
        bestMatch: MatchResult?,
        bestMatchStart: Int,
        endMatch: (result: MatchResult?, start: Int),
        applyEndPatternLast: Bool,
        position: Int
    ) -> MatchResult? {
        if endMatch.result != nil, endMatch.start > position {
            if let bestMatch, bestMatchStart < endMatch.start {
                return bestMatch
            }
            return nil
        }

        if applyEndPatternLast {
            if let bestMatch, bestMatchStart == position {
                return bestMatch
            }
            if let endMatchResult = endMatch.result {
                if let bestMatch, bestMatchStart <= endMatch.start {
                    return bestMatch
                }
                return endMatchResult
            }
            return bestMatch
        }

        if let endMatchResult = endMatch.result {
            if let bestMatch, bestMatchStart < endMatch.start {
                return bestMatch
            }
            return endMatchResult
        }

        return bestMatch
    }

    private func evaluatePatterns(
        _ patterns: [TMPattern],
        line: String,
        position: Int,
        state: RuleStack,
        grammar: TMGrammar,
        endMatchStart: Int
    ) -> (immediate: MatchResult?, bestMatch: MatchResult?, bestMatchStart: Int) {
        var evaluation = PatternEvaluationState()

        for (index, pattern) in patterns.enumerated() {
            guard let result = tryPattern(
                pattern,
                in: line,
                at: position,
                state: state,
                grammar: grammar
            ) else {
                continue
            }

            if shouldApplyStateTransitionNow(
                result,
                position: position,
                state: state,
                endMatchStart: endMatchStart
            ) {
                evaluation.recordZeroLengthTransition(result, index: index)
                continue
            }

            evaluation.considerMatch(result, index: index, position: position)
        }

        return evaluation.finalize(position: position)
    }

    private struct PatternEvaluationState {
        var bestMatch: MatchResult?
        var bestMatchStart = Int.max
        var zeroLengthTransition: MatchResult?
        var zeroLengthIndex: Int?
        var firstMatchAtPositionIndex: Int?

        mutating func recordZeroLengthTransition(_ result: MatchResult, index: Int) {
            guard zeroLengthTransition == nil else { return }
            zeroLengthTransition = result
            zeroLengthIndex = index
        }

        mutating func considerMatch(_ result: MatchResult, index: Int, position: Int) {
            if let firstToken = result.tokens.first {
                if firstToken.startIndex == position, firstMatchAtPositionIndex == nil {
                    firstMatchAtPositionIndex = index
                }
                if firstToken.startIndex < bestMatchStart {
                    bestMatch = result
                    bestMatchStart = firstToken.startIndex
                }
            } else if result.newPosition > position && bestMatch == nil {
                bestMatch = result
            }
        }

        func finalize(position: Int) -> (immediate: MatchResult?, bestMatch: MatchResult?, bestMatchStart: Int) {
            if let zeroLengthTransition,
               let zeroLengthIndex,
               let firstMatchAtPositionIndex,
               zeroLengthIndex < firstMatchAtPositionIndex {
                return (zeroLengthTransition, nil, Int.max)
            }

            if let bestMatch, bestMatchStart == position {
                return (nil, bestMatch, bestMatchStart)
            }

            if let zeroLengthTransition {
                return (zeroLengthTransition, nil, Int.max)
            }

            return (nil, bestMatch, bestMatchStart)
        }
    }

    private func shouldApplyStateTransitionNow(
        _ result: MatchResult,
        position: Int,
        state: RuleStack,
        endMatchStart: Int
    ) -> Bool {
        guard result.tokens.isEmpty,
              result.newPosition == position,
              result.newState != state else {
            return false
        }

        return state.applyEndPatternLast || endMatchStart != position
    }

    private func findEndMatch(
        line: String,
        position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> (result: MatchResult?, start: Int) {
        guard let endPattern = state.endPattern,
              let match = tryMatch(
                pattern: endPattern,
                in: line,
                at: position,
                anchorPosition: state.anchorPosition
              ) else {
            return (nil, Int.max)
        }

        let matchStart = match.startOffset
        let matchEnd = match.endOffset
        guard matchStart >= position else {
            return (nil, Int.max)
        }

        let newState = state.pop()
        let scopes = state.scopesWithoutContent
        let context = EndMatchContext(
            match: match,
            scopes: scopes,
            line: line,
            grammar: grammar,
            matchStart: matchStart,
            matchEnd: matchEnd
        )
        let tokens = endMatchTokens(endCaptures: state.endCaptures, context: context)

        let result = MatchResult(tokens: tokens, newPosition: matchEnd, newState: newState)
        return (result, matchStart)
    }

    private struct EndMatchContext {
        let match: PatternMatch
        let scopes: [String]
        let line: String
        let grammar: TMGrammar
        let matchStart: Int
        let matchEnd: Int
    }

    private func endMatchTokens(
        endCaptures: [String: TMCapture]?,
        context: EndMatchContext
    ) -> [TMToken] {
        if context.matchStart == context.matchEnd {
            return []
        }

        if let endCaptures, !endCaptures.isEmpty {
            var captureTokens = tokensForCaptures(
                endCaptures,
                match: context.match,
                baseScopes: context.scopes,
                line: context.line,
                grammar: context.grammar
            )
            if !captureTokens.isEmpty {
                if context.matchStart < context.matchEnd {
                    captureTokens = fillGapsInRange(
                        tokens: captureTokens,
                        range: context.matchStart..<context.matchEnd,
                        defaultScopes: context.scopes
                    )
                }
                return captureTokens
            }
        }

        return [
            TMToken(
                startIndex: context.matchStart,
                endIndex: context.matchEnd,
                scopes: context.scopes
            )
        ]
    }

    func collectPatterns(state: RuleStack) -> ([TMPattern], TMGrammar) {
        let currentGrammar = grammarForScopeName(state.grammarScopeName) ?? grammar
        // If we have nested patterns from the current rule, use those
        if let nestedPatterns = state.nestedPatterns {
            let (leftInjections, rightInjections) = injectionPatterns(for: state, grammar: currentGrammar)
            let combined = leftInjections + nestedPatterns + rightInjections
            return (combined, currentGrammar)
        }

        // Inside a begin/end (or begin/while) block without explicit patterns,
        // do not fall back to top-level grammar patterns.
        if state.endPattern != nil || state.whilePattern != nil {
            let (leftInjections, rightInjections) = injectionPatterns(for: state, grammar: currentGrammar)
            return (leftInjections + rightInjections, currentGrammar)
        }

        // Otherwise use grammar's top-level patterns
        let (leftInjections, rightInjections) = injectionPatterns(for: state, grammar: currentGrammar)
        let combined = leftInjections + currentGrammar.patterns + rightInjections
        return (combined, currentGrammar)
    }

    func tryPattern(
        _ pattern: TMPattern,
        in line: String,
        at position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> MatchResult? {
        if pattern.disabled == true {
            return nil
        }
        switch pattern.patternType {
        case .match:
            return trySimpleMatch(pattern, in: line, at: position, state: state, grammar: grammar)
        case .beginEnd:
            return tryBeginMatch(pattern, in: line, at: position, state: state, grammar: grammar)
        case .include:
            return tryInclude(pattern, in: line, at: position, state: state, grammar: grammar)
        case .container:
            // Container patterns just hold nested patterns
            for nested in pattern.patterns ?? [] {
                if let result = tryPattern(nested, in: line, at: position, state: state, grammar: grammar) {
                    return result
                }
            }
            return nil
        case .unknown:
            return nil
        }
    }

    // MARK: - Simple Match

    func trySimpleMatch(
        _ pattern: TMPattern,
        in line: String,
        at position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> MatchResult? {
        guard let matchRegex = pattern.match else { return nil }
        guard let match = tryMatch(
            pattern: matchRegex,
            in: line,
            at: position,
            anchorPosition: state.anchorPosition
        ) else { return nil }

        let matchStart = match.startOffset
        let matchEnd = match.endOffset

        // Only accept matches that start at or after our position
        guard matchStart >= position else { return nil }

        var tokens: [TMToken] = []

        // Build scopes for this match
        var matchScopes = baseScopes(for: state)
        if let name = pattern.name {
            let resolvedName = resolveBackreferences(name, in: line, match: match) ?? name
            matchScopes.append(contentsOf: TextMateScope.split(resolvedName))
        }

        // Check for captures
        if let captures = pattern.captures, !captures.isEmpty {
            let captureTokens = tokensForCaptures(
                captures,
                match: match,
                baseScopes: matchScopes,
                line: line,
                grammar: grammar
            )
            if captureTokens.isEmpty {
                tokens.append(TMToken(
                    startIndex: matchStart,
                    endIndex: matchEnd,
                    scopes: matchScopes
                ))
            } else {
                let filled = fillGapsInRange(
                    tokens: captureTokens,
                    range: matchStart..<matchEnd,
                    defaultScopes: matchScopes
                )
                tokens.append(contentsOf: filled)
            }
        } else {
            // Single token for the whole match
            tokens.append(TMToken(
                startIndex: matchStart,
                endIndex: matchEnd,
                scopes: matchScopes
            ))
        }

        return MatchResult(tokens: tokens, newPosition: matchEnd, newState: state)
    }

    // MARK: - Begin/End Match

    func tryBeginMatch(
        _ pattern: TMPattern,
        in line: String,
        at position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> MatchResult? {
        guard let beginRegex = pattern.begin else { return nil }
        guard let match = tryMatch(
            pattern: beginRegex,
            in: line,
            at: position,
            anchorPosition: state.anchorPosition
        ) else { return nil }

        let matchStart = match.startOffset
        let matchEnd = match.endOffset

        // Only accept matches that start at or after our position
        guard matchStart >= position else { return nil }

        if shouldRejectShellMatch(pattern: pattern, line: line, matchStart: matchStart) {
            return nil
        }

        let context = BeginMatchContext(
            pattern: pattern,
            match: match,
            line: line,
            grammar: grammar,
            matchStart: matchStart,
            matchEnd: matchEnd,
            position: position
        )
        let scopeNames = resolveScopeNames(pattern: pattern, line: line, match: match)
        let beginScopes = baseScopes(for: state) + scopeNames
        var tokens = beginCaptureTokens(context: context, baseScopes: beginScopes)

        let shouldReprocessLine = shouldReprocessLine(context: context)

        if tokens.isEmpty && !shouldReprocessLine {
            tokens.append(TMToken(
                startIndex: matchStart,
                endIndex: matchEnd,
                scopes: beginScopes
            ))
        }

        let newState = pushBeginState(
            context: context,
            state: state,
            scopeNames: scopeNames
        )

        let newPosition = shouldReprocessLine ? position : matchEnd
        return MatchResult(tokens: tokens, newPosition: newPosition, newState: newState)
    }

    private func shouldRejectShellMatch(
        pattern: TMPattern,
        line: String,
        matchStart: Int
    ) -> Bool {
        guard pattern.name == "meta.statement.shell" else { return false }
        let startIndex = line.utf16Index(at: matchStart)
        let tail = String(line[startIndex...])
        return tail.range(
            of: #"^\s*(then|do|fi|done|else|elif|esac)\b"#,
            options: .regularExpression
        ) != nil
    }

    private func resolveScopeNames(
        pattern: TMPattern,
        line: String,
        match: PatternMatch
    ) -> [String] {
        guard let name = pattern.name else { return [] }
        let resolvedName = resolveBackreferences(name, in: line, match: match) ?? name
        return TextMateScope.split(resolvedName)
    }

    private func beginCaptureTokens(
        context: BeginMatchContext,
        baseScopes: [String]
    ) -> [TMToken] {
        let beginCaptureSource = (context.pattern.beginCaptures?.isEmpty == false)
            ? context.pattern.beginCaptures
            : context.pattern.captures
        guard let beginCaptures = beginCaptureSource, !beginCaptures.isEmpty else {
            return []
        }

        var captureTokens = tokensForCaptures(
            beginCaptures,
            match: context.match,
            baseScopes: baseScopes,
            line: context.line,
            grammar: context.grammar
        )
        if !captureTokens.isEmpty && context.matchStart < context.matchEnd {
            captureTokens = fillGapsInRange(
                tokens: captureTokens,
                range: context.matchStart..<context.matchEnd,
                defaultScopes: baseScopes
            )
        }
        return captureTokens
    }

    private func shouldReprocessLine(context: BeginMatchContext) -> Bool {
        let zeroLengthMatch = context.matchEnd == context.matchStart
        if zeroLengthMatch && context.matchStart == context.position {
            return true
        }
        if context.pattern.end == nil,
           context.pattern.`while` != nil,
           context.pattern.patterns?.isEmpty == false,
           context.matchEnd == context.line.utf16Count {
            return true
        }
        return false
    }

    private func pushBeginState(
        context: BeginMatchContext,
        state: RuleStack,
        scopeNames: [String]
    ) -> RuleStack {
        let resolvedEnd = resolveBackreferences(
            context.pattern.end,
            in: context.line,
            match: context.match
        )
        let resolvedWhile = resolveBackreferences(
            context.pattern.`while`,
            in: context.line,
            match: context.match
        )
        let resolvedContentName = resolveBackreferences(
            context.pattern.contentName,
            in: context.line,
            match: context.match
        )
        let endCaptures = (context.pattern.endCaptures?.isEmpty == false)
            ? context.pattern.endCaptures
            : context.pattern.captures

        return state.push(
            scopeNames: scopeNames,
            grammarScopeName: context.grammar.scopeName,
            endPattern: resolvedEnd,
            whilePattern: resolvedWhile,
            whileCaptures: context.pattern.whileCaptures,
            applyEndPatternLast: (context.pattern.applyEndPatternLast ?? 0) != 0,
            endCaptures: endCaptures,
            contentName: resolvedContentName,
            nestedPatterns: context.pattern.patterns,
            anchorPosition: context.matchEnd
        )
    }

    private struct BeginMatchContext {
        let pattern: TMPattern
        let match: PatternMatch
        let line: String
        let grammar: TMGrammar
        let matchStart: Int
        let matchEnd: Int
        let position: Int
    }
}
