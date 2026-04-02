// OnigurumaKit.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Swift wrapper for the Oniguruma regex library.
// Provides full TextMate grammar pattern compatibility.

import Foundation
@preconcurrency import COniguruma

// MARK: - Oniguruma Constants

// C macros are not imported by Swift, so we define them here
private let kOnigOptionNone: OnigOptionType = 0

// Syntax behavior flag that causes only named groups to be captured
// We need to DISABLE this to get numbered group captures when pattern has named groups
private let kOnigSynCaptureOnlyNamedGroup: UInt32 = 1 << 7
// Allow different-length and variable-length lookbehind (TextMate grammars rely on this).
private let kOnigSynDifferentLenAltLookBehind: UInt32 = 1 << 6
private let kOnigSynVariableLenLookBehind: UInt32 = 1 << 11

// Custom syntax for TextMate grammars - initialized once, never modified after
// Using nonisolated(unsafe) since this is effectively constant after initialization
nonisolated(unsafe) private var textMateSyntax: OnigSyntaxType = {
    _ = onigurumaConfig
    var syntax = OnigSyntaxType()
    // Copy Ruby syntax as base (Ruby is what TextMate grammars are based on)
    withUnsafeMutablePointer(to: &OnigSyntaxRuby) { rubySyntax in
        onig_copy_syntax(&syntax, rubySyntax)
    }
    
    // Disable CAPTURE_ONLY_NAMED_GROUP behavior
    // This ensures numbered groups like (func) are captured even when
    // the pattern contains named groups like (?<q>...)
    var behavior = onig_get_syntax_behavior(&syntax)
    behavior &= ~kOnigSynCaptureOnlyNamedGroup
    behavior |= kOnigSynDifferentLenAltLookBehind
    behavior |= kOnigSynVariableLenLookBehind
    onig_set_syntax_behavior(&syntax, behavior)
    
    return syntax
}()

// MARK: - Oniguruma Configuration

private let onigurumaConfig: Void = {
    withUnsafeMutablePointer(to: &OnigEncodingUTF8) { utf8Ptr in
        var encodings: [OnigEncoding?] = [utf8Ptr]
        encodings.withUnsafeMutableBufferPointer { buffer in
            _ = onig_initialize(buffer.baseAddress, Int32(buffer.count))
        }
    }

    // Initialize Oniguruma with UTF-8 encoding.
    // (Oniguruma also handles this lazily, but explicit init is safer.)
}()

// MARK: - OnigRegex

/// A compiled Oniguruma regular expression.
///
/// This class is `@unchecked Sendable` because the underlying Oniguruma regex
/// object is thread-safe for matching operations (read-only after creation).
public final class OnigRegex: @unchecked Sendable {
    private let regex: OpaquePointer
    
    /// The original pattern string.
    public let pattern: String
    
    /// Compile a regex pattern using Oniguruma.
    /// - Parameter pattern: The regex pattern string
    /// - Throws: `OnigError` if compilation fails
    public init(pattern: String) throws {
        _ = onigurumaConfig
        self.pattern = pattern
        
        var regexPtr: OpaquePointer?
        var errorInfo = OnigErrorInfo()
        
        // Access C globals - these are thread-safe for reading
        let encoding = withUnsafeMutablePointer(to: &OnigEncodingUTF8) { $0 }
        
        // Use our custom syntax that captures both numbered and named groups
        let result = pattern.withCString { patternPtr in
            let patternEnd = patternPtr.advanced(by: pattern.utf8.count)
            return withUnsafeMutablePointer(to: &textMateSyntax) { syntaxPtr in
                onig_new(
                    &regexPtr,
                    patternPtr,
                    patternEnd,
                    kOnigOptionNone,
                    encoding,
                    syntaxPtr,
                    &errorInfo
                )
            }
        }
        
        guard result == ONIG_NORMAL, let compiledRegex = regexPtr else {
            throw OnigError.compileFailed(
                pattern: pattern,
                message: "Oniguruma error code: \(result)"
            )
        }
        
        self.regex = compiledRegex
    }
    
    deinit {
        onig_free(regex)
    }
    
