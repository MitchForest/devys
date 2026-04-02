// TMTokenizerTests.swift
// DevysSyntax - Shiki-compatible syntax highlighting
//
// Tests for the TextMate tokenizer.

import Testing
import Foundation
@testable import Syntax

@Suite("TMTokenizer Tests")
struct TMTokenizerTests {
    
    // MARK: - Helper
    
    /// Create a simple test grammar
    func makeSimpleGrammar() -> TMGrammar {
        TMGrammar(
            name: "Test",
            scopeName: "source.test",
            patterns: [
                TMPattern(
                    match: "\\bfunction\\b",
                    name: "keyword.function",
                    captures: nil,
                    begin: nil, end: nil, beginCaptures: nil, endCaptures: nil, contentName: nil,
                    while: nil, whileCaptures: nil, patterns: nil, applyEndPatternLast: nil, repository: nil, include: nil, disabled: nil
                ),
                TMPattern(
                    match: "\\bvar\\b",
                    name: "keyword.var",
                    captures: nil,
                    begin: nil, end: nil, beginCaptures: nil, endCaptures: nil, contentName: nil,
                    while: nil, whileCaptures: nil, patterns: nil, applyEndPatternLast: nil, repository: nil, include: nil, disabled: nil
                ),
                TMPattern(
                    match: "\\d+",
                    name: "constant.numeric",
                    captures: nil,
                    begin: nil, end: nil, beginCaptures: nil, endCaptures: nil, contentName: nil,
                    while: nil, whileCaptures: nil, patterns: nil, applyEndPatternLast: nil, repository: nil, include: nil, disabled: nil
                ),
                TMPattern(
                    match: "\"[^\"]*\"",
                    name: "string.quoted",
                    captures: nil,
                    begin: nil, end: nil, beginCaptures: nil, endCaptures: nil, contentName: nil,
                    while: nil, whileCaptures: nil, patterns: nil, applyEndPatternLast: nil, repository: nil, include: nil, disabled: nil
                ),
            ],
            repository: nil,
            injections: nil,
            fileTypes: nil,
            firstLineMatch: nil,
            foldingStartMarker: nil,
            foldingStopMarker: nil
        )
    }
    
    /// Create a grammar with begin/end patterns
    func makeBeginEndGrammar() -> TMGrammar {
        TMGrammar(
            name: "BeginEnd Test",
            scopeName: "source.test",
            patterns: [
                TMPattern(
                    match: nil,
                    name: "comment.block",
                    captures: nil,
                    begin: "/\\*",
                    end: "\\*/",
                    beginCaptures: nil, endCaptures: nil,
                    contentName: "comment.content",
                    while: nil, whileCaptures: nil,
                    patterns: nil,
                    applyEndPatternLast: nil,
                    repository: nil,
                    include: nil, disabled: nil
                ),
                TMPattern(
                    match: nil,
                    name: "string.double",
                    captures: nil,
                    begin: "\"",
                    end: "\"",
                    beginCaptures: nil, endCaptures: nil,
                    contentName: nil,
                    while: nil, whileCaptures: nil,
                    patterns: nil,
                    applyEndPatternLast: nil,
                    repository: nil,
                    include: nil, disabled: nil
                ),
            ],
            repository: nil,
            injections: nil,
            fileTypes: nil,
            firstLineMatch: nil,
            foldingStartMarker: nil,
            foldingStopMarker: nil
        )
    }
    
    // MARK: - Basic Tests
    
    @Test("Tokenizes simple keywords")
    func testSimpleKeyword() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "function", prevState: nil)
        
        #expect(result.tokens.count >= 1)
        let keywordToken = result.tokens.first { $0.scopes.contains("keyword.function") }
        #expect(keywordToken != nil)
    }
    
    @Test("Tokenizes multiple keywords on one line")
    func testMultipleKeywords() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "function var", prevState: nil)
        
        let functionToken = result.tokens.first { $0.scopes.contains("keyword.function") }
        let varToken = result.tokens.first { $0.scopes.contains("keyword.var") }
        
        #expect(functionToken != nil)
        #expect(varToken != nil)
    }
    
    @Test("Tokenizes numbers")
    func testNumbers() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "var x = 42", prevState: nil)
        
        let numericToken = result.tokens.first { $0.scopes.contains("constant.numeric") }
        #expect(numericToken != nil)
    }
    
    @Test("Tokenizes strings")
    func testStrings() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "var name = \"hello\"", prevState: nil)
        
        let stringToken = result.tokens.first { $0.scopes.contains("string.quoted") }
        #expect(stringToken != nil)
    }
    
    @Test("Creates gap tokens")
    func testGapTokens() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "function test", prevState: nil)
        
        // Should have tokens covering the entire line
        let totalLength = result.tokens.map { $0.endIndex - $0.startIndex }.reduce(0, +)
        #expect(totalLength == "function test".utf16.count)
    }
    
    // MARK: - Begin/End Tests
    
    @Test("Tokenizes block comments")
    func testBlockComment() {
        let grammar = makeBeginEndGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "/* comment */", prevState: nil)
        
        let commentToken = result.tokens.first { $0.scopes.contains("comment.block") }
        #expect(commentToken != nil)
    }
    
    @Test("Handles multiline begin/end")
    func testMultilineComment() {
        let grammar = makeBeginEndGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        // First line - start of comment
        let result1 = tokenizer.tokenizeLine(line: "/* start", prevState: nil)
        
        // Should still be in the comment state
        #expect(result1.endState.endPattern != nil)
        
        // Second line - end of comment
        let result2 = tokenizer.tokenizeLine(line: "end */", prevState: result1.endState)
        
        // Should have exited the comment
        #expect(result2.endState.isAtRoot)
    }
    
    // MARK: - Edge Cases
    
    @Test("Handles empty lines")
    func testEmptyLine() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "", prevState: nil)
        
        #expect(result.tokens.isEmpty)
        #expect(result.endState.isAtRoot)
    }
    
    @Test("Handles whitespace-only lines")
    func testWhitespaceLine() {
        let grammar = makeSimpleGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let result = tokenizer.tokenizeLine(line: "   ", prevState: nil)
        
        // Should have a gap token for whitespace
        #expect(!result.tokens.isEmpty)
    }
    
    @Test("State persists across lines")
    func testStatePersistence() {
        let grammar = makeBeginEndGrammar()
        let tokenizer = TMTokenizer(grammar: grammar)
        
        let lines = ["/* line 1", "line 2", "line 3 */", "normal code"]
        var state: RuleStack? = nil
        
        for (index, line) in lines.enumerated() {
            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            state = result.endState
            
            if index < 3 {
                // Still in comment or just exited
                let hasCommentScope = result.tokens.contains { $0.scopes.contains { $0.contains("comment") } }
                #expect(hasCommentScope || index == 2)
            }
        }
        
        // After the comment ends, should be at root
        #expect(state?.isAtRoot == true)
    }
}
