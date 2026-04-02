// TMTokenizer+GapFilling.swift
// DevysSyntax

import Foundation

extension TMTokenizer {
    // MARK: - Gap Filling

    func fillGapsWithPositionScopes(
        tokens: [TMToken],
        lineLength: Int,
        positionScopes: [Int: [String]],
        defaultScopes: [String]
    ) -> [TMToken] {
        guard lineLength > 0 else { return [] }
        var scopesByPos = Array(repeating: defaultScopes, count: lineLength)
        var specificityByPos = Array(repeating: Int.min, count: lineLength)
        var startByPos = Array(repeating: 0, count: lineLength)

        for pos in 0..<lineLength {
            if let scopes = positionScopes[pos] {
                scopesByPos[pos] = scopes
            }
            startByPos[pos] = pos
        }

        for token in tokens {
            let start = max(0, min(lineLength, token.startIndex))
            let end = max(0, min(lineLength, token.endIndex))
            guard start < end else { continue }

            let specificity = tokenSpecificity(token)
            for index in start..<end {
                let currentScopes = scopesByPos[index]
                if isPrefix(currentScopes, token.scopes) {
                    scopesByPos[index] = token.scopes
                    specificityByPos[index] = specificity
                    startByPos[index] = token.startIndex
                    continue
                }

                if isPrefix(token.scopes, currentScopes) {
                    continue
                }

                if token.startIndex < startByPos[index]
                    || (token.startIndex == startByPos[index] && specificity >= specificityByPos[index]) {
                    scopesByPos[index] = token.scopes
                    specificityByPos[index] = specificity
                    startByPos[index] = token.startIndex
                }
            }
        }

        return buildTokensFromScopes(scopesByPos: scopesByPos, startIndex: 0)
    }

    func fillGapsInRange(
        tokens: [TMToken],
        range: Range<Int>,
        defaultScopes: [String]
    ) -> [TMToken] {
        guard range.lowerBound < range.upperBound else { return [] }
        let length = range.upperBound - range.lowerBound
        var scopesByPos = Array(repeating: defaultScopes, count: length)
        var specificityByPos = Array(repeating: Int.min, count: length)
        var startByPos = Array(repeating: range.lowerBound, count: length)

        for token in tokens {
            let start = max(range.lowerBound, token.startIndex)
            let end = min(range.upperBound, token.endIndex)
            guard start < end else { continue }

            let specificity = tokenSpecificity(token)
            for index in start..<end {
                let localIndex = index - range.lowerBound
                let currentScopes = scopesByPos[localIndex]
                if isPrefix(currentScopes, token.scopes) {
                    scopesByPos[localIndex] = token.scopes
                    specificityByPos[localIndex] = specificity
                    startByPos[localIndex] = token.startIndex
                    continue
                }

                if isPrefix(token.scopes, currentScopes) {
                    continue
                }

                if token.startIndex < startByPos[localIndex]
                    || (token.startIndex == startByPos[localIndex] && specificity >= specificityByPos[localIndex]) {
                    scopesByPos[localIndex] = token.scopes
                    specificityByPos[localIndex] = specificity
                    startByPos[localIndex] = token.startIndex
                }
            }
        }

        return buildTokensFromScopes(scopesByPos: scopesByPos, startIndex: range.lowerBound)
    }

    private func buildTokensFromScopes(
        scopesByPos: [[String]],
        startIndex: Int
    ) -> [TMToken] {
        guard let firstScopes = scopesByPos.first else { return [] }

        var filled: [TMToken] = []
        var currentStart = startIndex
        var currentScopes = firstScopes

        for offset in 1..<scopesByPos.count {
            let scopes = scopesByPos[offset]
            if scopes != currentScopes {
                filled.append(TMToken(
                    startIndex: currentStart,
                    endIndex: startIndex + offset,
                    scopes: currentScopes
                ))
                currentStart = startIndex + offset
                currentScopes = scopes
            }
        }

        filled.append(TMToken(
            startIndex: currentStart,
            endIndex: startIndex + scopesByPos.count,
            scopes: currentScopes
        ))

        return filled
    }

    private func tokenSpecificity(_ token: TMToken) -> Int {
        (token.scopes.count * 1000) - token.length
    }

    private func isPrefix(_ lhs: [String], _ rhs: [String]) -> Bool {
        guard lhs.count <= rhs.count else { return false }
        for (index, value) in lhs.enumerated() where rhs[index] != value {
            return false
        }
        return true
    }
}
