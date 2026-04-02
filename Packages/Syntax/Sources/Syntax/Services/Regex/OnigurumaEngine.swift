// OnigurumaEngine.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// RegexEngine implementation that wraps OnigurumaKit.
// Provides full TextMate grammar pattern compatibility.

import Foundation
import OnigurumaKit

// MARK: - OnigurumaEngine

/// Regex engine using native Oniguruma C library via OnigurumaKit.
///
/// This engine provides full compatibility with TextMate grammars,
/// supporting all Oniguruma regex features including:
/// - Named capturing groups `(?<name>...)`
/// - Named backreferences `\k<name>`
/// - Unicode property escapes
/// - Possessive quantifiers
/// - All TextMate-specific constructs
struct OnigurumaEngine: RegexEngine, Sendable {
    /// Create a multi-pattern scanner using Oniguruma.
    /// - Parameter patterns: Array of regex pattern strings
    /// - Returns: A PatternScanner using Oniguruma
    /// - Throws: If any pattern fails to compile
    func createScanner(patterns: [String]) throws -> any PatternScanner {
        try OnigurumaPatternScanner(patterns: patterns)
    }
}

// MARK: - OnigurumaPatternScanner

/// Pattern scanner that wraps OnigurumaKit's OnigScanner.
final class OnigurumaPatternScanner: PatternScanner, @unchecked Sendable {
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
    ///   - position: Position in UTF-16 code units
    /// - Returns: Match result with UTF-16 positions, or nil
    func findNextMatch(in string: String, from position: Int) -> PatternMatch? {
        // Convert UTF-16 position to UTF-8 byte position
        let utf8Position = utf16ToUtf8Position(in: string, utf16Offset: position)
        
        guard let match = scanner.findNextMatch(in: string, from: utf8Position) else {
            return nil
        }
        
        // Convert capture positions from UTF-8 to UTF-16
        let utf16Captures = match.captures.map { capture in
            CaptureRange(
                index: capture.index,
                start: utf8ToUtf16Position(in: string, utf8Offset: capture.start),
                end: utf8ToUtf16Position(in: string, utf8Offset: capture.end)
            )
        }
        
        return PatternMatch(captures: utf16Captures)
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
