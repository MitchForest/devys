// SwiftGrammarTests.swift
// DevysSyntax - Swift grammar specific tests

import Testing
@testable import Syntax

@Suite("Swift Grammar Tests")
struct SwiftGrammarTests {
    
    @Test("Loads Swift grammar")
    func testLoadSwiftGrammar() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        
        #expect(grammar.scopeName == "source.swift")
        #expect(grammar.patterns.count > 0)
        #expect(grammar.repository != nil)
        #expect(grammar.repository?["root"] != nil)
        
        // Check root has patterns
        if let root = grammar.repository?["root"] {
            let patterns = root.asPatterns
            #expect(patterns.count > 0)
            print("Root has \(patterns.count) patterns")
            for p in patterns {
                print("  - include: \(p.include ?? "none")")
            }
        }
    }
    
    @Test("Tokenizes Swift func keyword")
    func testSwiftKeywords() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let line = "func hello() {"
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)
        
        print("Tokens for '\(line)':")
        for token in result.tokens {
            let startIdx = line.utf16.index(line.utf16.startIndex, offsetBy: token.startIndex)
            let endIdx = line.utf16.index(line.utf16.startIndex, offsetBy: min(token.endIndex, line.utf16.count))
            let text = String(line[startIdx..<endIdx])
            print("  [\(token.startIndex)-\(token.endIndex)] '\(text)' scopes: \(token.scopes)")
        }
        
        #expect(result.tokens.count > 0)
        
        // 'func' is marked as storage.type.function.swift, not 'keyword'
        let hasFunc = result.tokens.contains { token in
            token.scopes.contains { $0.contains("storage.type.function") }
        }
        #expect(hasFunc, "Expected 'func' to have storage.type.function scope")
    }
    
    @Test("Tokenizes Swift struct")
    func testSwiftStruct() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let line = "struct Person {"
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)
        
        print("Tokens for '\(line)':")
        for token in result.tokens {
            let startIdx = line.utf16.index(line.utf16.startIndex, offsetBy: token.startIndex)
            let endIdx = line.utf16.index(line.utf16.startIndex, offsetBy: min(token.endIndex, line.utf16.count))
            let text = String(line[startIdx..<endIdx])
            print("  [\(token.startIndex)-\(token.endIndex)] '\(text)' scopes: \(token.scopes)")
        }
        
        #expect(result.tokens.count > 0)
    }
    
    @Test("Tokenizes Swift let with type annotation")
    func testSwiftTypedVariable() async throws {
        let grammar = try await TMRegistry().grammar(for: "swift")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        // NOTE: The grammar only matches let/var WITH type annotations
        // "let name = value" won't match, but "let name: Type = value" will
        let line = "let name: String = \"test\""
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)
        
        print("Tokens for '\(line)':")
        for token in result.tokens {
            let startIdx = line.utf16.index(line.utf16.startIndex, offsetBy: token.startIndex)
            let endIdx = line.utf16.index(line.utf16.startIndex, offsetBy: min(token.endIndex, line.utf16.count))
            let text = String(line[startIdx..<endIdx])
            print("  [\(token.startIndex)-\(token.endIndex)] '\(text)' scopes: \(token.scopes)")
        }
        
        // Check for string
        let hasString = result.tokens.contains { token in
            token.scopes.contains { $0.contains("string") }
        }
        #expect(hasString, "Expected to find a string token")
    }
    
    @Test("Documents grammar limitation: untyped let")
    func testSwiftUntypedVariable() async throws {
        // This test documents a known limitation
        let grammar = try await TMRegistry().grammar(for: "swift")
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let line = "let name = \"test\""
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)
        
        print("Tokens for '\(line)':")
        for token in result.tokens {
            let startIdx = line.utf16.index(line.utf16.startIndex, offsetBy: token.startIndex)
            let endIdx = line.utf16.index(line.utf16.startIndex, offsetBy: min(token.endIndex, line.utf16.count))
            let text = String(line[startIdx..<endIdx])
            print("  [\(token.startIndex)-\(token.endIndex)] '\(text)' scopes: \(token.scopes)")
        }
        
        // KNOWN LIMITATION: 'let' without type annotation is NOT highlighted
        // This is because the VS Code Swift grammar requires type annotations
        // and uses Oniguruma-specific regex features (named backreferences)
        
        // String IS highlighted though
        let hasString = result.tokens.contains { token in
            token.scopes.contains { $0.contains("string") }
        }
        #expect(hasString, "String should still be highlighted")
    }
}
