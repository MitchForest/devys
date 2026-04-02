import Foundation

extension TMTokenizer {
    func tokensForCaptures(
        _ captures: [String: TMCapture],
        match: PatternMatch,
        baseScopes: [String],
        line: String,
        grammar: TMGrammar
    ) -> [TMToken] {
        let infos = captureInfos(captures, match: match, line: line)
        let orderedInfos = orderedCaptureInfos(infos)
        var tokens: [TMToken] = []

        for info in orderedInfos {
            let enclosing = enclosingInfos(for: info, in: orderedInfos)
            var captureScopes = baseScopes
            for enclosingInfo in enclosing {
                if let name = enclosingInfo.resolvedName {
                    captureScopes.append(contentsOf: TextMateScope.split(name))
                }
            }

            if let patterns = info.capture.patterns, !patterns.isEmpty {
                let nestedTokens = tokenizeRange(
                    line: line,
                    range: info.range,
                    baseScopes: captureScopes,
                    grammar: grammar,
                    patterns: patterns
                )
                if nestedTokens.isEmpty {
                    tokens.append(TMToken(
                        startIndex: info.range.lowerBound,
                        endIndex: info.range.upperBound,
                        scopes: captureScopes
                    ))
                } else {
                    let filledNested = fillGapsInRange(
                        tokens: nestedTokens,
                        range: info.range,
                        defaultScopes: captureScopes
                    )
                    tokens.append(contentsOf: filledNested)
                }
            } else {
                tokens.append(TMToken(
                    startIndex: info.range.lowerBound,
                    endIndex: info.range.upperBound,
                    scopes: captureScopes
                ))
            }
        }

        return tokens
    }
}

private extension TMTokenizer {
    struct CaptureInfo {
        let index: Int
        let range: Range<Int>
        let capture: TMCapture
        let resolvedName: String?
    }

    func captureInfos(
        _ captures: [String: TMCapture],
        match: PatternMatch,
        line: String
    ) -> [CaptureInfo] {
        var infos: [CaptureInfo] = []
        infos.reserveCapacity(captures.count)

        for (key, capture) in captures {
            guard let captureIndex = Int(key),
                  let captureRange = match.captures.first(where: { $0.index == captureIndex }) else { continue }
            guard captureRange.start >= 0,
                  captureRange.end >= 0,
                  captureRange.end > captureRange.start else { continue }

            let resolvedName = capture.name.flatMap { resolveBackreferences($0, in: line, match: match) ?? $0 }
            infos.append(CaptureInfo(
                index: captureIndex,
                range: captureRange.start..<captureRange.end,
                capture: capture,
                resolvedName: resolvedName
            ))
        }

        return infos
    }

