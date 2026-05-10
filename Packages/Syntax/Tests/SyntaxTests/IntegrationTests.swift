import Foundation
import Testing
import Text
@testable import Syntax

@Suite("Syntax Integration Tests", .serialized)
struct IntegrationTests {
    @MainActor
    @Test("Theme registry keeps active identity aligned when a requested theme is missing")
    func themeRegistryRejectsMissingThemeWithoutIdentityDrift() {
        let defaultsKey = "Syntax.themeName"
        let defaults = UserDefaults.standard
        let previousPreference = defaults.string(forKey: defaultsKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
        }

        let registry = ThemeRegistry()
        registry.currentThemeName = "devys-light"
        #expect(registry.currentThemeName == "devys-light")
        #expect(registry.currentTheme?.name == "devys-light")

        registry.currentThemeName = "missing-theme"
        #expect(registry.currentThemeName == "devys-light")
        #expect(registry.currentTheme?.name == "devys-light")
    }

    @MainActor
    @Test("Syntax controller resolves visible highlights without loading placeholder state")
    func syntaxControllerResolvesVisibleHighlights() async throws {
        let controller = SyntaxController(
            lines: sampleLines,
            language: "swift",
            themeName: "devys-dark"
        )

        let visibleRange = SourceLineRange(0, sampleLines.count)
        let completed = await controller.prepareActualHighlights(
            visibleRange: visibleRange,
            preferredRange: visibleRange,
            batchSize: sampleLines.count,
            budgetNanoseconds: 50_000_000
        )

        let snapshot = controller.currentSnapshot()
        #expect(completed)
        #expect(snapshot.hasActualHighlights(in: 0..<sampleLines.count))
        #expect(snapshot.lines(in: 0..<sampleLines.count).allSatisfy { $0.value.status != .stale })
    }

    @MainActor
    @Test("Syntax controller resolves every shipped Tree-sitter language")
    func syntaxControllerResolvesShippedLanguages() async throws {
        for fixture in shippedLanguageFixtures {
            let controller = SyntaxController(
                lines: fixture.lines,
                language: fixture.language,
                themeName: "devys-dark"
            )

            let visibleRange = SourceLineRange(0, fixture.lines.count)
            let completed = await controller.prepareActualHighlights(
                visibleRange: visibleRange,
                preferredRange: visibleRange,
                batchSize: fixture.lines.count,
                budgetNanoseconds: 50_000_000
            )

            let snapshot = controller.currentSnapshot()
            #expect(completed)
            #expect(snapshot.hasActualHighlights(in: 0..<fixture.lines.count))
            #expect(snapshot.lines(in: 0..<fixture.lines.count).contains { !$0.value.tokens.isEmpty })
        }
    }

    @MainActor
    @Test("Incremental edits invalidate only bounded line ranges")
    func incrementalEditsInvalidateOnlyBoundedRanges() async throws {
        let originalDocument = TextDocument(content: sampleSource)
        let oldSnapshot = originalDocument.snapshot()
        let controller = SyntaxController(
            documentSnapshot: oldSnapshot,
            language: "swift",
            themeName: "devys-dark"
        )

        let fullRange = SourceLineRange(0, oldSnapshot.lineCount)
        _ = await controller.prepareActualHighlights(
            visibleRange: fullRange,
            preferredRange: fullRange,
            batchSize: oldSnapshot.lineCount,
            budgetNanoseconds: 50_000_000
        )

        let editedDocument = TextDocument(content: sampleSource)
        let transaction = EditTransaction(
            edits: [
                TextEdit(
                    range: utf8Range(of: "\"world\"", in: sampleSource),
                    replacement: "\"team\""
                )
            ]
        )
        _ = editedDocument.apply(transaction)
        let newSnapshot = editedDocument.snapshot()

        controller.updateDocument(
            SyntaxDocumentUpdate(
                oldSnapshot: oldSnapshot,
                newSnapshot: newSnapshot,
                transaction: transaction
            ),
            dirtyFrom: 2
        )

        let pendingSnapshot = controller.currentSnapshot()
        #expect(pendingSnapshot.line(0)?.status == .actual)
        #expect(pendingSnapshot.line(1)?.status == .stale)
        #expect(pendingSnapshot.line(2)?.status == .stale || pendingSnapshot.line(2) == nil)
        #expect(pendingSnapshot.line(4)?.status == .actual)
    }

