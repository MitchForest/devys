// CSSGrammarTests.swift
// DevysSyntaxTests

import Testing
@testable import Syntax

@Suite("CSS Grammar Tests")
struct CSSGrammarTests {
    @Test("CSS rule lists close on same line")
    func testCSSRuleListClosure() async throws {
        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "css")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let line = "body { font-family: \"Inter\", sans-serif; background: #f5f5f7; }"
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)

        #expect(result.endState.scopePath == "source.css")
    }

    @Test("CSS rule lists close with nonzero anchor")
    func testCSSRuleListClosureWithAnchor() async throws {
        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "css")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let line = "    body { font-family: \"Inter\", sans-serif; background: #f5f5f7; }"
        let state = RuleStack.fromScopes(
            [grammar.scopeName],
            grammarScopeName: grammar.scopeName,
            anchorPosition: 8
        )

        let result = tokenizer.tokenizeLine(line: line, prevState: state)
        #expect(result.endState.scopePath == "source.css")
    }
}
