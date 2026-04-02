// ShikiParityReportTests.swift
// DevysSyntaxTests
//
// Compares DevysSyntax token scopes and colors against Shiki output for fixtures.

import Foundation
import Testing
@testable import Syntax

@Suite("Shiki Parity Reports")
struct ShikiParityReportTests {

    private struct FixtureSpec {
        let language: String
        let file: String
    }

    private struct ShikiFixture: Codable {
        let language: String
        let theme: String
        let lines: [ShikiLine]
    }

    private struct ShikiLine: Codable {
        let text: String
        let segments: [ShikiSegment]
    }

    private struct ShikiSegment: Codable {
        let start: Int
        let end: Int
        let text: String
        let scopes: [String]
        let color: String?
        let fontStyle: Int
    }

    private struct SegmentData {
        let start: Int
        let end: Int
        let scopes: [String]
        let color: String?
        let fontStyle: Int
    }

    private struct PositionMap {
        let scopes: [String]
        let colors: [String]
        let fontStyles: [Int]
    }

    private struct Mismatch: Codable {
        let kind: String
        let line: Int
        let start: Int
        let end: Int
        let text: String
        let devys: String
        let shiki: String
    }

    private struct FileReport: Codable {
        let language: String
        let fixture: String
        let theme: String
        let totalPositions: Int
        let scopeMismatchPositions: Int
        let colorMismatchPositions: Int
        let scopeMismatchRanges: Int
        let colorMismatchRanges: Int
        let scopeMismatches: [Mismatch]
        let colorMismatches: [Mismatch]
    }

    private struct Report: Codable {
        let generatedAt: String
        let theme: String
        let files: [FileReport]
    }

    private let fixtures: [FixtureSpec] = [
        .init(language: "swift", file: "sample.swift"),
        .init(language: "javascript", file: "sample.js"),
        .init(language: "jsx", file: "sample.jsx"),
        .init(language: "json", file: "sample.json"),
        .init(language: "markdown", file: "sample.md"),
        .init(language: "yaml", file: "sample.yaml"),
        .init(language: "typescript", file: "sample.ts"),
        .init(language: "html", file: "sample.html"),
        .init(language: "css", file: "sample.css"),
        .init(language: "python", file: "sample.py"),
        .init(language: "shellscript", file: "sample.sh"),
        .init(language: "rust", file: "sample.rs"),
        .init(language: "ruby", file: "sample.rb"),
        .init(language: "go", file: "sample.go"),
        .init(language: "php", file: "sample.php"),
        .init(language: "java", file: "sample.java"),
        .init(language: "csharp", file: "sample.cs"),
        .init(language: "cpp", file: "sample.cpp"),
        .init(language: "c", file: "sample.c"),
        .init(language: "lua", file: "sample.lua"),
        .init(language: "kotlin", file: "sample.kt"),
        .init(language: "make", file: "sample.mk")
    ]

