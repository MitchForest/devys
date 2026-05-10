import Foundation
import UI

public enum SyntaxThemeAppearance: String, Codable, Sendable {
    case dark
    case light
}

public struct SyntaxThemeTokenStyle: Codable, Sendable, Equatable {
    public let foreground: String?
    public let background: String?
    public let fontStyle: String?

    public init(
        foreground: String? = nil,
        background: String? = nil,
        fontStyle: String? = nil
    ) {
        self.foreground = foreground
        self.background = background
        self.fontStyle = fontStyle
    }

    public var resolvedFontStyle: FontStyle {
        FontStyle.parse(fontStyle)
    }
}

public struct SyntaxThemeResolvedStyle: Sendable, Equatable {
    public let foreground: String
    public let background: String?
    public let fontStyle: FontStyle

    public init(
        foreground: String,
        background: String? = nil,
        fontStyle: FontStyle = []
    ) {
        self.foreground = foreground
        self.background = background
        self.fontStyle = fontStyle
    }
}

public struct SyntaxTheme: Codable, Sendable, Equatable {
    public let name: String
    public let appearance: SyntaxThemeAppearance
    public let defaultForeground: String
    public let defaultBackground: String
    public let colors: [String: String]
    public let styles: [String: SyntaxThemeTokenStyle]

    public init(
        name: String,
        appearance: SyntaxThemeAppearance,
        defaultForeground: String,
        defaultBackground: String,
        colors: [String: String] = [:],
        styles: [String: SyntaxThemeTokenStyle]
    ) {
        self.name = name
        self.appearance = appearance
        self.defaultForeground = defaultForeground
        self.defaultBackground = defaultBackground
        self.colors = colors
        self.styles = styles
    }

    public init(design: CodeSyntaxThemeDesign) {
        self.init(
            name: design.name,
            appearance: design.colorScheme == .dark ? .dark : .light,
            defaultForeground: design.defaultForeground,
            defaultBackground: design.defaultBackground,
            colors: design.colors,
            styles: design.styles.mapValues {
                SyntaxThemeTokenStyle(
                    foreground: $0.foreground,
                    background: $0.background,
                    fontStyle: $0.fontStyle
                )
            }
        )
    }

    public var isDark: Bool {
        appearance == .dark
    }

    public var editorBackground: String {
        requiredColor("editor.background")
    }

    public var editorForeground: String {
        requiredColor("editor.foreground")
    }

    public var lineNumberForeground: String? {
        colors["editorLineNumber.foreground"]
    }

    public var gutterBackground: String? {
        colors["editorGutter.background"]
    }

    public var lineHighlightBackground: String? {
        colors["editor.lineHighlightBackground"]
    }

    public var selectionBackground: String? {
        colors["editor.selectionBackground"]
    }

    public var cursorColor: String? {
        colors["editorCursor.foreground"]
    }

    public func requiredColor(_ key: String) -> String {
        guard let color = colors[key] else {
            preconditionFailure("Syntax theme '\(name)' is missing required color '\(key)'")
        }
        return color
    }

    public func resolve(captureNames: [String]) -> SyntaxThemeResolvedStyle {
        var bestMatch: (style: SyntaxThemeTokenStyle, specificity: Int, captureIndex: Int)?

        for (captureIndex, rawCaptureName) in captureNames.enumerated() {
            var candidate = normalizedCaptureName(rawCaptureName)

            while !candidate.isEmpty {
                if let style = styles[candidate] {
                    let specificity = candidate.split(separator: ".").count

                    if let currentBestMatch = bestMatch {
                        if specificity > currentBestMatch.specificity ||
                            (
                                specificity == currentBestMatch.specificity &&
                                captureIndex < currentBestMatch.captureIndex
                            ) {
                            bestMatch = (style, specificity, captureIndex)
                        }
                    } else {
                        bestMatch = (style, specificity, captureIndex)
                    }
                }

                guard let separator = candidate.lastIndex(of: ".") else {
                    break
                }

                candidate.removeSubrange(separator...)
            }
        }

        return SyntaxThemeResolvedStyle(
            foreground: bestMatch?.style.foreground ?? defaultForeground,
            background: bestMatch?.style.background,
            fontStyle: bestMatch?.style.resolvedFontStyle ?? []
        )
    }

    public static func load(name: String, bundle: Bundle? = nil) throws -> SyntaxTheme {
        guard let design = CodeSyntaxThemeDesign.theme(named: name) else {
            throw ThemeError.themeNotFound(name)
        }
        return SyntaxTheme(design: design)
    }

    public static func load(from url: URL) throws -> SyntaxTheme {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SyntaxTheme.self, from: data)
    }

    private func normalizedCaptureName(_ captureName: String) -> String {
        if captureName.hasPrefix("@") {
            return String(captureName.dropFirst())
        }

        return captureName
    }
}

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