    @Test("Invalidation subtraction removes only resolved lines")
    func invalidationSubtractionRemovesOnlyResolvedLines() {
        let invalidation = SyntaxInvalidationSet(
            lineRanges: [
                SourceLineRange(2, 6)
            ]
        )

        let remaining = invalidation.subtracting(3..<5)

        #expect(remaining.lineRanges == [SourceLineRange(2, 3), SourceLineRange(5, 6)])
    }

    @Test("Runtime diagnostics still track visible presentation without placeholder frames")
    func runtimeDiagnosticsTrackVisiblePresentationWithoutPlaceholders() {
        SyntaxRuntimeDiagnostics.reset()

        SyntaxRuntimeDiagnostics.recordVisiblePresentation(
            surface: "editor",
            actualHighlightedLines: 8,
            staleLines: 1,
            loadingLines: 2
        )
        SyntaxRuntimeDiagnostics.recordPrefetchSample(surface: "editor", hits: 9, misses: 2)

        let snapshot = SyntaxRuntimeDiagnostics.snapshot()
        #expect(snapshot.visibleHighlightedLines == 8)
        #expect(snapshot.visibleStaleLines == 1)
        #expect(snapshot.visibleLoadingLines == 2)
        #expect(snapshot.loadingPlaceholderFrames == 0)
        #expect(snapshot.prefetchHits == 9)
        #expect(snapshot.prefetchMisses == 2)
    }
}

private let sampleSource = """
struct Greeter {
    func greet() {
        let subject = "world"
        print(subject)
    }
}
"""

private let sampleLines = sampleSource.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

private let shippedLanguageFixtures: [(language: String, lines: [String])] = [
    ("c", fixtureLines(named: "sample.c")),
    ("cpp", fixtureLines(named: "sample.cpp")),
    ("csharp", fixtureLines(named: "sample.cs")),
    ("css", fixtureLines(named: "sample.css")),
    ("go", fixtureLines(named: "sample.go")),
    ("html", fixtureLines(named: "sample.html")),
    ("java", fixtureLines(named: "sample.java")),
    ("javascript", fixtureLines(named: "sample.js")),
    ("json", fixtureLines(named: "sample.json")),
    ("jsx", fixtureLines(named: "sample.jsx")),
    ("kotlin", fixtureLines(named: "sample.kt")),
    ("lua", fixtureLines(named: "sample.lua")),
    ("make", fixtureLines(named: "sample.mk")),
    ("markdown", fixtureLines(named: "sample.md")),
    ("php", fixtureLines(named: "sample.php")),
    ("python", fixtureLines(named: "sample.py")),
    ("ruby", fixtureLines(named: "sample.rb")),
    ("rust", fixtureLines(named: "sample.rs")),
    ("shellscript", fixtureLines(named: "sample.sh")),
    ("sql", fixtureLines(named: "sample.sql")),
    ("swift", fixtureLines(named: "sample.swift")),
    ("typescript", fixtureLines(named: "sample.ts")),
    ("tsx", fixtureLines(named: "sample.tsx")),
    ("yaml", fixtureLines(named: "sample.yaml"))
]

private func utf8Range(of needle: String, in haystack: String) -> TextByteRange {
    guard let range = haystack.range(of: needle) else {
        Issue.record("Missing needle '\(needle)' in test fixture.")
        return TextByteRange(0, 0)
    }

    let lowerBound = haystack.utf8.distance(from: haystack.startIndex, to: range.lowerBound)
    let upperBound = haystack.utf8.distance(from: haystack.startIndex, to: range.upperBound)
    return TextByteRange(lowerBound, upperBound)
}

private func fixtureLines(named name: String) -> [String] {
    let content = fixtureContents(named: name)
    return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

private func fixtureContents(named name: String) -> String {
    let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
    let fileURL = fixturesDirectory.appendingPathComponent(name)

    do {
        return try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
        Issue.record("Unable to load fixture \(name): \(error)")
        return ""
    }
}
