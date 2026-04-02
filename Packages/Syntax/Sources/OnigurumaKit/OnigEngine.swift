// OnigEngine.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// RegexEngine implementation using Oniguruma.
// Provides full TextMate grammar pattern compatibility.

import Foundation

// MARK: - OnigEngine

/// Regex engine using native Oniguruma C library.
///
/// This engine provides full compatibility with TextMate grammars,
/// supporting all Oniguruma regex features including:
/// - Named capturing groups `(?<name>...)`
/// - Named backreferences `\k<name>`
/// - Unicode property escapes
/// - Possessive quantifiers
/// - All TextMate-specific constructs
public struct OnigEngine: Sendable {
    
    public init() {}
    
    /// Create a multi-pattern scanner using Oniguruma.
    /// - Parameter patterns: Array of regex pattern strings
    /// - Returns: A PatternScanner using Oniguruma
    /// - Throws: If any pattern fails to compile
    public func createScanner(patterns: [String]) throws -> OnigPatternScanner {
        try OnigPatternScanner(patterns: patterns)
    }
}

// MARK: - OnigPatternScanner

/// Pattern scanner using Oniguruma for matching.
public final class OnigPatternScanner: @unchecked Sendable {
    private let scanner: OnigScanner
    
    init(patterns: [String]) throws {
        self.scanner = try OnigScanner(patterns: patterns)
    }
    
    /// Find the next match starting from the given position.
    ///
    /// Note: The position is in UTF-16 code units (to match Swift String indices),
    /// but Oniguruma uses UTF-8. This method handles the conversion.
    ///
    /// - Parameters:
    ///   - string: The string to search
    ///   - utf16Position: Position in UTF-16 code units
    /// - Returns: Match result with UTF-16 positions, or nil
    public func findNextMatch(in string: String, fromUTF16 utf16Position: Int) -> OnigPatternMatch? {
        // Convert UTF-16 position to UTF-8 byte position
        let utf8Position = utf16ToUtf8Position(in: string, utf16Offset: utf16Position)
        
        guard let match = scanner.findNextMatch(in: string, from: utf8Position) else {
            return nil
        }
        
        // Convert capture positions from UTF-8 to UTF-16
        let utf16Captures = match.captures.map { capture in
            OnigPatternCapture(
                index: capture.index,
                start: utf8ToUtf16Position(in: string, utf8Offset: capture.start),
                end: utf8ToUtf16Position(in: string, utf8Offset: capture.end)
            )
        }
        
        return OnigPatternMatch(
            patternIndex: match.patternIndex,
            captures: utf16Captures
        )
    }
    
    // MARK: - Position Conversion
    
    private func utf16ToUtf8Position(in string: String, utf16Offset: Int) -> Int {
        guard utf16Offset > 0 else { return 0 }
        guard utf16Offset < string.utf16.count else { return string.utf8.count }
        
        let utf16Index = string.utf16.index(string.utf16.startIndex, offsetBy: utf16Offset)
        let stringIndex = String.Index(utf16Index, within: string) ?? string.startIndex
        return string.utf8.distance(from: string.utf8.startIndex, to: stringIndex)
    }
    
    private func utf8ToUtf16Position(in string: String, utf8Offset: Int) -> Int {
        guard utf8Offset > 0 else { return 0 }
        guard utf8Offset < string.utf8.count else { return string.utf16.count }
        
        let utf8Index = string.utf8.index(string.utf8.startIndex, offsetBy: utf8Offset)
        let stringIndex = String.Index(utf8Index, within: string) ?? string.startIndex
        return string.utf16.distance(from: string.utf16.startIndex, to: stringIndex)
    }
}

// MARK: - OnigPatternMatch

/// Match result with UTF-16 positions.
public struct OnigPatternMatch: Sendable, Equatable {
    /// Index of the pattern that matched.
    public let patternIndex: Int
    
    /// Capture groups with UTF-16 positions.
    public let captures: [OnigPatternCapture]
    
    /// Start position in UTF-16 code units.
    public var startOffset: Int {
        captures.first?.start ?? 0
    }
    
    /// End position in UTF-16 code units.
    public var endOffset: Int {
        captures.first?.end ?? 0
    }
}

// MARK: - OnigPatternCapture

/// Capture group with UTF-16 positions.
public struct OnigPatternCapture: Sendable, Equatable {
    /// Capture group index.
    public let index: Int
    
    /// Start position in UTF-16 code units.
    public let start: Int
    
    /// End position in UTF-16 code units.
    public let end: Int
}
