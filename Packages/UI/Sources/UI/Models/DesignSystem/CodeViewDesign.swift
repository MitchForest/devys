import CoreGraphics
import SwiftUI

public enum CodeViewColorScheme: Sendable, Equatable {
    case light
    case dark

    public init(colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    public var syntaxThemeName: String {
        switch self {
        case .light:
            "devys-light"
        case .dark:
            "devys-dark"
        }
    }
}

public struct CodeViewDesign: Sendable, Equatable {
    public let fontName: String
    public let fontSize: CGFloat
    public let lineHeight: CGFloat
    public let tabWidth: Int
    public let insertSpacesForTab: Bool
    public let syntaxThemeName: String
    public let surfaceDesign: CodeSurfaceDesign

    public init(
        colorScheme: CodeViewColorScheme,
        fontName: String = Self.fontName,
        fontSize: CGFloat = Self.fontSize,
        lineHeight: CGFloat = Self.lineHeight,
        tabWidth: Int = Self.tabWidth,
        insertSpacesForTab: Bool = Self.insertSpacesForTab,
        surfaceDesign: CodeSurfaceDesign = Self.surfaceDesign
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.tabWidth = tabWidth
        self.insertSpacesForTab = insertSpacesForTab
        self.syntaxThemeName = colorScheme.syntaxThemeName
        self.surfaceDesign = surfaceDesign
    }

    public static let fontName = "Menlo-Regular"
    public static let fontSize: CGFloat = 13
    public static let lineHeight: CGFloat = 16
    public static let tabWidth = 4
    public static let insertSpacesForTab = true
    public static let surfaceDesign = CodeSurfaceDesign.glass

    public static let dark = CodeViewDesign(colorScheme: .dark)
    public static let light = CodeViewDesign(colorScheme: .light)

    public static func resolved(for colorScheme: ColorScheme) -> CodeViewDesign {
        CodeViewDesign(colorScheme: CodeViewColorScheme(colorScheme: colorScheme))
    }
}

public struct CodeSurfaceDesign: Sendable, Equatable {
    public let usesGlassBackground: Bool
    public let defaultBackgroundOpacity: CGFloat
    public let hunkHeaderBackgroundOpacity: CGFloat
    public let dividerOpacity: CGFloat

    public init(
        usesGlassBackground: Bool,
        defaultBackgroundOpacity: CGFloat,
        hunkHeaderBackgroundOpacity: CGFloat,
        dividerOpacity: CGFloat
    ) {
        self.usesGlassBackground = usesGlassBackground
        self.defaultBackgroundOpacity = defaultBackgroundOpacity
        self.hunkHeaderBackgroundOpacity = hunkHeaderBackgroundOpacity
        self.dividerOpacity = dividerOpacity
    }

    public static let glass = CodeSurfaceDesign(
        usesGlassBackground: true,
        defaultBackgroundOpacity: 0,
        hunkHeaderBackgroundOpacity: 0.36,
        dividerOpacity: 0.55
    )
}

public struct CodeSyntaxTokenStyleDesign: Sendable, Equatable {
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
}

public struct CodeDiffDesign: Sendable, Equatable {
    public let changeBarWidth: CGFloat
    public let deletedChangeBarDashHeight: CGFloat
    public let deletedChangeBarDashStride: CGFloat

    public init(
        changeBarWidth: CGFloat = Self.changeBarWidth,
        deletedChangeBarDashHeight: CGFloat = Self.deletedChangeBarDashHeight,
        deletedChangeBarDashStride: CGFloat = Self.deletedChangeBarDashStride
    ) {
        self.changeBarWidth = changeBarWidth
        self.deletedChangeBarDashHeight = deletedChangeBarDashHeight
        self.deletedChangeBarDashStride = deletedChangeBarDashStride
    }

    public static let changeBarWidth: CGFloat = 4
    public static let deletedChangeBarDashHeight: CGFloat = 1
    public static let deletedChangeBarDashStride: CGFloat = 2

    public static let `default` = CodeDiffDesign()
}

public struct CodeSyntaxThemeDesign: Sendable, Equatable {
    public let name: String
    public let colorScheme: CodeViewColorScheme
    public let defaultForeground: String
    public let defaultBackground: String
    public let colors: [String: String]
    public let styles: [String: CodeSyntaxTokenStyleDesign]

    public init(
        name: String,
        colorScheme: CodeViewColorScheme,
        defaultForeground: String,
        defaultBackground: String,
        colors: [String: String],
        styles: [String: CodeSyntaxTokenStyleDesign]
    ) {
        self.name = name
        self.colorScheme = colorScheme
        self.defaultForeground = defaultForeground
        self.defaultBackground = defaultBackground
        self.colors = colors
        self.styles = styles
    }