    func orderedCaptureInfos(_ infos: [CaptureInfo]) -> [CaptureInfo] {
        infos.sorted {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound < $1.range.lowerBound
            }
            let lhsLength = $0.range.upperBound - $0.range.lowerBound
            let rhsLength = $1.range.upperBound - $1.range.lowerBound
            if lhsLength != rhsLength {
                return lhsLength > rhsLength
            }
            return $0.index < $1.index
        }
    }

    func enclosingInfos(
        for info: CaptureInfo,
        in orderedInfos: [CaptureInfo]
    ) -> [CaptureInfo] {
        orderedInfos
            .filter { $0.range.lowerBound <= info.range.lowerBound && $0.range.upperBound >= info.range.upperBound }
            .sorted {
                let lhsLength = $0.range.upperBound - $0.range.lowerBound
                let rhsLength = $1.range.upperBound - $1.range.lowerBound
                if lhsLength != rhsLength {
                    return lhsLength > rhsLength
                }
                return $0.index < $1.index
            }
    }

    struct SliceTokenizationResult {
        let tokens: [TMToken]
        let positionScopes: [Int: [String]]
    }

    func tokenizeRange(
        line: String,
        range: Range<Int>,
        baseScopes: [String],
        grammar: TMGrammar,
        patterns: [TMPattern]
    ) -> [TMToken] {
        guard range.lowerBound < range.upperBound else { return [] }

        let startIndex = line.utf16Index(at: range.lowerBound)
        let endIndex = line.utf16Index(at: range.upperBound)
        let slice = String(line[startIndex..<endIndex])
        let sliceLength = slice.utf16Count
        let matchSlice = slice + "\n"

        let initialState = RuleStack.fromScopes(
            baseScopes,
            grammarScopeName: grammar.scopeName,
            nestedPatterns: patterns,
            anchorPosition: 0
        )

        let result = tokenizeSlice(
            matchSlice: matchSlice,
            sliceLength: sliceLength,
            state: initialState
        )

        let filled = fillGapsWithPositionScopes(
            tokens: result.tokens,
            lineLength: sliceLength,
            positionScopes: result.positionScopes,
            defaultScopes: baseScopes
        )

        return filled.map { token in
            TMToken(
                startIndex: token.startIndex + range.lowerBound,
                endIndex: token.endIndex + range.lowerBound,
                scopes: token.scopes
            )
        }
    }

    func tokenizeSlice(
        matchSlice: String,
        sliceLength: Int,
        state: RuleStack
    ) -> SliceTokenizationResult {
        var state = state
        var tokens: [TMToken] = []
        var positionScopes: [Int: [String]] = [:]
        var position = 0

        let matchContext = SliceMatchContext(
            sliceLength: sliceLength,
            matchSlice: matchSlice
        )

        while position < sliceLength {
            positionScopes[position] = self.baseScopes(for: state)

            guard let result = matchAtPosition(
                line: matchSlice,
                position: position,
                state: state
            ) else {
                position = advancePosition(position, in: matchSlice, limit: sliceLength)
                continue
            }

            let outcome = applyMatchResult(
                result,
                position: position,
                state: state,
                context: matchContext,
                positionScopes: &positionScopes,
                tokens: &tokens
            )
            position = outcome.position
            state = outcome.state
        }

        _ = resolveEndState(
            line: matchSlice,
            sliceLength: sliceLength,
            state: state,
            tokens: &tokens
        )

        return SliceTokenizationResult(
            tokens: tokens,
            positionScopes: positionScopes
        )
    }

    func applyMatchResult(
        _ result: MatchResult,
        position: Int,
        state: RuleStack,
        context: SliceMatchContext,
        positionScopes: inout [Int: [String]],
        tokens: inout [TMToken]
    ) -> (position: Int, state: RuleStack) {
        if result.tokens.isEmpty && result.newPosition == position {
            return (position, result.newState)
        }

        if result.newPosition <= position {
            let next = advancePosition(position, in: context.matchSlice, limit: context.sliceLength)
            return (next, state)
        }

        appendTokens(from: result, sliceLength: context.sliceLength, tokens: &tokens)

        let matchEnd = min(result.newPosition, context.sliceLength)
        let gapScopes: [String]
        if result.newState.depth < state.depth {
            gapScopes = state.scopesWithoutContent
        } else {
            gapScopes = self.baseScopes(for: state)
        }

        for pos in position..<matchEnd where positionScopes[pos] == nil {
            positionScopes[pos] = gapScopes
        }

        return (matchEnd, result.newState)
    }

    struct SliceMatchContext {
        let sliceLength: Int
        let matchSlice: String
    }

    func appendTokens(
        from result: MatchResult,
        sliceLength: Int,
        tokens: inout [TMToken]
    ) {
        for token in result.tokens {
            let start = max(0, token.startIndex)
            let end = min(sliceLength, token.endIndex)
            if start < end {
                tokens.append(TMToken(startIndex: start, endIndex: end, scopes: token.scopes))
            }
        }
    }

    func advancePosition(_ position: Int, in matchSlice: String, limit: Int) -> Int {
        min(limit, matchSlice.nextCharacterBoundary(afterUtf16Offset: position))
    }

    func resolveEndState(
        line: String,
        sliceLength: Int,
        state: RuleStack,
        tokens: inout [TMToken]
    ) -> RuleStack {
        var endState = state
        var endGuard = 0
        while endGuard < 50 {
            endGuard += 1
            guard let endResult = matchAtPosition(
                line: line,
                position: sliceLength,
                state: endState
            ) else {
                break
            }

            if endResult.tokens.isEmpty
                && endResult.newPosition == sliceLength
                && endResult.newState != endState {
                endState = endResult.newState
                continue
            }

            if !endResult.tokens.isEmpty {
                appendTokens(from: endResult, sliceLength: sliceLength, tokens: &tokens)
            }

            if endResult.newPosition == sliceLength && endResult.newState != endState {
                endState = endResult.newState
                continue
            }

            break
        }
        return endState
    }
}
