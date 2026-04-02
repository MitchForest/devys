// TMGrammar.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Represents a TextMate grammar for syntax highlighting.
// Compatible with VS Code/Shiki grammar JSON files.

import Foundation

// MARK: - Grammar

/// TextMate grammar representation
public struct TMGrammar: Codable, Sendable {
    /// Display name of the grammar
    public let name: String

    /// Root scope name (e.g., "source.swift")
    public let scopeName: String

    /// Top-level patterns to match
    public let patterns: [TMPattern]

    /// Named pattern repository for reuse
    public let repository: [String: TMRepositoryPattern]?

    /// Injection rules for embedding languages
    public let injections: [String: TMPattern]?

    /// File extensions this grammar handles
    public let fileTypes: [String]?

    /// Regex to match first line of file for detection
    public let firstLineMatch: String?

    /// Folding markers
    public let foldingStartMarker: String?
    public let foldingStopMarker: String?
}

// MARK: - Pattern

/// A single TextMate pattern rule
public struct TMPattern: Codable, Sendable {
    // MARK: Simple Match

    /// Single-line regex pattern
    public let match: String?

    /// Scope name for the entire match
    public let name: String?

    /// Scopes for capture groups
    public let captures: [String: TMCapture]?

    // MARK: Begin/End Pair

    /// Opening pattern for a range
    public let begin: String?

    /// Closing pattern for a range
    public let end: String?

    /// Scopes for begin captures
    public let beginCaptures: [String: TMCapture]?

    /// Scopes for end captures
    public let endCaptures: [String: TMCapture]?

    /// Scope for content between begin/end
    public let contentName: String?

    // MARK: While Pattern (for heredocs, etc.)

    /// Pattern that must continue to match
    public let `while`: String?

    /// Scopes for while captures
    public let whileCaptures: [String: TMCapture]?

    // MARK: Nested Patterns

    /// Child patterns to apply within this pattern
    public let patterns: [TMPattern]?

    /// Apply end pattern after nested patterns (TextMate behavior)
    public let applyEndPatternLast: Int?

    /// Nested repository for this pattern
    public let repository: [String: TMRepositoryPattern]?

    // MARK: Repository Reference

    /// Reference to repository pattern (#name, $self, $base)
    public let include: String?

    // MARK: Disabled Pattern

    /// If true, pattern is disabled
    public let disabled: Bool?

    /// Pattern type classification
    public var patternType: PatternType {
        if include != nil {
            return .include
        } else if begin != nil {
            return .beginEnd
        } else if match != nil {
            return .match
        } else if patterns != nil {
            return .container
        }
        return .unknown
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case match
        case name
        case captures
        case begin
        case end
        case beginCaptures
        case endCaptures
        case contentName
        case `while`
        case whileCaptures
        case patterns
        case applyEndPatternLast
        case repository
        case include
        case disabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.match = try container.decodeIfPresent(String.self, forKey: .match)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.captures = try container.decodeIfPresent([String: TMCapture].self, forKey: .captures)
        self.begin = try container.decodeIfPresent(String.self, forKey: .begin)
        self.end = try container.decodeIfPresent(String.self, forKey: .end)
        self.beginCaptures = try container.decodeIfPresent([String: TMCapture].self, forKey: .beginCaptures)
        self.endCaptures = try container.decodeIfPresent([String: TMCapture].self, forKey: .endCaptures)
        self.contentName = try container.decodeIfPresent(String.self, forKey: .contentName)
        self.while = try container.decodeIfPresent(String.self, forKey: .while)
        self.whileCaptures = try container.decodeIfPresent([String: TMCapture].self, forKey: .whileCaptures)
        self.patterns = try container.decodeIfPresent([TMPattern].self, forKey: .patterns)
        self.repository = try container.decodeIfPresent([String: TMRepositoryPattern].self, forKey: .repository)

        if let intValue = try? container.decodeIfPresent(Int.self, forKey: .applyEndPatternLast) {
            self.applyEndPatternLast = intValue
        } else if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .applyEndPatternLast) {
            self.applyEndPatternLast = boolValue ? 1 : 0
        } else {
            self.applyEndPatternLast = nil
        }