    public static let dark = CodeSyntaxThemeDesign(
        name: "devys-dark",
        colorScheme: .dark,
        defaultForeground: "#E6E0D8",
        defaultBackground: "#050505",
        colors: [
            "editor.background": "#050505",
            "editor.foreground": "#E6E0D8",
            "editorLineNumber.foreground": "#6A6A6A",
            "editorGutter.background": "#050505",
            "editor.lineHighlightBackground": "#1A1A1A",
            "editor.selectionBackground": "#FFFFFF26",
            "editor.findMatchBackground": "#E6B56A57",
            "editor.findMatchHighlightBackground": "#E6B56A2E",
            "editorCursor.foreground": "#F5F0E8",
            "gitDecoration.addedResourceForeground": "#5ECC71",
            "gitDecoration.deletedResourceForeground": "#FF6762",
            "diffEditor.border": "#1F1F1F",
            "diffEditor.insertedLineBackground": "#5ECC711F",
            "diffEditor.removedLineBackground": "#FF67621F",
            "diffEditor.insertedTextBackground": "#5ECC712E",
            "diffEditor.removedTextBackground": "#FF67622E",
            "diffEditorGutter.insertedLineBackground": "#5ECC711A",
            "diffEditorGutter.removedLineBackground": "#FF67621A"
        ],
        styles: Self.darkStyles
    )

    public static let light = CodeSyntaxThemeDesign(
        name: "devys-light",
        colorScheme: .light,
        defaultForeground: "#1C1B19",
        defaultBackground: "#FAF7F1",
        colors: [
            "editor.background": "#FAF7F1",
            "editor.foreground": "#1C1B19",
            "editorLineNumber.foreground": "#8E8A82",
            "editorGutter.background": "#FAF7F1",
            "editor.lineHighlightBackground": "#ECEAE6",
            "editor.selectionBackground": "#1C1B1926",
            "editor.findMatchBackground": "#8B5F1F57",
            "editor.findMatchHighlightBackground": "#8B5F1F2E",
            "editorCursor.foreground": "#1C1B19",
            "gitDecoration.addedResourceForeground": "#0D8A3B",
            "gitDecoration.deletedResourceForeground": "#C2313B",
            "diffEditor.border": "#D5CEC2",
            "diffEditor.insertedLineBackground": "#0DBE4E1A",
            "diffEditor.removedLineBackground": "#FF2E3F1A",
            "diffEditor.insertedTextBackground": "#0DBE4E26",
            "diffEditor.removedTextBackground": "#FF2E3F26",
            "diffEditorGutter.insertedLineBackground": "#0DBE4E14",
            "diffEditorGutter.removedLineBackground": "#FF2E3F14"
        ],
        styles: Self.lightStyles
    )

    public static let supportedThemes = [Self.dark, Self.light]

    public static func theme(named name: String) -> CodeSyntaxThemeDesign? {
        supportedThemes.first { $0.name == name }
    }

    private static let darkStyles: [String: CodeSyntaxTokenStyleDesign] = [
        "comment": CodeSyntaxTokenStyleDesign(foreground: "#747474", fontStyle: "italic"),
        "constant": CodeSyntaxTokenStyleDesign(foreground: "#E6B56A"),
        "function": CodeSyntaxTokenStyleDesign(foreground: "#B596FF"),
        "keyword": CodeSyntaxTokenStyleDesign(foreground: "#D979C6"),
        "link_text.markup": CodeSyntaxTokenStyleDesign(foreground: "#B596FF"),
        "link_uri.markup": CodeSyntaxTokenStyleDesign(foreground: "#B596FF", fontStyle: "underline"),
        "text.reference": CodeSyntaxTokenStyleDesign(foreground: "#B596FF"),
        "text.uri": CodeSyntaxTokenStyleDesign(foreground: "#B596FF", fontStyle: "underline"),
        "text.title": CodeSyntaxTokenStyleDesign(foreground: "#F5F0E8", fontStyle: "bold"),
        "text.emphasis": CodeSyntaxTokenStyleDesign(foreground: "#E6E0D8", fontStyle: "italic"),
        "text.strong": CodeSyntaxTokenStyleDesign(foreground: "#F5F0E8", fontStyle: "bold"),
        "text.literal": CodeSyntaxTokenStyleDesign(foreground: "#8CCF7E"),
        "markup": CodeSyntaxTokenStyleDesign(foreground: "#BDB7AE"),
        "number": CodeSyntaxTokenStyleDesign(foreground: "#E6B56A"),
        "operator": CodeSyntaxTokenStyleDesign(foreground: "#D979C6"),
        "property": CodeSyntaxTokenStyleDesign(foreground: "#E6A66A"),
        "punctuation": CodeSyntaxTokenStyleDesign(foreground: "#7A7A7A"),
        "punctuation.delimiter": CodeSyntaxTokenStyleDesign(foreground: "#7A7A7A"),
        "punctuation.special": CodeSyntaxTokenStyleDesign(foreground: "#D979C6", fontStyle: "bold"),
        "string": CodeSyntaxTokenStyleDesign(foreground: "#8CCF7E"),
        "string.special": CodeSyntaxTokenStyleDesign(foreground: "#8CCF7E"),
        "text.literal.markup": CodeSyntaxTokenStyleDesign(foreground: "#8CCF7E"),
        "title.markup": CodeSyntaxTokenStyleDesign(foreground: "#F5F0E8", fontStyle: "bold"),
        "type": CodeSyntaxTokenStyleDesign(foreground: "#9D8CFF"),
        "type.builtin": CodeSyntaxTokenStyleDesign(foreground: "#9D8CFF"),
        "variable": CodeSyntaxTokenStyleDesign(foreground: "#E6A66A"),
        "variable.parameter": CodeSyntaxTokenStyleDesign(foreground: "#E6B56A"),
        "emphasis.markup": CodeSyntaxTokenStyleDesign(foreground: "#E6E0D8", fontStyle: "italic"),
        "emphasis.strong.markup": CodeSyntaxTokenStyleDesign(foreground: "#F5F0E8", fontStyle: "bold"),
        "strikethrough.markup": CodeSyntaxTokenStyleDesign(foreground: "#7A7A7A"),
        "punctuation.markup": CodeSyntaxTokenStyleDesign(foreground: "#7A7A7A"),
        "punctuation.list_marker.markup": CodeSyntaxTokenStyleDesign(foreground: "#BDB7AE"),
        "punctuation.embedded.markup": CodeSyntaxTokenStyleDesign(foreground: "#7A7A7A")
    ]

