// TMTokenizer+Includes.swift
// DevysSyntax

import Foundation

extension TMTokenizer {
    // MARK: - Include

    func tryInclude(
        _ pattern: TMPattern,
        in line: String,
        at position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> MatchResult? {
        guard let include = pattern.include else { return nil }

        switch include {
        case "$self", "$base":
            return bestMatch(
                patterns: grammar.patterns,
                line: line,
                position: position,
                state: state,
                grammar: grammar
            )
        case let include where include.hasPrefix("#"):
            return includeRepository(
                include,
                line: line,
                position: position,
                state: state,
                grammar: grammar
            )
        default:
            if let externalGrammar = scopeNameToGrammar[include] {
                return bestMatch(
                    patterns: externalGrammar.patterns,
                    line: line,
                    position: position,
                    state: state,
                    grammar: externalGrammar
                )
            }
            return nil
        }
    }

    private func includeRepository(
        _ include: String,
        line: String,
        position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> MatchResult? {
        let repoKey = String(include.dropFirst())
        guard let repoPattern = grammar.repository?[repoKey] else { return nil }

        let mergedGrammar = TMGrammar(
            name: grammar.name,
            scopeName: grammar.scopeName,
            patterns: grammar.patterns,
            repository: mergedRepository(for: repoPattern, base: grammar.repository),
            injections: grammar.injections,
            fileTypes: grammar.fileTypes,
            firstLineMatch: grammar.firstLineMatch,
            foldingStartMarker: grammar.foldingStartMarker,
            foldingStopMarker: grammar.foldingStopMarker
        )

        return bestMatch(
            patterns: repoPattern.asPatterns,
            line: line,
            position: position,
            state: state,
            grammar: mergedGrammar
        )
    }

    private func mergedRepository(
        for repoPattern: TMRepositoryPattern,
        base: [String: TMRepositoryPattern]?
    ) -> [String: TMRepositoryPattern]? {
        let nestedRepository: [String: TMRepositoryPattern]? = {
            switch repoPattern {
            case .pattern(let pattern):
                return pattern.repository
            case .patterns:
                return nil
            }
        }()

        guard let nestedRepository else { return base }

        var merged = base ?? [:]
        for (key, value) in nestedRepository {
            merged[key] = value
        }
        return merged
    }


    // MARK: - Regex Matching

    func tryMatch(
        pattern: String,
        in line: String,
        at position: Int,
        anchorPosition: Int? = nil
    ) -> PatternMatch? {
        // Guard against Oniguruma crashing on recursive C++ scope-resolution patterns.
        if pattern.contains("__has_cpp_attribute"),
           pattern.contains("\\g<7>") {
            return nil
        }
        do {
            let anchor = anchorPosition ?? position
            if pattern.contains("\\G") {
                let match = try matchWithAnchor(
                    pattern: pattern,
                    line: line,
                    position: position,
                    anchor: anchor
                )
                if let match {
                    return match.startOffset == position ? match : nil
                }
                if position == 0, anchor != 0 {
                    let fallback = try matchWithAnchor(
                        pattern: pattern,
                        line: line,
                        position: position,
                        anchor: 0
                    )
                    if let fallback {
                        return fallback.startOffset == position ? fallback : nil
                    }
                }
                return nil
            }

            let scanner = try scanner(for: pattern)
            return scanner.findNextMatch(in: line, from: position)
        } catch {
            // Pattern failed to compile - skip it
            return nil
        }
    }

    private func matchWithAnchor(
        pattern: String,
        line: String,
        position: Int,
        anchor: Int
    ) throws -> PatternMatch? {
        let anchorLookbehind = #"(?<=\A.{\#(anchor)})"#
        let adjustedPattern = pattern.replacingOccurrences(of: "\\G", with: anchorLookbehind)
        let scanner = try scanner(for: adjustedPattern)
        return scanner.findNextMatch(in: line, from: position)
    }

    private func bestMatch(
        patterns: [TMPattern],
        line: String,
        position: Int,
        state: RuleStack,
        grammar: TMGrammar
    ) -> MatchResult? {
        var bestMatch: MatchResult?
        var bestMatchStart = Int.max
        var zeroLengthTransition: MatchResult?
        var zeroLengthIndex: Int?
        var firstMatchAtPositionIndex: Int?

        for (index, nested) in patterns.enumerated() {
            guard let result = tryPattern(nested, in: line, at: position, state: state, grammar: grammar) else {
                continue
            }

            if result.tokens.isEmpty,
               result.newPosition == position,
               result.newState != state {
                if zeroLengthTransition == nil {
                    zeroLengthTransition = result
                    zeroLengthIndex = index
                }
                continue
            }

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

        if let zeroLengthTransition,
           let zeroLengthIndex,
           let firstMatchAtPositionIndex,
           zeroLengthIndex < firstMatchAtPositionIndex {
            return zeroLengthTransition
        }

        if let bestMatch, bestMatchStart == position {
            return bestMatch
        }

        if let zeroLengthTransition {
            return zeroLengthTransition
        }

        return bestMatch
    }

    // MARK: - Grammar Helpers

    func grammarForScopeName(_ scopeName: String) -> TMGrammar? {
        if scopeName == grammar.scopeName {
            return grammar
        }
        return scopeNameToGrammar[scopeName]
    }

    func baseScopes(for state: RuleStack) -> [String] {
        state.scopes
    }

    func resolveBackreferences(_ pattern: String?, in line: String, match: PatternMatch) -> String? {
        guard let pattern, pattern.contains("\\") || pattern.contains("$") else { return pattern }

        // Build capture lookup
        var captureValues: [Int: String] = [:]
        for capture in match.captures {
            guard capture.start >= 0, capture.end >= 0, capture.end >= capture.start else { continue }
            let start = line.utf16Index(at: capture.start)
            let end = line.utf16Index(at: capture.end)
            captureValues[capture.index] = String(line[start..<end])
        }

        var result = pattern

        let regexes = [
            try? NSRegularExpression(pattern: #"\\(\d+)"#, options: []),
            try? NSRegularExpression(pattern: #"\$(\d+)"#, options: []),
            try? NSRegularExpression(pattern: #"\$\{(\d+):/(downcase|upcase|capitalize)\}"#, options: [])
        ].compactMap { $0 }

        for regex in regexes {
            let matches = regex.matches(in: result, options: [], range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let numRange = Range(match.range(at: 1), in: result) else { continue }
                let indexString = String(result[numRange])
                guard let index = Int(indexString) else { continue }
                let replacement = captureValues[index] ?? ""

                var transformed = replacement
                if match.numberOfRanges >= 3,
                   let transformRange = Range(match.range(at: 2), in: result) {
                    let transform = String(result[transformRange])
                    switch transform {
                    case "downcase":
                        transformed = replacement.lowercased()
                    case "upcase":
                        transformed = replacement.uppercased()
                    case "capitalize":
                        transformed = replacement.capitalized
                    default:
                        break
                    }
                }

                let escaped = NSRegularExpression.escapedPattern(for: transformed)

                if let fullRange = Range(match.range(at: 0), in: result) {
                    result.replaceSubrange(fullRange, with: escaped)
                }
            }
        }

        return result
    }

}
