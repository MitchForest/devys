// ShikiTheme.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Represents a Shiki/VS Code theme for syntax highlighting.
// Loads standard VS Code theme JSON files.

import Foundation

// MARK: - Shiki Theme

/// Shiki/VS Code theme representation
public struct ShikiTheme: Codable, Sendable {
    /// Theme display name
    public let name: String

    /// Theme type (dark or light)
    public let type: ThemeType?

    /// Editor colors (background, foreground, etc.)
    public let colors: [String: String]?

    /// Token coloring rules
    public let tokenColors: [TokenColorRule]?

    /// Semantic token colors (optional)
    public let semanticTokenColors: [String: AnyCodable]?

    /// Semantic highlighting setting
    public let semanticHighlighting: Bool?

    // MARK: - Convenience Accessors

    /// Editor background color
    public var editorBackground: String? {
        colors?["editor.background"]
    }

    /// Editor foreground (default text) color
    public var editorForeground: String? {
        colors?["editor.foreground"]
    }

    /// Line highlight background
    public var lineHighlightBackground: String? {
        colors?["editor.lineHighlightBackground"]
    }

    /// Selection background
    public var selectionBackground: String? {
        colors?["editor.selectionBackground"]
    }

    /// Cursor color
    public var cursorColor: String? {
        colors?["editorCursor.foreground"]
    }

    /// Whether this is a dark theme
    public var isDark: Bool {
        type == .dark
    }
}

// MARK: - Theme Type

public enum ThemeType: String, Codable, Sendable {
    case dark
    case light
    case hc // High contrast
    case hcLight
}

// MARK: - Token Color Rule

/// A single token coloring rule
public struct TokenColorRule: Codable, Sendable {
    /// Optional name for the rule
    public let name: String?

    /// Scope selector (String or [String])
    public let scope: ScopeSelector?

    /// Style settings
    public let settings: TokenSettings
}

// MARK: - Scope Selector

/// Handles scope being String or [String]
public enum ScopeSelector: Codable, Sendable {
    case single(String)
    case multiple([String])

    public var scopes: [String] {
        switch self {
        case .single(let s): return [s]
        case .multiple(let arr): return arr
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .single(string)
        } else if let array = try? container.decode([String].self) {
            self = .multiple(array)
        } else {
            throw DecodingError.typeMismatch(
                ScopeSelector.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Expected String or [String]")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let s): try container.encode(s)
        case .multiple(let arr): try container.encode(arr)
        }
    }
}

// MARK: - Token Settings

/// Style settings for a token
public struct TokenSettings: Codable, Sendable {
    /// Foreground color (hex)
    public let foreground: String?

    /// Background color (hex)
    public let background: String?

    /// Font style (e.g., "bold", "italic", "underline", "bold italic")
    public let fontStyle: String?
}

// MARK: - AnyCodable (for semantic tokens)

/// Type-erased Codable for flexible JSON
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Theme Loading

public extension ShikiTheme {
    /// Load theme from bundle resource
    static func load(name: String, bundle: Bundle? = nil) throws -> ShikiTheme {
        let resourceBundle = bundle ?? Bundle.moduleBundle

        // Try with subdirectory first (for app bundles), then without (for SPM)
        var url = resourceBundle.url(forResource: name, withExtension: "json", subdirectory: "Themes")
        if url == nil {
            url = resourceBundle.url(forResource: name, withExtension: "json")
        }

        guard let themeURL = url else {
            throw ThemeError.themeNotFound(name)
        }

        let data = try Data(contentsOf: themeURL)
        let decoder = JSONDecoder()
        return try decoder.decode(ShikiTheme.self, from: data)
    }

    /// Load theme from file URL
    static func load(from url: URL) throws -> ShikiTheme {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ShikiTheme.self, from: data)
    }
}

// MARK: - Theme Error

public enum ThemeError: Error, LocalizedError {
    case themeNotFound(String)
    case invalidTheme(String)

    public var errorDescription: String? {
        switch self {
        case .themeNotFound(let name):
            return "Theme not found: \(name)"
        case .invalidTheme(let reason):
            return "Invalid theme: \(reason)"
        }
    }
}
