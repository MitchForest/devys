// EngineTests.swift
// Tests for the RegexEngine and TMTokenizer integration

import Testing
import Foundation
@testable import Syntax
@testable import OnigurumaKit

@Suite("RegexEngine Tests")
struct EngineTests {
    
    @Test("OnigurumaEngine returns correct capture positions")
    func testOnigurumaEngineCaptures() throws {
        let engine = OnigurumaEngine()
        let pattern = #"\b(func)\s+(\w+)\s*(?=\()"#
        
        let scanner = try engine.createScanner(patterns: [pattern])
        let match = scanner.findNextMatch(in: "func hello() {", from: 0)
        
        #expect(match != nil, "Should find match")
        
        if let match = match {
            // These are UTF-16 positions (same as UTF-8 for ASCII)
            #expect(match.captures[0].start == 0 && match.captures[0].end == 10, "Full match")
            #expect(match.captures[1].start == 0 && match.captures[1].end == 4, "Capture 1 = func")
            #expect(match.captures[2].start == 5 && match.captures[2].end == 10, "Capture 2 = hello")
        }
    }

    @Test("OnigurumaEngine finds zero-length lookahead matches")
    func testOnigurumaZeroLengthLookahead() throws {
        let engine = OnigurumaEngine()
        let pattern = #"(?=\s*+[^=\s])"#

        let scanner = try engine.createScanner(patterns: [pattern])
        let match = scanner.findNextMatch(in: ">", from: 0)

        #expect(match != nil, "Should find zero-length match")
        if let match {
            #expect(match.captures[0].start == 0)
            #expect(match.captures[0].end == 0)
        }
    }

    @Test("OnigurumaEngine anchors \\G to start of string")
    func testOnigurumaGAnchor() throws {
        let regex = try OnigRegex(pattern: #"\\Gabc"#)

        let matchAtTwo = regex.search(in: "xxabc", from: 2)
        #expect(matchAtTwo == nil)

        let matchAtThree = regex.search(in: "xxabc", from: 3)
        #expect(matchAtThree == nil)
    }

    @Test("OnigurumaEngine finds selector end lookahead")
    func testOnigurumaSelectorEndLookahead() throws {
        let regex = try OnigRegex(pattern: #"(?=\s*[)/@{])"#)
        let match = regex.search(in: "    body {", from: 0)
        #expect(match != nil)
        #expect(match?.start == 8)
        #expect(match?.end == 8)
    }

    @Test("OnigurumaEngine finds selector begin lookahead")
    func testOnigurumaSelectorBeginLookahead() throws {
        let pattern = #"(?=\|?(?:[-#*.:A-\[_a-z[^\x00-\x7F]]|\\(?:\h{1,6}|.)))"#
        let regex = try OnigRegex(pattern: pattern)
        let match = regex.search(in: "    body {", from: 0)
        #expect(match != nil)
        #expect(match?.start == 4)
        #expect(match?.end == 4)
    }

    @Test("TMTokenizer splits multi-scope JSON property names")
    func testJSONPropertyNameScopeSplit() async throws {
        let grammar = try await TMRegistry().grammar(for: "json")
        let tokenizer = TMTokenizer(grammar: grammar)

        let startState = tokenizer.tokenizeLine(line: "{", prevState: nil).endState
        let result = tokenizer.tokenizeLine(line: "\"name\": 1", prevState: startState)
        if ProcessInfo.processInfo.environment["DEVYS_DEBUG_JSON"] == "1" {
            for token in result.tokens {
                print("JSON token:", token.startIndex, token.endIndex, token.scopes)
            }
        }
        let token = result.tokens.first { token in
            token.scopes.contains("string.json")
                && token.scopes.contains("support.type.property-name.json")
        }

        #expect(token != nil, "Expected token to include both string and property-name scopes")
    }

    @Test("Markdown heading tokens include heading scopes")
    func testMarkdownHeadingScopes() async throws {
        let grammar = try await TMRegistry().grammar(for: "markdown")
        let tokenizer = TMTokenizer(grammar: grammar)

        let result = tokenizer.tokenizeLine(line: "# Scribble", prevState: nil)
        if ProcessInfo.processInfo.environment["DEVYS_DEBUG_MD"] == "1" {
            for token in result.tokens {
                print("MD token:", token.startIndex, token.endIndex, token.scopes)
            }

            if let headingPattern = grammar.repository?["heading"]?.asPatterns.first {
                let state = RuleStack.initial(scopeName: grammar.scopeName)
                let headingResult = tokenizer.tryPattern(
                    headingPattern,
                    in: "# Scribble",
                    at: 0,
                    state: state,
                    grammar: grammar
                )
                print("MD heading pattern result:", headingResult?.tokens ?? [])
            }
        }

        if ProcessInfo.processInfo.environment["DEVYS_DEBUG_MD_FENCE"] == "1" {
            let fixtureURL = Bundle.module.url(
                forResource: "sample",
                withExtension: "md"
            )
            if let fixtureURL {
                let content = try String(contentsOf: fixtureURL, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                var state: RuleStack? = nil
                for (index, line) in lines.enumerated() {
                    let lineResult = tokenizer.tokenizeLine(line: line, prevState: state)
                    state = lineResult.endState
                    if line.trimmingCharacters(in: .whitespacesAndNewlines) == "}" {
                        for token in lineResult.tokens {
                            print("MD fence token:", index, token.startIndex, token.endIndex, token.scopes)
                        }
                    }
                }
            }
        }

        let hasHeading = result.tokens.contains { token in
            token.scopes.contains("markup.heading.markdown")
                || token.scopes.contains("heading.1.markdown")
        }
        #expect(hasHeading, "Expected heading scopes for markdown heading")
    }

    @Test("Debug JS const tokenization")
    func testJavaScriptConstDebug() async throws {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_JS"] == "1" else {
            return
        }

        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "javascript")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let line = "const nums = [1, 2, 3, 4];"
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)

        for token in result.tokens {
            let start = line.utf16Index(at: token.startIndex)
            let end = line.utf16Index(at: token.endIndex)
            let text = String(line[start..<end])
            print("JS token:", token.startIndex, token.endIndex, text, token.scopes)
        }
    }

