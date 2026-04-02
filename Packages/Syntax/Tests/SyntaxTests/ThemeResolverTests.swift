// ThemeResolverTests.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Tests for theme resolution.

import Testing
import Foundation
@testable import Syntax

@Suite("ThemeResolver Tests")
struct ThemeResolverTests {
    
    // MARK: - Helper
    
    func makeTestTheme() -> ShikiTheme {
        ShikiTheme(
            name: "Test Theme",
            type: .dark,
            colors: [
                "editor.background": "#1e1e1e",
                "editor.foreground": "#d4d4d4"
            ],
            tokenColors: [
                TokenColorRule(
                    name: "Keywords",
                    scope: .single("keyword"),
                    settings: TokenSettings(foreground: "#569cd6", background: nil, fontStyle: nil)
                ),
                TokenColorRule(
                    name: "Keywords Excluding Control",
                    scope: .single("keyword - keyword.control"),
                    settings: TokenSettings(foreground: "#111111", background: nil, fontStyle: nil)
                ),
                TokenColorRule(
                    name: "Control Keywords",
                    scope: .single("keyword.control"),
                    settings: TokenSettings(foreground: "#c586c0", background: nil, fontStyle: nil)
                ),
                TokenColorRule(
                    name: "Strings",
                    scope: .single("string"),
                    settings: TokenSettings(foreground: "#ce9178", background: nil, fontStyle: nil)
                ),
                TokenColorRule(
                    name: "Comments",
                    scope: .multiple(["comment", "comment.block"]),
                    settings: TokenSettings(foreground: "#6a9955", background: nil, fontStyle: "italic")
                ),
                TokenColorRule(
                    name: "Contextual Keyword",
                    scope: .single("source.swift keyword"),
                    settings: TokenSettings(foreground: "#123456", background: nil, fontStyle: nil)
                ),
                TokenColorRule(
                    name: "Functions",
                    scope: .single("entity.name.function"),
                    settings: TokenSettings(foreground: "#dcdcaa", background: nil, fontStyle: nil)
                ),
                TokenColorRule(
                    name: "Functions Override",
                    scope: .single("entity.name.function"),
                    settings: TokenSettings(foreground: "#0f0f0f", background: nil, fontStyle: nil)
                ),
            ],
            semanticTokenColors: nil,
            semanticHighlighting: nil
        )
    }
    
    // MARK: - Tests
    
    @Test("Resolves single scope")
    func testSingleScope() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)
        
        let style = resolver.resolve(scopes: ["source.swift", "keyword"])
        
        #expect(style.foreground == "#123456")
    }

    @Test("Resolves single scope without context")
    func testSingleScopeWithoutContext() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)

        let style = resolver.resolve(scopes: ["keyword"])

        #expect(style.foreground == "#569cd6")
    }
    
    @Test("Resolves nested scope (more specific wins)")
    func testNestedScope() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)
        
        let style = resolver.resolve(scopes: ["source.swift", "keyword.control"])
        
        // keyword.control is more specific than keyword
        #expect(style.foreground == "#c586c0")
    }

    @Test("Excludes scopes with '-' selector")
    func testExcludeSelector() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)

        let style = resolver.resolve(scopes: ["source.swift", "keyword.control"])

        // keyword - keyword.control should not apply, control rule should win
        #expect(style.foreground == "#c586c0")
    }

    @Test("Matches contextual selectors in order")
    func testContextualSelector() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)

        let style = resolver.resolve(scopes: ["source.swift", "keyword"])
        #expect(style.foreground == "#123456")
    }
    
    @Test("Resolves multiple scope selectors")
    func testMultipleScopes() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)
        
        let style = resolver.resolve(scopes: ["source.swift", "comment.block"])
        
        #expect(style.foreground == "#6a9955")
        #expect(style.fontStyle.contains(.italic))
    }
    
    @Test("Falls back to default foreground")
    func testDefaultFallback() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)
        
        let style = resolver.resolve(scopes: ["source.swift", "unknown.scope"])
        
        // Should use theme's default foreground
        #expect(style.foreground == "#d4d4d4")
    }
    
    @Test("Parses font styles")
    func testFontStyle() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)
        
        let style = resolver.resolve(scopes: ["source.swift", "comment"])
        
        #expect(style.fontStyle.contains(.italic))
        #expect(!style.fontStyle.contains(.bold))
    }
    
    @Test("Caches resolved styles")
    func testCaching() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)
        
        let scopes = ["source.swift", "keyword.control.return"]
        
        // First call
        let style1 = resolver.resolve(scopes: scopes)
        // Second call (should be cached)
        let style2 = resolver.resolve(scopes: scopes)
        
        #expect(style1.foreground == style2.foreground)
        #expect(style1.fontStyle == style2.fontStyle)
    }

    @Test("Later rules override with equal specificity")
    func testLaterRuleOverride() {
        let theme = makeTestTheme()
        let resolver = ThemeResolver(theme: theme)

        let style = resolver.resolve(scopes: ["source.swift", "entity.name.function"])
        #expect(style.foreground == "#0f0f0f")
    }

    @Test("GitHub Dark resolves JSON property names to support color")
    func testGitHubDarkJSONPropertyNameColor() throws {
        let theme = try ShikiTheme.load(name: "github-dark")
        let resolver = ThemeResolver(theme: theme)
        let style = resolver.resolve(scopes: [
            "source.json",
            "meta.structure.dictionary.json",
            "string.json",
            "support.type.property-name.json"
        ])
        #expect(style.foreground.uppercased() == "#79B8FF")
    }
}

@Suite("FontStyle Tests")
struct FontStyleTests {
    
    @Test("Parses bold")
    func testBold() {
        let style = FontStyle.parse("bold")
        #expect(style.contains(.bold))
        #expect(!style.contains(.italic))
    }
    
    @Test("Parses italic")
    func testItalic() {
        let style = FontStyle.parse("italic")
        #expect(style.contains(.italic))
        #expect(!style.contains(.bold))
    }
    
    @Test("Parses bold italic")
    func testBoldItalic() {
        let style = FontStyle.parse("bold italic")
        #expect(style.contains(.bold))
        #expect(style.contains(.italic))
    }
    
    @Test("Parses underline")
    func testUnderline() {
        let style = FontStyle.parse("underline")
        #expect(style.contains(.underline))
    }
    
    @Test("Handles nil")
    func testNil() {
        let style = FontStyle.parse(nil)
        #expect(style == [])
    }
}
