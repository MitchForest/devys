import AppKit
import CoreGraphics
import Foundation
import Testing
import Text
@testable import Syntax
import Rendering
@testable import Git

@MainActor
@Suite("Diff Syntax Language Parity Tests")
struct DiffSyntaxLanguageParityTests {
    @Test("Diff views resolve actual highlights for every shipped Tree-sitter language")
    func diffViewsResolveShippedLanguages() async {
        for fixture in shippedDiffLanguageFixtures {
            let snapshot = makeDiffSnapshot(
                fileName: fixture.fileName,
                baseContent: fixture.content,
                modifiedContent: mutatedContent(from: fixture.content)
            )
            let view = MetalDiffDocumentView(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
            defer { cancelBackgroundTasks(on: view) }

            view.updateLanguage(fixture.language)
            view.updateLayout(
                makeLayout(
                    from: snapshot,
                    mode: .split,
                    wrapLines: false,
                    splitRatio: 0.5
                )
            )

            await view.visibleHighlightBudgetTask?.value

            let visibleRanges = view.preferredHighlightRangesForVisibleRows()
            if let baseRange = visibleRanges.base {
                #expect(view.baseSyntaxController?.currentSnapshot().hasActualHighlights(in: baseRange) == true)
            }
            if let modifiedRange = visibleRanges.modified {
                #expect(view.modifiedSyntaxController?.currentSnapshot().hasActualHighlights(in: modifiedRange) == true)
            }
        }
    }

    private func makeDiffSnapshot(
        fileName: String,
        baseContent: String,
        modifiedContent: String
    ) -> DiffSnapshot {
        let baseLines = baseContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let modifiedLines = modifiedContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let removed = baseLines.map { "-\($0)" }.joined(separator: "\n")
        let added = modifiedLines.map { "+\($0)" }.joined(separator: "\n")
        let diff = DiffParser.parse("""
        --- a/\(fileName)
        +++ b/\(fileName)
        @@ -1,\(max(baseLines.count, 1)) +1,\(max(modifiedLines.count, 1)) @@
        \(removed)
        \(added)
        """)

        return DiffSnapshot(
            from: diff,
            baseContent: baseContent,
            modifiedContent: modifiedContent
        )
    }

    private func makeLayout(
        from snapshot: DiffSnapshot,
        mode: DiffViewMode,
        wrapLines: Bool,
        splitRatio: CGFloat
    ) -> DiffRenderLayout {
        let configuration = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: wrapLines,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        return DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: mode,
            configuration: configuration,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 800,
            splitRatio: splitRatio
        )
    }

    private func cancelBackgroundTasks(on view: MetalDiffDocumentView) {
        view.highlightTask?.cancel()
        view.highlightTask = nil
        view.visibleHighlightBudgetTask?.cancel()
        view.visibleHighlightBudgetTask = nil
    }
}

private let shippedDiffLanguageFixtures: [(fileName: String, language: String, content: String)] = [
    ("sample.c", "c", diffFixtureContents(named: "sample.c")),
    ("sample.cpp", "cpp", diffFixtureContents(named: "sample.cpp")),
    ("sample.cs", "csharp", diffFixtureContents(named: "sample.cs")),
    ("sample.css", "css", diffFixtureContents(named: "sample.css")),
    ("sample.go", "go", diffFixtureContents(named: "sample.go")),
    ("sample.html", "html", diffFixtureContents(named: "sample.html")),
    ("sample.java", "java", diffFixtureContents(named: "sample.java")),
    ("sample.js", "javascript", diffFixtureContents(named: "sample.js")),
    ("sample.json", "json", diffFixtureContents(named: "sample.json")),
    ("sample.jsx", "jsx", diffFixtureContents(named: "sample.jsx")),
    ("sample.kt", "kotlin", diffFixtureContents(named: "sample.kt")),
    ("sample.lua", "lua", diffFixtureContents(named: "sample.lua")),
    ("sample.mk", "make", diffFixtureContents(named: "sample.mk")),
    ("sample.md", "markdown", diffFixtureContents(named: "sample.md")),
    ("sample.php", "php", diffFixtureContents(named: "sample.php")),
    ("sample.py", "python", diffFixtureContents(named: "sample.py")),
    ("sample.rb", "ruby", diffFixtureContents(named: "sample.rb")),
    ("sample.rs", "rust", diffFixtureContents(named: "sample.rs")),
    ("sample.sh", "shellscript", diffFixtureContents(named: "sample.sh")),
    ("sample.sql", "sql", diffFixtureContents(named: "sample.sql")),
    ("sample.swift", "swift", diffFixtureContents(named: "sample.swift")),
    ("sample.ts", "typescript", diffFixtureContents(named: "sample.ts")),
    ("sample.tsx", "tsx", diffFixtureContents(named: "sample.tsx")),
    ("sample.yaml", "yaml", diffFixtureContents(named: "sample.yaml"))
]

private func diffFixtureContents(named name: String) -> String {
    let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Syntax/Tests/SyntaxTests/Fixtures", isDirectory: true)
    let fileURL = fixturesDirectory.appendingPathComponent(name)

    do {
        return try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
        Issue.record("Unable to load diff fixture \(name): \(error)")
        return ""
    }
}

private func mutatedContent(from content: String) -> String {
    for target in ["Devys", "Ada", "Hello", "42", "1.0.0", "clicked"] {
        if let range = content.range(of: target) {
            return content.replacingCharacters(in: range, with: "Updated")
        }
    }

    return content + "\nupdated"
}
