// RegexEngine.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Protocol abstraction for regex engines, matching Shiki's IOnigLib pattern.
// This allows swapping between NSRegularExpression and Oniguruma.

import Foundation

// MARK: - Regex Engine Protocol

/// Protocol for regex engine implementations.
///
/// Matches Shiki's IOnigLib interface pattern:
/// - `createOnigScanner(patterns)` → `createScanner(patterns:)`
/// - `createOnigString(s)` → Not needed (Swift String works directly)
///
/// This abstraction allows swapping between regex engine implementations.
protocol RegexEngine: Sendable {
    /// Create a multi-pattern scanner.
    /// - Parameter patterns: Array of regex pattern strings
    /// - Returns: A scanner that can find matches among all patterns
    /// - Throws: If any pattern fails to compile
    func createScanner(patterns: [String]) throws -> any PatternScanner
}

// MARK: - Pattern Scanner Protocol

/// Protocol for pattern scanning operations.
///
/// Matches Shiki's OnigScanner interface:
/// - `findNextMatchSync(string, startPosition)` → `findNextMatch(in:from:)`
protocol PatternScanner: Sendable {
    /// Find the next match starting from the given position.
    /// - Parameters:
    ///   - string: The string to search
    ///   - position: UTF-16 offset to start searching from
    /// - Returns: Match result or nil if no match found
    func findNextMatch(in string: String, from position: Int) -> PatternMatch?
}

// MARK: - Pattern Match

/// Result of a successful pattern match.
///
/// Matches Shiki's captureIndices interface.
struct PatternMatch: Sendable, Equatable {
    /// Capture group positions.
    /// Index 0 is always the full match, 1+ are capture groups.
    let captures: [CaptureRange]
    
    /// Start offset of the full match (UTF-16).
    var startOffset: Int {
        captures.first { $0.index == 0 }?.start ?? (captures.first?.start ?? 0)
    }
    
    /// End offset of the full match (UTF-16).
    var endOffset: Int {
        captures.first { $0.index == 0 }?.end ?? (captures.first?.end ?? 0)
    }
    
}

// MARK: - Capture Range

/// A single capture group's position.
///
/// Matches Shiki's captureIndices element:
/// - `index`: Capture group index (0 = full match)
/// - `start`: Start position (UTF-16)
/// - `end`: End position (UTF-16)
struct CaptureRange: Sendable, Equatable {
    /// Capture group index (0 = full match, 1+ = capture groups).
    let index: Int
    
    /// Start position in UTF-16 code units.
    let start: Int
    
    /// End position in UTF-16 code units.
    let end: Int
    
}

// MARK: - Default Engine

/// The default regex engine used by Syntax.
///
/// Uses `OnigurumaEngine` for full TextMate grammar compatibility.
let defaultRegexEngine: any RegexEngine = OnigurumaEngine()