    /// Search for a match in the given string.
    /// - Parameters:
    ///   - string: The string to search
    ///   - startPosition: UTF-8 byte offset to start searching from
    /// - Returns: Match result or nil if no match found
    public func search(in string: String, from startPosition: Int = 0) -> OnigMatch? {
        guard let region = onig_region_new() else { return nil }
        defer { onig_region_free(region, 1) }

        let matchResult = string.withCString { strPtr in
            let strEnd = strPtr.advanced(by: string.utf8.count)
            let start = strPtr.advanced(by: min(startPosition, string.utf8.count))

            return onig_search(
                regex,
                strPtr,
                strEnd,
                start,
                strEnd,
                region,
                kOnigOptionNone
            )
        }
        
        // Result is the match position or negative error code
        guard matchResult >= 0 else { return nil }
        
        // Extract captures from region
        // IMPORTANT: Include ALL capture groups, even unmatched ones (-1, -1),
        // so that capture indices are preserved for TextMate grammar processing.
        var captures: [OnigCapture] = []
        let numRegs = Int(region.pointee.num_regs)
        
        
        for i in 0..<numRegs {
            let beg = Int(region.pointee.beg[i])
            let end = Int(region.pointee.end[i])
            
            // Include all captures, even unmatched (-1, -1) to preserve indices
            captures.append(OnigCapture(index: i, start: beg, end: end))
        }
        
        return OnigMatch(matchPosition: Int(matchResult), captures: captures)
    }
}

// MARK: - OnigMatch

/// Result of a successful Oniguruma regex match.
public struct OnigMatch: Sendable, Equatable {
    /// Position where the match was found (UTF-8 byte offset).
    public let matchPosition: Int
    
    /// Capture groups (index 0 is the full match).
    public let captures: [OnigCapture]
    
    /// Start position of the full match.
    public var start: Int {
        captures.first?.start ?? matchPosition
    }
    
    /// End position of the full match.
    public var end: Int {
        captures.first?.end ?? matchPosition
    }
}

// MARK: - OnigCapture

/// A capture group from an Oniguruma match.
public struct OnigCapture: Sendable, Equatable {
    /// Capture group index (0 = full match).
    public let index: Int
    
    /// Start position (UTF-8 byte offset).
    public let start: Int
    
    /// End position (UTF-8 byte offset).
    public let end: Int
    
    /// Length of the capture.
    public var length: Int { end - start }
}

// MARK: - OnigError

/// Errors from Oniguruma operations.
public enum OnigError: Error, LocalizedError, Sendable {
    case compileFailed(pattern: String, message: String)
    case searchFailed(code: Int)
    
    public var errorDescription: String? {
        switch self {
        case .compileFailed(let pattern, let message):
            return "Failed to compile pattern '\(pattern)': \(message)"
        case .searchFailed(let code):
            return "Search failed with code \(code)"
        }
    }
}

// MARK: - OnigScanner

/// Multi-pattern scanner using Oniguruma.
///
/// This matches the interface expected by TextMate grammars,
/// similar to vscode-textmate's OnigScanner.
public final class OnigScanner: @unchecked Sendable {
    private let regexes: [OnigRegex]
    
    /// Create a scanner with multiple patterns.
    /// - Parameter patterns: Array of regex pattern strings
    /// - Throws: If any pattern fails to compile
    public init(patterns: [String]) throws {
        self.regexes = try patterns.map { try OnigRegex(pattern: $0) }
    }
    
    /// Find the next match starting from the given position.
    /// - Parameters:
    ///   - string: The string to search
    ///   - startPosition: UTF-8 byte offset to start from
    /// - Returns: Scanner match result or nil
    public func findNextMatch(in string: String, from startPosition: Int) -> OnigScannerMatch? {
        var bestMatch: OnigScannerMatch?
        var bestPosition = Int.max
        
        for (index, regex) in regexes.enumerated() {
            if let match = regex.search(in: string, from: startPosition) {
                if match.start < bestPosition {
                    bestPosition = match.start
                    bestMatch = OnigScannerMatch(
                        patternIndex: index,
                        captures: match.captures
                    )
                }
            }
        }
        
        return bestMatch
    }
}

// MARK: - OnigScannerMatch

/// Result from OnigScanner.findNextMatch.
public struct OnigScannerMatch: Sendable, Equatable {
    /// Index of the pattern that matched.
    public let patternIndex: Int
    
    /// Capture groups from the match.
    public let captures: [OnigCapture]
    
    /// Start position of the full match.
    public var start: Int {
        captures.first?.start ?? 0
    }
    
    /// End position of the full match.
    public var end: Int {
        captures.first?.end ?? 0
    }
}
