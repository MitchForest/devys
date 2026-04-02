// TMToken.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Represents tokens produced by the TextMate tokenizer.

import Foundation

// MARK: - Token

/// A single token from TextMate tokenization
public struct TMToken: Sendable, Equatable {
    /// UTF-16 start index in the line (0-based)
    let startIndex: Int
    
    /// UTF-16 end index in the line
    let endIndex: Int

    /// Scope stack for this token (e.g., ["source.swift", "keyword.control"])
    public let scopes: [String]

    init(startIndex: Int, endIndex: Int, scopes: [String]) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.scopes = scopes
    }

    /// Length of the token
    var length: Int {
        endIndex - startIndex
    }

    /// Range as Swift Range
    public var range: Range<Int> {
        startIndex..<endIndex
    }
}

// MARK: - Tokenize Result

/// Result of tokenizing a single line
public struct TokenizeResult: Sendable {
    /// Tokens found in the line
    public let tokens: [TMToken]

    /// State at end of line (for continuing tokenization)
    public let endState: RuleStack

    public init(tokens: [TMToken], endState: RuleStack) {
        self.tokens = tokens
        self.endState = endState
    }
}

// MARK: - Token with Styling

/// Token with resolved styling information
struct StyledToken: Sendable {
    /// UTF-16 range for the token
    let range: Range<Int>
    
    /// Foreground color (hex)
    let foregroundColor: String?
    
    /// Font style flags
    let fontStyle: FontStyle

    init(
        range: Range<Int>,
        foregroundColor: String? = nil,
        fontStyle: FontStyle = []
    ) {
        self.range = range
        self.foregroundColor = foregroundColor
        self.fontStyle = fontStyle
    }
}

/// Font style flags
public struct FontStyle: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let bold = FontStyle(rawValue: 1 << 0)
    public static let italic = FontStyle(rawValue: 1 << 1)
    public static let underline = FontStyle(rawValue: 1 << 2)
    public static let strikethrough = FontStyle(rawValue: 1 << 3)
}

extension FontStyle {
    /// Parse from TextMate fontStyle string
    static func parse(_ string: String?) -> FontStyle {
        guard let string = string else { return [] }

        var style: FontStyle = []
        let lowercased = string.lowercased()

        if lowercased.contains("bold") {
            style.insert(.bold)
        }
        if lowercased.contains("italic") {
            style.insert(.italic)
        }
        if lowercased.contains("underline") {
            style.insert(.underline)
        }
        if lowercased.contains("strikethrough") {
            style.insert(.strikethrough)
        }

        return style
    }
}
