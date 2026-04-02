// ThemeResolver.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Resolves TextMate scopes to colors using the theme's token rules.
// Implements the TextMate scope matching algorithm.

import Foundation
import SwiftUI

// MARK: - Theme Resolver

/// Resolves token scopes to colors using TextMate scope matching
public final class ThemeResolver: Sendable {
    /// The theme being resolved against
    public let theme: ShikiTheme

    /// Default foreground color
    public let defaultForeground: String

    /// Default background color
    public let defaultBackground: String

    /// Cache of resolved styles (scope path → style)
    private let cache: Cache

    // MARK: - Initialization

    public init(theme: ShikiTheme) {
        self.theme = theme

        // Extract defaults from theme
        self.defaultForeground = theme.editorForeground ?? (theme.isDark ? "#d4d4d4" : "#333333")
        self.defaultBackground = theme.editorBackground ?? (theme.isDark ? "#1e1e1e" : "#ffffff")

        self.cache = Cache()
    }

    // MARK: - Resolution

    /// Resolve scopes to a style
    public func resolve(scopes: [String]) -> ResolvedStyle {
        // Create cache key from scope path
        let key = scopes.joined(separator: " ")

        // Check cache
        if let cached = cache.get(key) {
            return cached
        }

        // Find best matching rule
        var bestRule: TokenColorRule?
        var bestScore = -1

        for rule in theme.tokenColors ?? [] {
            guard let ruleScopes = rule.scope?.scopes else { continue }

            for ruleScope in ruleScopes {
                let score = matchScore(ruleScope: ruleScope, tokenScopes: scopes)
                if score > bestScore || (score == bestScore && score != -1) {
                    bestScore = score
                    bestRule = rule
                }
            }
        }

        // Build resolved style
        let style = ResolvedStyle(
            foreground: bestRule?.settings.foreground ?? defaultForeground,
            background: bestRule?.settings.background,
            fontStyle: FontStyle.parse(bestRule?.settings.fontStyle)
        )

        // Cache and return
        cache.set(key, value: style)
        return style
    }

    // MARK: - Scope Matching

    /// Calculate match score between rule scope and token scopes
    ///
    /// TextMate scope matching algorithm:
    /// - Scopes are matched from most specific (deepest) to least specific
    /// - Exact matches score higher than prefix matches
    /// - Deeper matches score higher than shallow matches
    private func matchScore(ruleScope: String, tokenScopes: [String]) -> Int {
        // Rule scope: "keyword.control" or "keyword.control.import"
        // Token scopes: ["source.swift", "meta.function", "keyword.control.return"]

        // Handle comma-separated selectors (e.g., "keyword, storage")
        let selectors = ruleScope.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        var maxScore = -1

        for selector in selectors {
            let score = matchSelector(selector, tokenScopes: tokenScopes)
            maxScore = max(maxScore, score)
        }

        return maxScore
    }

    private func matchSelector(_ selector: String, tokenScopes: [String]) -> Int {
        let parts = selector
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var segments: [[String]] = [[]]
        for part in parts {
            if part == "-" {
                segments.append([])
            } else {
                segments[segments.count - 1].append(part)
            }
        }

        let include = segments.first?.joined(separator: " ") ?? ""
        let excludes = segments.dropFirst().map { $0.joined(separator: " ") }.filter { !$0.isEmpty }

        let includeScore = matchSequence(include, tokenScopes: tokenScopes)
        guard includeScore >= 0 else { return -1 }

        for exclude in excludes where matchSequence(exclude, tokenScopes: tokenScopes) >= 0 {
            return -1
        }

        return includeScore
    }

    private func matchSequence(_ selector: String, tokenScopes: [String]) -> Int {
        let parts = selector
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !parts.isEmpty, !tokenScopes.isEmpty else { return -1 }

        var totalSpecificity = 0
        var lastPartScore = 0
        var lastMatchIndex = -1

        for part in parts {
            var matched = false
            for scopeIndex in (lastMatchIndex + 1)..<tokenScopes.count {
                let tokenScope = tokenScopes[scopeIndex]
                if let result = matchSingleSelector(part, tokenScope: tokenScope) {
                    totalSpecificity += result.specificity
                    lastPartScore = result.score
                    lastMatchIndex = scopeIndex
                    matched = true
                    break
                }
            }

            if !matched {
                return -1
            }
        }

        // Prioritize deeper scope matches over selector specificity to mirror TextMate ordering.
        return (lastMatchIndex + 1) * 1_000_000
            + lastPartScore * 1_000
            + totalSpecificity * 10
            + parts.count
    }

    private func matchSingleSelector(_ selector: String, tokenScope: String) -> (score: Int, specificity: Int)? {
        let specificity = selector.split(separator: ".").count

        if tokenScope == selector {
            return (score: 300 + specificity, specificity: specificity)
        }

        if tokenScope.hasPrefix(selector + ".") {
            return (score: 200 + specificity, specificity: specificity)
        }

        if selector.hasPrefix(tokenScope + ".") {
            return (score: 100 + specificity, specificity: specificity)
        }

        return nil
    }
}

// MARK: - Resolved Style

/// A fully resolved style from theme resolution
public struct ResolvedStyle: Sendable, Equatable {
    /// Foreground color (hex)
    public let foreground: String

    /// Background color (hex, optional)
    public let background: String?

    /// Font style flags
    public let fontStyle: FontStyle

    public init(foreground: String, background: String? = nil, fontStyle: FontStyle = []) {
        self.foreground = foreground
        self.background = background
        self.fontStyle = fontStyle
    }
}

// MARK: - Cache

/// Thread-safe LRU cache for resolved styles.
private final class Cache: @unchecked Sendable {
    private var storage: [String: ResolvedStyle] = [:]
    private let lock = NSLock()
    private let maxSize = 1000

    func get(_ key: String) -> ResolvedStyle? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, value: ResolvedStyle) {
        lock.lock()
        defer { lock.unlock() }

        // Simple eviction - clear half when full
        if storage.count >= maxSize {
            let keysToRemove = Array(storage.keys.prefix(maxSize / 2))
            for k in keysToRemove {
                storage.removeValue(forKey: k)
            }
        }

        storage[key] = value
    }
}

// MARK: - SwiftUI Color Extension

public extension Color {
    /// Create Color from hex string
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        var alpha: Double = 1.0

        switch hexString.count {
        case 6: // RRGGBB
            Scanner(string: hexString).scanHexInt64(&rgb)
        case 8: // RRGGBBAA
            Scanner(string: hexString).scanHexInt64(&rgb)
            alpha = Double(rgb & 0xFF) / 255.0
            rgb >>= 8
        case 3: // RGB shorthand
            Scanner(string: hexString).scanHexInt64(&rgb)
            let r = (rgb >> 8) & 0xF
            let g = (rgb >> 4) & 0xF
            let b = rgb & 0xF
            rgb = (r << 20) | (r << 16) | (g << 12) | (g << 8) | (b << 4) | b
        default:
            return nil
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}
