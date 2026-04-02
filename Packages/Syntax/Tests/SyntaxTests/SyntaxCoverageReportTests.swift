// SyntaxCoverageReportTests.swift
// DevysSyntaxTests
//
// Generates a per-language token/color report for fixture files.

import Foundation
import Testing
@testable import Syntax

@Suite("Syntax Coverage Reports")
struct SyntaxCoverageReportTests {

    private struct ScopeCount: Codable {
        let scope: String
        let count: Int
    }

    private struct ColorCount: Codable {
        let color: String
        let count: Int
    }

    private struct FileReport: Codable {
        let language: String
        let fixture: String
        let theme: String
        let totalTokens: Int
        let identifiedTokens: Int
        let uniqueScopes: Int
        let uniqueColors: Int
        let defaultForeground: String
        let topScopes: [ScopeCount]
        let topColors: [ColorCount]
    }

    private struct Report: Codable {
        let generatedAt: String
        let theme: String
        let files: [FileReport]
    }

    private let fixtures: [(language: String, file: String)] = [
        ("html", "sample.html"),
        ("css", "sample.css"),
        ("json", "sample.json"),
        ("yaml", "sample.yaml"),
        ("javascript", "sample.js"),
        ("typescript", "sample.ts"),
        ("tsx", "sample.tsx"),
        ("jsx", "sample.jsx"),
        ("markdown", "sample.md"),
        ("swift", "sample.swift"),
        ("python", "sample.py")
    ]

    @Test("Generate syntax coverage report (github-light)")
    func testGenerateReport() async throws {
        let themeName = "github-light"
        let theme = try ShikiTheme.load(name: themeName)
        let resolver = ThemeResolver(theme: theme)

        var reports: [FileReport] = []

        for fixture in fixtures {
            let content = try loadFixture(named: fixture.file)
            let lines = content.components(separatedBy: "\n")

            let grammar = try await TMRegistry().grammar(for: fixture.language)
            let scopeMap = try await TMRegistry().grammarsByScope()
            let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

            var state: RuleStack? = nil
            var totalTokens = 0
            var identifiedTokens = 0
            var scopeCounts: [String: Int] = [:]
            var colorCounts: [String: Int] = [:]

            for line in lines {
                let result = tokenizer.tokenizeLine(line: line, prevState: state)
                state = result.endState

                for token in result.tokens {
                    totalTokens += 1
                    for scope in token.scopes {
                        scopeCounts[scope, default: 0] += 1
                    }

                    let style = resolver.resolve(scopes: token.scopes)
                    let color = style.foreground
                    colorCounts[color, default: 0] += 1

                    if style.foreground != resolver.defaultForeground
                        || style.background != nil
                        || !style.fontStyle.isEmpty {
                        identifiedTokens += 1
                    }
                }
            }

            let sortedScopes = scopeCounts
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { ScopeCount(scope: $0.key, count: $0.value) }

            let sortedColors = colorCounts
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { ColorCount(color: $0.key, count: $0.value) }

            let report = FileReport(
                language: fixture.language,
                fixture: fixture.file,
                theme: themeName,
                totalTokens: totalTokens,
                identifiedTokens: identifiedTokens,
                uniqueScopes: scopeCounts.keys.count,
                uniqueColors: colorCounts.keys.count,
                defaultForeground: resolver.defaultForeground,
                topScopes: Array(sortedScopes),
                topColors: Array(sortedColors)
            )

            reports.append(report)

            #expect(totalTokens > 0)
            #expect(scopeCounts.keys.count > 0)
            #expect(colorCounts.keys.count > 0)
        }

        let report = Report(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            theme: themeName,
            files: reports
        )

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-syntax-report-\(UUID().uuidString)")
            .appendingPathExtension("json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: outURL, options: .atomic)

        print("DevysSyntax report written to:", outURL.path)
    }

    private func loadFixture(named name: String) throws -> String {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        let base = parts.first.map(String.init) ?? name
        let ext = parts.dropFirst().joined(separator: ".")

        guard let url = Bundle.module.url(forResource: base, withExtension: ext) else {
            throw NSError(domain: "DevysSyntaxTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Fixture not found: \(name)"
            ])
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}
