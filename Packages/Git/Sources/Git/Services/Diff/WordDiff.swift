// WordDiff.swift
// Word-level diff algorithm using LCS.

import Foundation

/// Word-level diff utility using Longest Common Subsequence.
struct WordDiff: Sendable {
    
    /// A change in a word diff.
    struct Change: Sendable {
        let range: Range<String.Index>
        let type: ChangeType
    }
    
    /// Type of change.
    enum ChangeType: Sendable {
        case added
        case removed
        case unchanged
    }
    
    /// Diff mode for granularity.
    enum DiffMode: Sendable {
        case word     // Word boundaries
        case wordAlt  // Word boundaries, minimize single-char gaps
        case char     // Character-level
    }
    
    /// Compute word-level diff between old and new lines.
    /// Returns ranges of changed words in each line.
    static func diff(
        old: String,
        new: String,
        mode: DiffMode = .wordAlt,
        includeWhitespace: Bool = false
    ) -> (oldChanges: [Change], newChanges: [Change]) {
        let oldTokens = tokenize(old, mode: mode, includeWhitespace: includeWhitespace)
        let newTokens = tokenize(new, mode: mode, includeWhitespace: includeWhitespace)
        
        let lcs = longestCommonSubsequence(
            oldTokens.map(\.text),
            newTokens.map(\.text)
        )
        let oldUnchanged = lcs.oldIndices
        let newUnchanged = lcs.newIndices
        
        let oldChanges = oldTokens.enumerated().map { index, token in
            Change(
                range: token.range,
                type: oldUnchanged.contains(index) ? .unchanged : .removed
            )
        }
        
        let newChanges = newTokens.enumerated().map { index, token in
            Change(
                range: token.range,
                type: newUnchanged.contains(index) ? .unchanged : .added
            )
        }
        
        return (oldChanges, newChanges)
    }
    
    // MARK: - Private
    
    private struct Token {
        let text: String
        let range: Range<String.Index>
    }
    
    private enum TokenKind {
        case word
        case whitespace
        case symbol
    }
    
    private static func tokenize(
        _ text: String,
        mode: DiffMode,
        includeWhitespace: Bool
    ) -> [Token] {
        switch mode {
        case .char:
            return tokenizeByCharacter(text)
        case .word, .wordAlt:
            return tokenizeByWord(text, includeWhitespace: includeWhitespace)
        }
    }
    
    private static func tokenizeByCharacter(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        
        while index < text.endIndex {
            let nextIndex = text.index(after: index)
            let range = index..<nextIndex
            tokens.append(Token(text: String(text[range]), range: range))
            index = nextIndex
        }
        
        return tokens
    }
    
    private static func tokenizeByWord(_ text: String, includeWhitespace: Bool) -> [Token] {
        var tokens: [Token] = []
        var start: String.Index?
        var currentKind: TokenKind?
        
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let tokenKind = classifyCharacter(character, includeWhitespace: includeWhitespace)
            
            if let kind = tokenKind {
                if start == nil {
                    start = index
                    currentKind = kind
                } else if currentKind != kind {
                    // End current token
                    if let tokenStart = start {
                        let range = tokenStart..<index
                        tokens.append(Token(text: String(text[range]), range: range))
                    }
                    start = index
                    currentKind = kind
                }
            } else if let tokenStart = start, currentKind != nil {
                // End current token
                let range = tokenStart..<index
                tokens.append(Token(text: String(text[range]), range: range))
                start = nil
                currentKind = nil
            }
            
            index = text.index(after: index)
        }
        
        // Handle final token
        if let tokenStart = start, currentKind != nil {
            let range = tokenStart..<text.endIndex
            tokens.append(Token(text: String(text[range]), range: range))
        }
        
        return tokens
    }
    
    private static func classifyCharacter(_ character: Character, includeWhitespace: Bool) -> TokenKind? {
        if character.isLetter || character.isNumber || character == "_" {
            return .word
        } else if includeWhitespace && character.isWhitespace {
            return .whitespace
        } else if !character.isWhitespace {
            return .symbol
        }
        return nil
    }
    
    /// Compute longest common subsequence and return matching indices.
    private static func longestCommonSubsequence(
        _ a: [String],
        _ b: [String]
    ) -> (oldIndices: Set<Int>, newIndices: Set<Int>) {
        let n = a.count
        let m = b.count
        
        if n == 0 || m == 0 {
            return ([], [])
        }
        
        // Build DP table
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }
        
        // Backtrack to find matching indices
        var i = n
        var j = m
        var oldIndices: Set<Int> = []
        var newIndices: Set<Int> = []
        
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                oldIndices.insert(i - 1)
                newIndices.insert(j - 1)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] >= dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        
        return (oldIndices, newIndices)
    }
}
