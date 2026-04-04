import Testing
@testable import Syntax

@Suite("SyntaxTheme Tests")
struct SyntaxThemeTests {
    @Test("Loads bundled Tree-sitter theme from bundle")
    func loadsBundledTheme() throws {
        let theme = try SyntaxTheme.load(name: "devys-dark")

        #expect(theme.name == "devys-dark")
        #expect(theme.appearance == .dark)
        #expect(theme.styles["keyword"]?.foreground == "#F08B5A")
        #expect(theme.editorBackground == "#000000")
    }

    @Test("Most specific capture wins over parent capture")
    func mostSpecificCaptureWins() {
        let theme = SyntaxTheme(
            name: "Test",
            appearance: .dark,
            defaultForeground: "#ffffff",
            defaultBackground: "#000000",
            styles: [
                "keyword": SyntaxThemeTokenStyle(foreground: "#111111"),
                "keyword.control": SyntaxThemeTokenStyle(foreground: "#222222", fontStyle: "bold")
            ]
        )

        let style = theme.resolve(captureNames: ["@keyword.control"])

        #expect(style.foreground == "#222222")
        #expect(style.fontStyle.contains(.bold))
    }

    @Test("Parent capture fallback resolves when a child capture is missing")
    func parentCaptureFallbackResolves() {
        let theme = SyntaxTheme(
            name: "Test",
            appearance: .dark,
            defaultForeground: "#ffffff",
            defaultBackground: "#000000",
            styles: [
                "string": SyntaxThemeTokenStyle(foreground: "#00ff00")
            ]
        )

        let style = theme.resolve(captureNames: ["@string.special.regex"])

        #expect(style.foreground == "#00ff00")
        #expect(style.fontStyle.isEmpty)
    }

    @Test("Default foreground is used when no capture matches")
    func defaultForegroundIsUsedWhenNoCaptureMatches() {
        let theme = SyntaxTheme(
            name: "Test",
            appearance: .light,
            defaultForeground: "#123456",
            defaultBackground: "#ffffff",
            styles: [:]
        )

        let style = theme.resolve(captureNames: ["@unknown.capture"])

        #expect(style.foreground == "#123456")
        #expect(style.background == nil)
    }

    @Test("Bundled theme styles markdown captures distinctly")
    func bundledThemeStylesMarkdownCaptures() throws {
        let theme = try SyntaxTheme.load(name: "devys-dark")

        let heading = theme.resolve(captureNames: ["@text.title"])
        let marker = theme.resolve(captureNames: ["@punctuation.special"])
        let link = theme.resolve(captureNames: ["@text.uri"])
        let emphasis = theme.resolve(captureNames: ["@text.emphasis"])
        let code = theme.resolve(captureNames: ["@text.literal"])

        #expect(heading.foreground != theme.defaultForeground)
        #expect(heading.fontStyle.contains(.bold))
        #expect(marker.foreground != theme.defaultForeground)
        #expect(marker.fontStyle.contains(.bold))
        #expect(link.foreground != theme.defaultForeground)
        #expect(link.fontStyle.contains(.underline))
        #expect(emphasis.fontStyle.contains(.italic))
        #expect(code.foreground == "#D7B06C")
    }
}
