// ThemeRegistry.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Manages loading and caching of themes, and tracks the current theme.

import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.devys.syntax", category: "ThemeRegistry")

// MARK: - Theme Registry

@MainActor
public protocol ThemeService: AnyObject, Sendable {
    var currentTheme: ShikiTheme? { get }
    var currentResolver: ThemeResolver? { get }
    var currentThemeName: String { get set }

    func loadTheme(name: String)
    func resolver(for themeName: String?) -> ThemeResolver?
    func clearCache()
}

/// Registry for loading and managing themes
@MainActor
@Observable
public final class ThemeRegistry: ThemeService {
    /// Currently loaded theme
    public private(set) var currentTheme: ShikiTheme?

    /// Current theme resolver
    public private(set) var currentResolver: ThemeResolver?

    /// Name of the current theme
    public var currentThemeName: String = "github-dark" {
        didSet {
            if oldValue != currentThemeName {
                loadTheme(name: currentThemeName)
                saveThemePreference()
            }
        }
    }

    /// Cached themes
    private var themes: [String: ShikiTheme] = [:]

    /// Cached resolvers
    private var resolvers: [String: ThemeResolver] = [:]

    /// Bundle to load from
    private let bundle: Bundle

    // MARK: - Initialization

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? Bundle.moduleBundle
        loadThemePreference()
        loadTheme(name: currentThemeName)
    }

    // MARK: - Theme Loading

    /// Load and activate a theme by name
    public func loadTheme(name: String) {
        do {
            // Check cache
            if let cached = themes[name] {
                currentTheme = cached
                currentResolver = resolvers[name] ?? ThemeResolver(theme: cached)
                return
            }

            // Load from bundle
            let theme = try ShikiTheme.load(name: name, bundle: bundle)
            let resolver = ThemeResolver(theme: theme)

            // Cache
            themes[name] = theme
            resolvers[name] = resolver

            // Activate
            currentTheme = theme
            currentResolver = resolver

        } catch {
            logger.error("Failed to load theme '\(name)': \(error)")

            // Try fallback
            if name != "github-dark" {
                loadTheme(name: "github-dark")
            }
        }
    }

    /// Get resolver for a specific theme
    public func resolver(for themeName: String? = nil) -> ThemeResolver? {
        let name = themeName ?? currentThemeName

        if let cached = resolvers[name] {
            return cached
        }

        // Try to load
        loadTheme(name: name)
        return resolvers[name]
    }

    /// Clear theme cache
    public func clearCache() {
        themes.removeAll()
        resolvers.removeAll()

        // Reload current
        loadTheme(name: currentThemeName)
    }

    // MARK: - Persistence

    private func saveThemePreference() {
        UserDefaults.standard.set(currentThemeName, forKey: "Syntax.themeName")
    }

    private func loadThemePreference() {
        if let saved = UserDefaults.standard.string(forKey: "Syntax.themeName") {
            currentThemeName = saved
        }
    }
}