    @Test("Debug YAML key tokenization")
    func testYAMLKeyDebug() async throws {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_YAML"] == "1" else {
            return
        }

        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "yaml")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let line = "name: devys"
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)

        for token in result.tokens {
            let start = line.utf16Index(at: token.startIndex)
            let end = line.utf16Index(at: token.endIndex)
            let text = String(line[start..<end])
            print("YAML token:", token.startIndex, token.endIndex, text, token.scopes)
        }
    }

    @Test("Debug JS const regex match")
    func testJavaScriptConstRegexDebug() throws {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_JS_REGEX"] == "1" else {
            return
        }

        let pattern = #"(?<![$_[:alnum:]])(?:(?<=\\.\\.\\.)|(?<!\\.))(?:\\b(export)\\s+)?(?:\\b(declare)\\s+)?\\b(const(?!\\s+enum\\b))(?![$_[:alnum:]])(?:(?=\\.\\.\\.)|(?!\\.))\\s*"#
        let regex = try OnigRegex(pattern: pattern)
        let line = "const nums = [1, 2, 3, 4];"
        if let match = regex.search(in: line, from: 0) {
            print("Const match:", match.start, match.end)
            for cap in match.captures {
                print("cap", cap.index, cap.start, cap.end)
            }
        } else {
            print("Const match: nil")
        }
    }

    @Test("Debug C++ tokenization")
    func testCppTokenizationDebug() async throws {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_CPP"] == "1" else {
            return
        }

        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "cpp")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let fixtureURL = Bundle.module.url(forResource: "sample", withExtension: "cpp")
        #expect(fixtureURL != nil)
        guard let fixtureURL else { return }

        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var state: RuleStack? = nil
        for (index, line) in lines.enumerated() {
            print("CPP line", index, ":", line)
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            state = result.endState
            print("  tokens:", result.tokens.count, "state:", result.endState.scopePath)
        }
    }

    @Test("Debug Swift tokenization")
    func testSwiftTokenizationDebug() async throws {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_SWIFT"] == "1" else {
            return
        }

        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "swift")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let fixtureURL = Bundle.module.url(forResource: "sample", withExtension: "swift")
        #expect(fixtureURL != nil)
        guard let fixtureURL else { return }

        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var state: RuleStack? = nil
        for (index, line) in lines.enumerated() {
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            state = result.endState
            if [2, 7, 8, 11, 12].contains(index) {
                print("SWIFT line", index, ":", line)
                for token in result.tokens {
                    let start = line.utf16Index(at: token.startIndex)
                    let end = line.utf16Index(at: token.endIndex)
                    let text = String(line[start..<end])
                    print("  token:", token.startIndex, token.endIndex, text, token.scopes)
                }
            }
        }
    }

    @Test("Debug Shell tokenization")
    func testShellTokenizationDebug() async throws {
        guard ProcessInfo.processInfo.environment["DEVYS_DEBUG_SH"] == "1" else {
            return
        }

        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "shellscript")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let fixtureURL = Bundle.module.url(forResource: "sample", withExtension: "sh")
        #expect(fixtureURL != nil)
        guard let fixtureURL else { return }

        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var state: RuleStack? = nil
        for (index, line) in lines.enumerated() {
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            state = result.endState
            if [10, 16, 17, 19, 20].contains(index) {
                print("SH line", index, ":", line)
                for token in result.tokens {
                    let start = line.utf16Index(at: token.startIndex)
                    let end = line.utf16Index(at: token.endIndex)
                    let text = String(line[start..<end])
                    print("  token:", token.startIndex, token.endIndex, text, token.scopes)
                }
            }
        }
    }
    
    @Test("Grammar pattern from JSON has correct captures")
    func testGrammarPatternFromJSON() async throws {
        // Load the actual grammar and check the pattern
        let grammar = try await TMRegistry().grammar(for: "swift")
        
        // Find the declarations-function pattern
        guard let repo = grammar.repository,
              let repoPattern = repo["declarations-function"] else {
            #expect(Bool(false), "Should find declarations-function pattern")
            return
        }
        
        // Extract the TMPattern from the repository pattern
        let patterns: [TMPattern]
        switch repoPattern {
        case .pattern(let p):
            patterns = [p]
        case .patterns(let ps):
            patterns = ps
        }
        
        guard let funcPattern = patterns.first,
              let beginPattern = funcPattern.begin else {
            #expect(Bool(false), "Should have begin pattern")
            return
        }
        
        // Test with the actual grammar pattern
        let regex = try OnigRegex(pattern: beginPattern)
        
        if let match = regex.search(in: "func hello() {") {
            // Capture 1 should be "func" at positions 0-4
            let capture1 = match.captures.first { $0.index == 1 }
            #expect(capture1 != nil, "Capture 1 should exist")
            if let cap1 = capture1 {
                #expect(cap1.start == 0, "Capture 1 (func) should start at 0")
                #expect(cap1.end == 4, "Capture 1 (func) should end at 4")
            }
        } else {
            #expect(Bool(false), "Pattern should match 'func hello() {'")
        }
    }
    
    @Test("TMTokenizer correctly processes begin captures")
    func testTokenizerBeginCaptures() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "func hello() {", prevState: nil)
        
        // Find the token for "func"
        let funcToken = result.tokens.first { $0.scopes.contains("storage.type.function.swift") }
        #expect(funcToken != nil, "Should have a token with storage.type.function.swift scope")
        
        if let funcToken = funcToken {
            #expect(funcToken.startIndex == 0, "func token should start at 0")
            #expect(funcToken.endIndex == 4, "func token should end at 4")
        }
    }

    @Test("JSX tag lookbehind pattern compiles")
    func testJSXTagLookbehindCompiles() async throws {
        let grammar = try await TMRegistry().grammar(for: "jsx")
        guard let repo = grammar.repository,
              let repoPattern = repo["jsx-tag-in-expression"] else {
            #expect(Bool(false), "Should find jsx-tag-in-expression pattern")
            return
        }

        let patterns: [TMPattern]
        switch repoPattern {
        case .pattern(let p):
            patterns = [p]
        case .patterns(let ps):
            patterns = ps
        }

        guard let beginPattern = patterns.first?.begin else {
            #expect(Bool(false), "JSX tag pattern should have begin regex")
            return
        }

        _ = try OnigRegex(pattern: beginPattern)
    }

    @Test("Oniguruma finds JSX import end at line end")
    func testJSXImportEndMatchAtLineEnd() async throws {
        let grammar = try await TMRegistry().grammar(for: "jsx")
        guard let repo = grammar.repository,
              let repoPattern = repo["import-declaration"] else {
            #expect(Bool(false), "Should find import-declaration pattern")
            return
        }

        let patterns: [TMPattern]
        switch repoPattern {
        case .pattern(let p):
            patterns = [p]
        case .patterns(let ps):
            patterns = ps
        }

        guard let endPattern = patterns.first?.end else {
            #expect(Bool(false), "Import declaration should have end regex")
            return
        }

        let regex = try OnigRegex(pattern: endPattern)
        let line = "import React from 'react';"
        let utf8End = line.utf8.count

        let match = regex.search(in: line, from: max(0, utf8End - 1))

        #expect(match != nil)
        if let match {
            #expect(match.start == utf8End || match.start == utf8End - 1)
        }
    }
}
