// ThemeRegistry.swift
// Native syntax theme loading and runtime selection.

// periphery:ignore:all - theme/runtime cache helpers are used by app integration and tests
import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.devys.syntax", category: "ThemeRegistry")
private let defaultThemeName = "devys-dark"

public struct RuntimeThemeDescriptor: Sendable, Hashable, Equatable {
    public let name: String
    public let version: Int

    public init(name: String, version: Int) {
        self.name = name
        self.version = version
    }
}

private let supportedThemeDescriptors: [RuntimeThemeDescriptor] = [
    RuntimeThemeDescriptor(name: "devys-dark", version: 1),
    RuntimeThemeDescriptor(name: "devys-light", version: 2)
]
private let supportedThemeDescriptorsByName = Dictionary(
    uniqueKeysWithValues: supportedThemeDescriptors.map { ($0.name, $0) }
)
private let supportedThemeNames = supportedThemeDescriptors.map(\.name)
private let defaultThemeDescriptor = supportedThemeDescriptorsByName[defaultThemeName]
    ?? RuntimeThemeDescriptor(name: defaultThemeName, version: 1)

public enum SyntaxThemeCache {
    private static let state = SyntaxThemeCacheState()

    public static func theme(name: String, bundle: Bundle) -> SyntaxTheme? {
        state.theme(name: name, bundlePath: bundle.bundlePath)
    }

    public static func theme(name: String, bundlePath: String) -> SyntaxTheme? {
        state.theme(name: name, bundlePath: bundlePath)
    }

    static func clearAll() {
        state.clearAll()
    }
}

private final class SyntaxThemeCacheState: @unchecked Sendable {
    private let lock = NSLock()
    private var themesByBundlePath: [String: [String: SyntaxTheme]] = [:]

    func theme(name: String, bundlePath: String) -> SyntaxTheme? {
        lock.lock()
        if let cached = themesByBundlePath[bundlePath]?[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let bundle = Bundle(path: bundlePath) else { return nil }

        do {
            let theme = try SyntaxRuntimeDiagnostics.measureAssetLoad(
                kind: "syntax-theme",
                name: name
            ) {
                try SyntaxTheme.load(name: name, bundle: bundle)
            }

            lock.lock()
            var themes = themesByBundlePath[bundlePath] ?? [:]
            themes[name] = theme
            themesByBundlePath[bundlePath] = themes
            lock.unlock()

            return theme
        } catch {
            return nil
        }
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        themesByBundlePath.removeAll()
    }
}

@MainActor
public protocol ThemeService: AnyObject, Sendable {
    var currentTheme: SyntaxTheme? { get }
    var currentThemeName: String { get set }

    func loadTheme(name: String)
    func clearCache()
}

@MainActor
@Observable
public final class ThemeRegistry: ThemeService {
    public static var supportedThemes: [RuntimeThemeDescriptor] {
        supportedThemeDescriptors
    }

    public static var preferredThemeName: String {
        if let saved = UserDefaults.standard.string(forKey: "Syntax.themeName"),
           supportedThemeNames.contains(saved) {
            return saved
        }
        return defaultThemeName
    }

    public static var preferredThemeDescriptor: RuntimeThemeDescriptor {
        descriptor(name: preferredThemeName)
    }

    public static func descriptor(name: String) -> RuntimeThemeDescriptor {
        supportedThemeDescriptorsByName[name] ?? defaultThemeDescriptor
    }

    public static func cachedTheme(name: String, bundle: Bundle? = nil) -> SyntaxTheme? {
        SyntaxThemeCache.theme(name: name, bundle: bundle ?? Bundle.moduleBundle)
    }

    public static func resolvedTheme(
        name requestedName: String,
        bundle: Bundle? = nil
    ) -> (descriptor: RuntimeThemeDescriptor, theme: SyntaxTheme) {
        let bundle = bundle ?? Bundle.moduleBundle
        guard let requestedDescriptor = supportedThemeDescriptorsByName[requestedName] else {
            preconditionFailure("Unsupported runtime theme '\(requestedName)'")
        }
        guard let theme = cachedTheme(name: requestedDescriptor.name, bundle: bundle) else {
            preconditionFailure("Missing bundled runtime theme '\(requestedDescriptor.name)'")
        }
        return (requestedDescriptor, theme)
    }

    public private(set) var currentTheme: SyntaxTheme?

    private let bundle: Bundle
    private var isUpdatingThemeNameInternally = false

    public var currentThemeName: String = defaultThemeName {
        didSet {
            guard oldValue != currentThemeName else { return }
            guard !isUpdatingThemeNameInternally else { return }
            applyThemeSelection(
                requestedName: currentThemeName,
                fallbackName: oldValue,
                persistPreference: true
            )
        }
    }

    public init(bundle: Bundle? = nil) {
        self.bundle = bundle ?? Bundle.moduleBundle
        currentThemeName = Self.preferredThemeName
        _ = applyThemeSelection(
            requestedName: currentThemeName,
            fallbackName: defaultThemeName,
            persistPreference: false
        )
    }

    public func loadTheme(name: String) {
        _ = applyThemeSelection(
            requestedName: name,
            fallbackName: currentThemeName,
            persistPreference: false
        )
    }

    public func clearCache() {
        SyntaxThemeCache.clearAll()
        currentTheme = nil
        ensureCurrentThemeLoaded()
    }

    private static func canonicalThemeName(for requestedName: String) -> String {
        supportedThemeDescriptorsByName[requestedName]?.name ?? requestedName
    }

    private func setCurrentThemeName(_ name: String) {
        guard currentThemeName != name else { return }
        isUpdatingThemeNameInternally = true
        currentThemeName = name
        isUpdatingThemeNameInternally = false
    }

    private func applyLoadedTheme(
        name: String,
        theme: SyntaxTheme,
        persistPreference: Bool
    ) {
        currentTheme = theme
        setCurrentThemeName(name)
        if persistPreference {
            saveThemePreference()
        }
    }

    @discardableResult
    private func applyThemeSelection(
        requestedName: String,
        fallbackName: String?,
        persistPreference: Bool
    ) -> Bool {
        let canonicalName = Self.canonicalThemeName(for: requestedName)
        if let theme = Self.cachedTheme(name: canonicalName, bundle: bundle) {
            applyLoadedTheme(
                name: canonicalName,
                theme: theme,
                persistPreference: persistPreference
            )
            return true
        }

        logger.error("Failed to load theme '\(requestedName)'")

        if let fallbackName,
           fallbackName != requestedName,
           let theme = Self.cachedTheme(name: fallbackName, bundle: bundle) {
            applyLoadedTheme(
                name: fallbackName,
                theme: theme,
                persistPreference: persistPreference
            )
            return false
        }

        if requestedName != defaultThemeName,
           let theme = Self.cachedTheme(name: defaultThemeName, bundle: bundle) {
            logger.error("Falling back to default theme '\(defaultThemeName)' after load failure")
            applyLoadedTheme(
                name: defaultThemeName,
                theme: theme,
                persistPreference: persistPreference
            )
            return false
        }

        assertionFailure("No bundled syntax theme could be loaded")
        return false
    }

    private func ensureCurrentThemeLoaded() {
        if currentTheme == nil {
            _ = applyThemeSelection(
                requestedName: currentThemeName,
                fallbackName: defaultThemeName,
                persistPreference: false
            )
        }
    }

    private func saveThemePreference() {
        UserDefaults.standard.set(currentThemeName, forKey: "Syntax.themeName")
    }
}
