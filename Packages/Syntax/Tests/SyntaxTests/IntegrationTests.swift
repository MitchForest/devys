// IntegrationTests.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// End-to-end integration tests.

import Testing
import Foundation
@testable import Syntax

@Suite("Integration Tests")
struct IntegrationTests {
    
    // MARK: - Grammar Loading
    
    @Test("Loads Swift grammar from bundle")
    func testLoadSwiftGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        
        #expect(grammar.name.lowercased().contains("swift"))
        #expect(grammar.scopeName == "source.swift")
        #expect(!grammar.patterns.isEmpty)
    }
    
    @Test("Loads Python grammar from bundle")
    func testLoadPythonGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "python")
        
        #expect(grammar.name.lowercased().contains("python"))
        #expect(grammar.scopeName == "source.python")
    }
    
    @Test("Loads JavaScript grammar from bundle")
    func testLoadJavaScriptGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "javascript")
        
        #expect(grammar.scopeName == "source.js")
    }

    @Test("Loads C++ grammar from bundle")
    func testLoadCppGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "cpp")
        #expect(grammar.scopeName.contains("cpp"))
    }

    @Test("Loads JSON grammar from bundle")
    func testLoadJSONGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "json")

        #expect(grammar.scopeName.contains("json"))
    }

    @Test("Loads YAML grammar from bundle")
    func testLoadYAMLGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "yaml")

        #expect(grammar.scopeName.contains("yaml"))
    }
    
    // MARK: - Theme Loading
    
    @Test("Loads GitHub Dark theme from bundle")
    func testLoadGitHubDark() throws {
        let theme = try ShikiTheme.load(name: "github-dark")
        
        #expect(theme.name.lowercased().contains("github"))
        #expect(theme.isDark)
        #expect(theme.editorBackground != nil)
        #expect(theme.tokenColors?.isEmpty == false)
    }
    
    @Test("Loads GitHub Light theme from bundle")
    func testLoadGitHubLight() throws {
        let theme = try ShikiTheme.load(name: "github-light")
        
        #expect(!theme.isDark)
    }
    
    @Test("Theme has token colors")
    func testThemeTokenColors() throws {
        let theme = try ShikiTheme.load(name: "github-dark")
        
        let tokenColors = theme.tokenColors ?? []
        #expect(!tokenColors.isEmpty)
        
        // Should have keyword coloring
        let hasKeyword = tokenColors.contains { rule in
            rule.scope?.scopes.contains { $0.contains("keyword") } == true
        }
        #expect(hasKeyword)
    }
    
    // MARK: - End-to-End Tokenization
    
    @Test("Tokenizes Swift code end-to-end")
    func testSwiftTokenization() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let code = "let x = 42"
        let result = tokenizer.tokenizeLine(line: code, prevState: nil)
        
        #expect(!result.tokens.isEmpty)
        
        // Should have tokens for 'let', 'x', '=', '42'
        let hasKeyword = result.tokens.contains { $0.scopes.contains { $0.contains("keyword") } }
        let hasNumeric = result.tokens.contains { $0.scopes.contains { $0.contains("numeric") } }
        
        #expect(hasKeyword || hasNumeric)
    }
    
    @Test("Tokenizes Python code end-to-end")
    func testPythonTokenization() async throws {
        let grammar = try await TMRegistry().grammar(for: "python")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let code = "def hello():"
        let result = tokenizer.tokenizeLine(line: code, prevState: nil)
        
        #expect(!result.tokens.isEmpty)
    }

    @Test("Tokenizes JSX tags")
    func testJSXTagTokenization() async throws {
        let grammar = try await TMRegistry().grammar(for: "jsx")
        let scopeMap = try await TMRegistry().grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let line1 = "return ("
        let line2 = "  <Button label=\"Click\" />"
        let result1 = tokenizer.tokenizeLine(line: line1, prevState: nil)
        let result2 = tokenizer.tokenizeLine(line: line2, prevState: result1.endState)

        let hasTagScope = result2.tokens.contains { token in
            token.scopes.contains { $0.contains("meta.tag") || $0.contains("entity.name.tag") }
        }
        #expect(hasTagScope)
    }

    @Test("JSX import statement closes on line end")
    func testJSXImportCloses() async throws {
        let grammar = try await TMRegistry().grammar(for: "jsx")
        let tokenizer = TMTokenizer(grammar: grammar)
        let result = tokenizer.tokenizeLine(line: "import React from 'react';", prevState: nil)
        #expect(result.endState.isAtRoot)
    }

    @Test("JSX fixture includes tag scopes")
    func testJSXFixtureHasTags() async throws {
        let grammar = try await TMRegistry().grammar(for: "jsx")
        let scopeMap = try await TMRegistry().grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let fixtureURL = Bundle.module.url(forResource: "sample", withExtension: "jsx")
        #expect(fixtureURL != nil)
        guard let fixtureURL else { return }

        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var state: RuleStack? = nil
        var hasTagScope = false

        for line in lines {
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            state = result.endState
            if result.tokens.contains(where: { token in
                token.scopes.contains { $0.contains("meta.tag") || $0.contains("entity.name.tag") }
            }) {
                hasTagScope = true
                break
            }
        }

        #expect(hasTagScope)
    }

    @Test("Markdown fenced code blocks tokenize and exit cleanly")
    func testMarkdownFencedCodeBlockLifecycle() async throws {
        let markdown = try await TMRegistry().grammar(for: "markdown")
        let scopeMap = try await TMRegistry().grammarsByScope()
        let tokenizer = TMTokenizer(grammar: markdown, scopeNameToGrammar: scopeMap)

        let lines = [
            "```swift",
            "let x = 1",
            "```",
            "# Heading"
        ]

        var state: RuleStack? = nil
        var results: [TokenizeResult] = []
        for line in lines {
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            results.append(result)
            state = result.endState
        }

        // The fenced code line should still produce tokens.
        let swiftLineTokens = results[1].tokens
        #expect(!swiftLineTokens.isEmpty)

        // After closing fence, we should not still be in an embedded Swift scope.
        let headingTokens = results[3].tokens
        let stillEmbedded = headingTokens.contains { token in
            token.scopes.contains { $0.contains("meta.embedded.block.swift") }
        }
        #expect(!stillEmbedded)
    }
    
    // MARK: - Multiline
    
    @Test("Handles multiline strings in Python")
    func testPythonMultilineString() async throws {
        let grammar = try await TMRegistry().grammar(for: "python")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        // Test that tokenizer handles multiple lines without crashing
        let lines = ["x = '''", "multiline", "string", "'''"]
        var state: RuleStack? = nil
        var allResults: [TokenizeResult] = []
        
        for line in lines {
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            allResults.append(result)
            state = result.endState
        }
        
        // Should have tokenized all lines
        #expect(allResults.count == 4)
        // First line should have tokens
        #expect(!allResults[0].tokens.isEmpty)
    }
    
    // MARK: - Language Detection
    
    @Test("Detects Swift from extension")
    func testDetectSwift() {
        let lang = LanguageDetector.detect(from: "main.swift")
        #expect(lang == "swift")
    }
    
    @Test("Detects Python from extension")
    func testDetectPython() {
        let lang = LanguageDetector.detect(from: "script.py")
        #expect(lang == "python")
    }
    
    @Test("Detects special filenames")
    func testDetectDockerfile() {
        let lang = LanguageDetector.detect(from: "Dockerfile")
        #expect(lang == "dockerfile")
    }
    
    @Test("Returns plaintext for unknown")
    func testDetectUnknown() {
        let lang = LanguageDetector.detect(from: "file.xyz")
        #expect(lang == "plaintext")
    }
}