        self.include = try container.decodeIfPresent(String.self, forKey: .include)
        self.disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
    }

    public init(
        match: String?,
        name: String?,
        captures: [String: TMCapture]?,
        begin: String?,
        end: String?,
        beginCaptures: [String: TMCapture]?,
        endCaptures: [String: TMCapture]?,
        contentName: String?,
        while: String?,
        whileCaptures: [String: TMCapture]?,
        patterns: [TMPattern]?,
        applyEndPatternLast: Int?,
        repository: [String: TMRepositoryPattern]?,
        include: String?,
        disabled: Bool?
    ) {
        self.match = match
        self.name = name
        self.captures = captures
        self.begin = begin
        self.end = end
        self.beginCaptures = beginCaptures
        self.endCaptures = endCaptures
        self.contentName = contentName
        self.while = `while`
        self.whileCaptures = whileCaptures
        self.patterns = patterns
        self.applyEndPatternLast = applyEndPatternLast
        self.repository = repository
        self.include = include
        self.disabled = disabled
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(match, forKey: .match)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(captures, forKey: .captures)
        try container.encodeIfPresent(begin, forKey: .begin)
        try container.encodeIfPresent(end, forKey: .end)
        try container.encodeIfPresent(beginCaptures, forKey: .beginCaptures)
        try container.encodeIfPresent(endCaptures, forKey: .endCaptures)
        try container.encodeIfPresent(contentName, forKey: .contentName)
        try container.encodeIfPresent(self.`while`, forKey: .while)
        try container.encodeIfPresent(whileCaptures, forKey: .whileCaptures)
        try container.encodeIfPresent(patterns, forKey: .patterns)
        try container.encodeIfPresent(applyEndPatternLast, forKey: .applyEndPatternLast)
        try container.encodeIfPresent(repository, forKey: .repository)
        try container.encodeIfPresent(include, forKey: .include)
        try container.encodeIfPresent(disabled, forKey: .disabled)
    }
}

/// Classification of pattern types
public enum PatternType: Sendable {
    case match      // Simple regex match
    case beginEnd   // Begin/end pair
    case include    // Repository reference
    case container  // Only contains nested patterns
    case unknown
}

// MARK: - Repository Pattern

/// Repository entry - can be a pattern or patterns array
public enum TMRepositoryPattern: Codable, Sendable {
    case pattern(TMPattern)
    case patterns([TMPattern])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as a pattern with "patterns" array
        if let pattern = try? container.decode(TMPattern.self) {
            // Check if it's really just a patterns wrapper
            if let patterns = pattern.patterns,
               pattern.match == nil,
               pattern.begin == nil,
               pattern.include == nil,
               pattern.repository == nil {
                self = .patterns(patterns)
            } else {
                self = .pattern(pattern)
            }
        } else {
            throw DecodingError.typeMismatch(
                TMRepositoryPattern.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected TMPattern")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .pattern(let pattern):
            try container.encode(pattern)
        case .patterns(let patterns):
            try container.encode(
                TMPattern(
                    match: nil,
                    name: nil,
                    captures: nil,
                    begin: nil,
                    end: nil,
                    beginCaptures: nil,
                    endCaptures: nil,
                    contentName: nil,
                    while: nil,
                    whileCaptures: nil,
                    patterns: patterns,
                    applyEndPatternLast: nil,
                    repository: nil,
                    include: nil,
                    disabled: nil
                )
            )
        }
    }

    /// Get patterns from this repository entry
    public var asPatterns: [TMPattern] {
        switch self {
        case .pattern(let pattern):
            return [pattern]
        case .patterns(let patterns):
            return patterns
        }
    }
}

// MARK: - Capture

/// Scope assignment for a capture group
public struct TMCapture: Codable, Sendable {
    /// Scope name for this capture
    public let name: String?

    /// Nested patterns within this capture
    public let patterns: [TMPattern]?
}

// MARK: - Extensions

public extension TMGrammar {
    /// Load grammar from bundle resource
    static func load(languageId: String, bundle: Bundle? = nil) throws -> TMGrammar {
        let resourceBundle = bundle ?? Bundle.moduleBundle

        // Try with subdirectory first (for app bundles), then without (for SPM)
        var url = resourceBundle.url(forResource: languageId, withExtension: "json", subdirectory: "Grammars")
        if url == nil {
            url = resourceBundle.url(forResource: languageId, withExtension: "json")
        }

        guard let grammarURL = url else {
            throw TMError.grammarNotFound(languageId)
        }

        let data = try Data(contentsOf: grammarURL)
        let decoder = JSONDecoder()
        return try decoder.decode(TMGrammar.self, from: data)
    }

    /// Load grammar from file URL
    static func load(from url: URL) throws -> TMGrammar {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(TMGrammar.self, from: data)
    }
}

// MARK: - Errors

public enum TMError: Error, LocalizedError {
    case grammarNotFound(String)
    case invalidGrammar(String)
    case regexCompileFailed(String)
    case tokenizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .grammarNotFound(let id):
            return "Grammar not found: \(id)"
        case .invalidGrammar(let reason):
            return "Invalid grammar: \(reason)"
        case .regexCompileFailed(let pattern):
            return "Failed to compile regex: \(pattern)"
        case .tokenizationFailed(let reason):
            return "Tokenization failed: \(reason)"
        }
    }
}