    private static let lightStyles: [String: CodeSyntaxTokenStyleDesign] = [
        "comment": CodeSyntaxTokenStyleDesign(foreground: "#8E8A82", fontStyle: "italic"),
        "constant": CodeSyntaxTokenStyleDesign(foreground: "#8B5F1F"),
        "function": CodeSyntaxTokenStyleDesign(foreground: "#704CB8"),
        "keyword": CodeSyntaxTokenStyleDesign(foreground: "#A33C91"),
        "link_text.markup": CodeSyntaxTokenStyleDesign(foreground: "#704CB8"),
        "link_uri.markup": CodeSyntaxTokenStyleDesign(foreground: "#704CB8", fontStyle: "underline"),
        "text.reference": CodeSyntaxTokenStyleDesign(foreground: "#704CB8"),
        "text.uri": CodeSyntaxTokenStyleDesign(foreground: "#704CB8", fontStyle: "underline"),
        "text.title": CodeSyntaxTokenStyleDesign(foreground: "#1F1A16", fontStyle: "bold"),
        "text.emphasis": CodeSyntaxTokenStyleDesign(foreground: "#1C1B19", fontStyle: "italic"),
        "text.strong": CodeSyntaxTokenStyleDesign(foreground: "#1F1A16", fontStyle: "bold"),
        "text.literal": CodeSyntaxTokenStyleDesign(foreground: "#2E7D32"),
        "markup": CodeSyntaxTokenStyleDesign(foreground: "#3D362F"),
        "number": CodeSyntaxTokenStyleDesign(foreground: "#8B5F1F"),
        "operator": CodeSyntaxTokenStyleDesign(foreground: "#A33C91"),
        "property": CodeSyntaxTokenStyleDesign(foreground: "#9A5B20"),
        "punctuation": CodeSyntaxTokenStyleDesign(foreground: "#A8A29A"),
        "punctuation.delimiter": CodeSyntaxTokenStyleDesign(foreground: "#A8A29A"),
        "punctuation.special": CodeSyntaxTokenStyleDesign(foreground: "#A33C91", fontStyle: "bold"),
        "string": CodeSyntaxTokenStyleDesign(foreground: "#2E7D32"),
        "string.special": CodeSyntaxTokenStyleDesign(foreground: "#2E7D32"),
        "text.literal.markup": CodeSyntaxTokenStyleDesign(foreground: "#2E7D32"),
        "title.markup": CodeSyntaxTokenStyleDesign(foreground: "#1F1A16", fontStyle: "bold"),
        "type": CodeSyntaxTokenStyleDesign(foreground: "#704CB8"),
        "type.builtin": CodeSyntaxTokenStyleDesign(foreground: "#704CB8"),
        "variable": CodeSyntaxTokenStyleDesign(foreground: "#9A5B20"),
        "variable.parameter": CodeSyntaxTokenStyleDesign(foreground: "#8B5F1F"),
        "emphasis.markup": CodeSyntaxTokenStyleDesign(foreground: "#1C1B19", fontStyle: "italic"),
        "emphasis.strong.markup": CodeSyntaxTokenStyleDesign(foreground: "#1F1A16", fontStyle: "bold"),
        "strikethrough.markup": CodeSyntaxTokenStyleDesign(foreground: "#A8A29A"),
        "punctuation.markup": CodeSyntaxTokenStyleDesign(foreground: "#A8A29A"),
        "punctuation.list_marker.markup": CodeSyntaxTokenStyleDesign(foreground: "#3D362F"),
        "punctuation.embedded.markup": CodeSyntaxTokenStyleDesign(foreground: "#A8A29A")
    ]
}