    @Test("Compare scopes and colors vs Shiki (github themes)")
    func testShikiParityReport() async throws {
        let themeNames = ["github-dark", "github-light"]

        let registry = TMRegistry()
        let scopeMap = try await registry.grammarsByScope()

        let filterLanguages = ProcessInfo.processInfo.environment["DEVYS_SHIKI_LANG"]
            .map { value in
                value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        let debugLanguage = ProcessInfo.processInfo.environment["DEVYS_SHIKI_DEBUG_LANG"]
        let debugLineSet: Set<Int> = {
            guard let raw = ProcessInfo.processInfo.environment["DEVYS_SHIKI_DEBUG_LINES"] else {
                return []
            }
            let values = raw
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return Set(values)
        }()

        let selectedFixtures: [FixtureSpec]
        if let filterLanguages {
            let filterSet = Set(filterLanguages.map { Swift.String($0) })
            selectedFixtures = fixtures.filter { filterSet.contains($0.language) }
        } else {
            selectedFixtures = fixtures
        }

        for themeName in themeNames {
            let theme = try ShikiTheme.load(name: themeName)
            let resolver = ThemeResolver(theme: theme)
            var reports: [FileReport] = []

            for fixture in selectedFixtures {
                print("Shiki parity fixture:", themeName, fixture.language)
                let content = try loadFixture(named: fixture.file)
                let shikiFixture = try loadShikiFixture(
                    named: "shiki.\(themeName).\(fixture.file).json"
                )

                let grammar = try await registry.grammar(for: fixture.language)
                let tokenizer = TMTokenizer(grammar: grammar, scopeNameToGrammar: scopeMap)

                let lines = content.components(separatedBy: "\n")
                var state: RuleStack? = nil

                var totalPositions = 0
                var scopeMismatchPositions = 0
                var colorMismatchPositions = 0
                var scopeMismatches: [Mismatch] = []
                var colorMismatches: [Mismatch] = []

                for (lineIndex, line) in lines.enumerated() {
                    let shikiLine = shikiFixture.lines.indices.contains(lineIndex)
                        ? shikiFixture.lines[lineIndex]
                        : ShikiLine(text: line, segments: [])

                    let result = tokenizer.tokenizeLine(line: line, prevState: state)
                    state = result.endState

                    let devysSegments = devysSegments(
                        for: line,
                        tokens: result.tokens,
                        resolver: resolver
                    )
                    let shikiSegments = shikiLine.segments.map {
                        SegmentData(
                            start: $0.start,
                            end: $0.end,
                            scopes: $0.scopes,
                            color: normalizeColor($0.color),
                            fontStyle: $0.fontStyle
                        )
                    }

                    if !debugLineSet.isEmpty,
                       debugLineSet.contains(lineIndex),
                       debugLanguage.map({ $0 == fixture.language }) ?? true {
                        print("DEBUG line", lineIndex, fixture.language, ":", line)
                        print("DEVYS segments:", devysSegments)
                        print("SHIKI segments:", shikiSegments)
                    }

                    let devysMap = buildPositionMap(line: line, segments: devysSegments)
                    let shikiMap = buildPositionMap(line: line, segments: shikiSegments)

                    totalPositions += line.utf16Count

                    let scopeLineMismatches = collectMismatches(
                        line: line,
                        lineIndex: lineIndex,
                        devysValues: devysMap.scopes,
                        shikiValues: shikiMap.scopes,
                        kind: "scope"
                    )
                    let colorLineMismatches = collectMismatches(
                        line: line,
                        lineIndex: lineIndex,
                        devysValues: zip(devysMap.colors, devysMap.fontStyles)
                            .map { "\($0)|\($1)" },
                        shikiValues: zip(shikiMap.colors, shikiMap.fontStyles)
                            .map { "\($0)|\($1)" },
                        kind: "color"
                    )

                    scopeMismatches.append(contentsOf: scopeLineMismatches)
                    colorMismatches.append(contentsOf: colorLineMismatches)

                    scopeMismatchPositions += countMismatchedPositions(
                        devysValues: devysMap.scopes,
                        shikiValues: shikiMap.scopes
                    )
                    colorMismatchPositions += countMismatchedPositions(
                        devysValues: zip(devysMap.colors, devysMap.fontStyles)
                            .map { "\($0)|\($1)" },
                        shikiValues: zip(shikiMap.colors, shikiMap.fontStyles)
                            .map { "\($0)|\($1)" }
                    )
                }

                let report = FileReport(
                    language: fixture.language,
                    fixture: fixture.file,
                    theme: themeName,
                    totalPositions: totalPositions,
                    scopeMismatchPositions: scopeMismatchPositions,
                    colorMismatchPositions: colorMismatchPositions,
                    scopeMismatchRanges: scopeMismatches.count,
                    colorMismatchRanges: colorMismatches.count,
                    scopeMismatches: scopeMismatches,
                    colorMismatches: colorMismatches
                )

                reports.append(report)

                #expect(totalPositions > 0)
            }

            let report = Report(
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                theme: themeName,
                files: reports
            )

            let outURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("devys-shiki-parity-\(UUID().uuidString)")
                .appendingPathExtension("json")

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try data.write(to: outURL, options: .atomic)

            print("DevysSyntax Shiki parity report written to:", outURL.path)

            if ProcessInfo.processInfo.environment["DEVYS_SHIKI_STRICT"] == "1" {
                let totalScopeMismatch = reports.reduce(0) { $0 + $1.scopeMismatchPositions }
                let totalColorMismatch = reports.reduce(0) { $0 + $1.colorMismatchPositions }
                #expect(totalScopeMismatch == 0)
                #expect(totalColorMismatch == 0)
            }
        }
    }

    private func devysSegments(
        for line: String,
        tokens: [TMToken],
        resolver: ThemeResolver
    ) -> [SegmentData] {
        var segments: [SegmentData] = []
        segments.reserveCapacity(tokens.count)

        for token in tokens {
            guard token.startIndex < token.endIndex else { continue }
            let start = max(0, token.startIndex)
            let end = min(line.utf16Count, token.endIndex)
            guard start < end else { continue }

            let style = resolver.resolve(scopes: token.scopes)
            let fontStyle = fontStyleBitset(style.fontStyle)

            segments.append(
                SegmentData(
                    start: start,
                    end: end,
                    scopes: token.scopes,
                    color: normalizeColor(style.foreground),
                    fontStyle: fontStyle
                )
            )
        }

        return segments
    }

    private func buildPositionMap(line: String, segments: [SegmentData]) -> PositionMap {
        let length = line.utf16Count
        if length == 0 {
            return PositionMap(scopes: [], colors: [], fontStyles: [])
        }

        var scopes = Array(repeating: "", count: length)
        var colors = Array(repeating: "", count: length)
        var styles = Array(repeating: 0, count: length)

        for segment in segments {
            let start = max(0, min(length, segment.start))
            let end = max(0, min(length, segment.end))
            guard start < end else { continue }

            let scopeKey = segment.scopes.joined(separator: " ")
            let color = normalizeColor(segment.color) ?? ""
            let fontStyle = segment.fontStyle

            for index in start..<end {
                scopes[index] = scopeKey
                colors[index] = color
                styles[index] = fontStyle
            }
        }

        return PositionMap(scopes: scopes, colors: colors, fontStyles: styles)
    }

    private func collectMismatches(
        line: String,
        lineIndex: Int,
        devysValues: [String],
        shikiValues: [String],
        kind: String
    ) -> [Mismatch] {
        let limit = min(devysValues.count, shikiValues.count)
        guard limit > 0 else { return [] }

        var mismatches: [Mismatch] = []
        var current: Mismatch? = nil

        for index in 0..<limit {
            let devysValue = devysValues[index]
            let shikiValue = shikiValues[index]
            let isMismatch = devysValue != shikiValue

            if !isMismatch {
                if let currentMismatch = current {
                    mismatches.append(currentMismatch)
                    current = nil
                }
                continue
            }

            if let currentMismatch = current,
               currentMismatch.devys == devysValue,
               currentMismatch.shiki == shikiValue,
               currentMismatch.end == index {
                current = Mismatch(
                    kind: currentMismatch.kind,
                    line: currentMismatch.line,
                    start: currentMismatch.start,
                    end: index + 1,
                    text: substring(line, start: currentMismatch.start, end: index + 1),
                    devys: currentMismatch.devys,
                    shiki: currentMismatch.shiki
                )
            } else {
                if let currentMismatch = current {
                    mismatches.append(currentMismatch)
                }
                current = Mismatch(
                    kind: kind,
                    line: lineIndex,
                    start: index,
                    end: index + 1,
                    text: substring(line, start: index, end: index + 1),
                    devys: devysValue,
                    shiki: shikiValue
                )
            }
        }

        if let currentMismatch = current {
            mismatches.append(currentMismatch)
        }

        return mismatches
    }

    private func countMismatchedPositions(devysValues: [String], shikiValues: [String]) -> Int {
        let limit = min(devysValues.count, shikiValues.count)
        guard limit > 0 else { return 0 }
        var count = 0
        for index in 0..<limit where devysValues[index] != shikiValues[index] {
            count += 1
        }
        return count
    }

    private func fontStyleBitset(_ fontStyle: FontStyle) -> Int {
        var value = 0
        if fontStyle.contains(.italic) { value |= 1 }
        if fontStyle.contains(.bold) { value |= 2 }
        if fontStyle.contains(.underline) { value |= 4 }
        return value
    }

    private func substring(_ line: String, start: Int, end: Int) -> String {
        let safeStart = max(0, min(line.utf16Count, start))
        let safeEnd = max(0, min(line.utf16Count, end))
        guard safeStart < safeEnd else { return "" }
        let startIndex = line.utf16Index(at: safeStart)
        let endIndex = line.utf16Index(at: safeEnd)
        return String(line[startIndex..<endIndex])
    }

    private func normalizeColor(_ color: String?) -> String? {
        guard let color else { return nil }
        let trimmed = color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#") {
            return "#" + trimmed.dropFirst().uppercased()
        }
        return trimmed.uppercased()
    }

    private func loadFixture(named name: String) throws -> String {
        let url = try fixtureURL(named: name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func loadShikiFixture(named name: String) throws -> ShikiFixture {
        let url = try fixtureURL(named: name)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ShikiFixture.self, from: data)
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
