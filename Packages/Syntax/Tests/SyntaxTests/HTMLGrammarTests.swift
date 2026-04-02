// HTMLGrammarTests.swift
// DevysSyntaxTests

import Foundation
import Testing
@testable import Syntax

@Suite("HTML Grammar Tests")
struct HTMLGrammarTests {
    @Test("HTML tag end is tokenized with punctuation scope")
    func testHTMLTagEndToken() async throws {
        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "html")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let line = "<html lang=\"en\">"
        let result = tokenizer.tokenizeLine(line: line, prevState: nil)

        let endIndex = line.utf16Count - 1
        let endToken = result.tokens.first { token in
            token.startIndex <= endIndex && token.endIndex > endIndex
        }

        #expect(endToken != nil)
        #expect(endToken?.scopes.contains("punctuation.definition.tag.end.html") == true)
        #expect(result.endState.scopePath == "text.html.basic")
    }

    @Test("HTML style embedding exits at closing tag")
    func testHTMLStyleEmbeddingCloses() async throws {
        let registry = TMRegistry()
        let grammar = try await registry.grammar(for: "html")
        let scopeMap = try await registry.grammarsByScope()
        let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

        let fixtureURL = try fixtureURL(named: "sample.html")
        let content = try String(contentsOf: fixtureURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n")

        var state: RuleStack? = nil
        var closingStyleIndex: Int? = nil

        for (index, line) in lines.enumerated() {
            if line.contains("</style>") {
                closingStyleIndex = index
            }

            if ProcessInfo.processInfo.environment["DEVYS_HTML_TRACE"] == "1", index == 6, let traceState = state {
                traceLine(line: line, tokenizer: tokenizer, state: traceState)
            }

            let result = tokenizer.tokenizeLine(line: line, prevState: state)
            state = result.endState

            if ProcessInfo.processInfo.environment["DEVYS_HTML_DEBUG"] == "1" {
                print(
                    "HTML line",
                    index,
                    "anchor:",
                    result.endState.anchorPosition,
                    "endPattern:",
                    result.endState.endPattern ?? "nil",
                    "state:",
                    result.endState.scopePath,
                    "line:",
                    line
                )
                if line.contains("</style>") || line.contains("{") {
                    for token in result.tokens {
                        let start = line.utf16Index(at: token.startIndex)
                        let end = line.utf16Index(at: token.endIndex)
                        let text = String(line[start..<end])
                        print("  token [\(token.startIndex)-\(token.endIndex)] '\(text)' scopes:", token.scopes)
                    }
                }
            }

            if let closingStyleIndex, index == closingStyleIndex {
                #expect(result.endState.scopePath == "text.html.basic")
                break
            }
        }
    }

    private func traceLine(line: String, tokenizer: TMTokenizer, state: RuleStack) {
        var position = 0
        var currentState = state
        let lineLength = line.utf16Count
        var steps = 0
        print("TRACE line:", line)

        while position < lineLength && steps < 50 {
            steps += 1
            print("  pos", position, "state:", currentState.scopePath, "end:", currentState.endPattern ?? "nil")
            if let result = tokenizer.matchAtPosition(line: line, position: position, state: currentState) {
                let tokenSummary = result.tokens.map { "\($0.startIndex)-\($0.endIndex)" }.joined(separator: ",")
                print("    match newPos:", result.newPosition, "tokens:", tokenSummary, "newState:", result.newState.scopePath)

                if result.tokens.isEmpty && result.newPosition == position {
                    currentState = result.newState
                    continue
                }

                if result.newPosition <= position {
                    position = line.nextCharacterBoundary(afterUtf16Offset: position)
                    currentState = result.newState
                    continue
                }

                position = result.newPosition
                currentState = result.newState
            } else {
                position = line.nextCharacterBoundary(afterUtf16Offset: position)
            }
        }
    }

    private func fixtureURL(named name: String) throws -> URL {
        if let url = Bundle.module.url(forResource: name, withExtension: nil) {
            return url
        }

        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard let ext = parts.last else {
            throw NSError(domain: "DevysSyntaxTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fixture not found: \(name)"
            ])
        }

        let base = parts.dropLast().joined(separator: ".")
        if let url = Bundle.module.url(forResource: base, withExtension: String(ext)) {
            return url
        }

        throw NSError(domain: "DevysSyntaxTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Fixture not found: \(name)"
        ])
    }
}
