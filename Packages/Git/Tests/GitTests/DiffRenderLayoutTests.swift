// DiffRenderLayoutTests.swift
// Tests for diff layout building.

import Testing
import Rendering
@testable import Git

@MainActor
struct DiffRenderLayoutTests {
    @Test func unifiedLayoutWrapsLines() {
        let diff = """
        --- a/file.swift
        +++ b/file.swift
        @@ -1,1 +1,1 @@
        -let greeting = \"Hello, World!\"
        +let greeting = \"Hello, Wonderful World!\"
        """

        let parsed = DiffParser.parse(diff)
        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: true,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        let snapshot = makeActualDiffSnapshot(parsed)

        let layout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .unified,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 200
        )

        switch layout {
        case .unified(let unified):
            #expect(unified.rows.count > 2)
        case .split:
            #expect(Bool(false), "Expected unified layout")
        }
    }

    @Test func hiddenHunkHeadersReserveEnoughRowsForOverlayHeight() throws {
        let parsed = DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let greeting = "Hello"
        +let greeting = "Hello, Devys"
         print(greeting)
        """)

        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: false,
            changeStyle: .fullBackground,
            showsHunkHeaders: false
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        let snapshot = makeActualDiffSnapshot(parsed)

        let layout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .unified,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 320
        )

        guard case .unified(let unified) = layout else {
            Issue.record("Expected unified layout")
            return
        }

        let headerIndex = try #require(unified.rows.firstIndex(where: { $0.kind == .hunkHeader }))
        let firstContentIndex = try #require(
            unified.rows.firstIndex(where: { $0.kind == .line && !$0.content.isEmpty })
        )
        let reservedRows = firstContentIndex - headerIndex

        #expect(reservedRows == DiffChromeMetrics.hiddenHunkSpacerRowCount(lineHeight: metrics.lineHeight) + 1)
    }

    @Test func unifiedLayoutIDsRemainStableAcrossRebuilds() {
        let parsed = DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let greeting = \"Hello\"
        +let greeting = \"Hello, Devys\"
         print(greeting)
        """)

        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: false,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        let snapshot = makeActualDiffSnapshot(parsed)

        let firstLayout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .unified,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 320
        )

        let secondLayout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .unified,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 640
        )

        guard case .unified(let first) = firstLayout else {
            Issue.record("Expected unified layout for first build")
            return
        }

        guard case .unified(let second) = secondLayout else {
            Issue.record("Expected unified layouts")
            return
        }

        #expect(first.rows.map(\.id) == second.rows.map(\.id))
        #expect(first.sourceDocuments.baseSnapshot.version == second.sourceDocuments.baseSnapshot.version)
        #expect(first.sourceDocuments.modifiedSnapshot.version == second.sourceDocuments.modifiedSnapshot.version)
    }

    @Test func splitLayoutIDsRemainStableAcrossRebuilds() {
        let parsed = DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let greeting = \"Hello\"
        +let greeting = \"Hello, Devys\"
         print(greeting)
        """)

        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: false,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        let snapshot = makeActualDiffSnapshot(parsed)

        let firstLayout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .split,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 360,
            splitRatio: 0.5
        )

        let secondLayout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .split,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 640,
            splitRatio: 0.62
        )

        guard case .split(let first) = firstLayout else {
            Issue.record("Expected split layout for first build")
            return
        }

        guard case .split(let second) = secondLayout else {
            Issue.record("Expected split layouts")
            return
        }

        #expect(first.rows.map(\.id) == second.rows.map(\.id))
        #expect(first.sourceDocuments.baseSnapshot.version == second.sourceDocuments.baseSnapshot.version)
        #expect(first.sourceDocuments.modifiedSnapshot.version == second.sourceDocuments.modifiedSnapshot.version)
    }

    @Test func unifiedLayoutCarriesStableHighlightSegmentsForWrappedRows() {
        let parsed = DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let greeting = "Hello from the original side of this diff"
        +let greeting = "Hello from the modified side of this diff"
         print(greeting)
        """)

        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: true,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        let snapshot = makeActualDiffSnapshot(parsed)

        let layout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .unified,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 220
        )

        guard case .unified(let unified) = layout else {
            Issue.record("Expected unified layout")
            return
        }

        let removedRows = unified.rows.filter { $0.lineType == .removed }
        #expect(removedRows.count > 1)
        #expect(removedRows.allSatisfy { $0.highlightSegment?.side == .base })
        #expect(Set(removedRows.compactMap { $0.highlightSegment?.sourceLineIndex }).count == 1)
        #expect(
            removedRows.compactMap(\.highlightSegment).map(\.utf16Range)
                == contiguousRangesCoveringWholeText(for: removedRows.compactMap(\.highlightSegment))
        )

        let addedRows = unified.rows.filter { $0.lineType == .added }
        #expect(addedRows.count > 1)
        #expect(addedRows.allSatisfy { $0.highlightSegment?.side == .modified })
        #expect(Set(addedRows.compactMap { $0.highlightSegment?.sourceLineIndex }).count == 1)
        #expect(
            addedRows.compactMap(\.highlightSegment).map(\.utf16Range)
                == contiguousRangesCoveringWholeText(for: addedRows.compactMap(\.highlightSegment))
        )

        #expect(unified.sourceDocuments.baseSourceLineCount == 2)
        #expect(unified.sourceDocuments.modifiedSourceLineCount == 2)
    }

    @Test func splitLayoutAssignsSourceIndicesPerSide() {
        let parsed = DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let oldValue = 1
        +let newValue = 2
         print("shared")
        """)

        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: false,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")
        let snapshot = makeActualDiffSnapshot(parsed)

        let layout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .split,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 420,
            splitRatio: 0.5
        )

        guard case .split(let split) = layout else {
            Issue.record("Expected split layout")
            return
        }

        guard let changedRow = split.rows.first(
            where: { $0.left?.lineType == .removed || $0.right?.lineType == .added }
        ) else {
            Issue.record("Expected changed split row")
            return
        }
        #expect(changedRow.left?.highlightSegment?.side == .base)
        #expect(changedRow.right?.highlightSegment?.side == .modified)
        #expect(changedRow.left?.highlightSegment?.sourceLineIndex == 0)
        #expect(changedRow.right?.highlightSegment?.sourceLineIndex == 0)

        guard let sharedRow = split.rows.first(
            where: { $0.left?.content == "print(\"shared\")" && $0.right?.content == "print(\"shared\")" }
        ) else {
            Issue.record("Expected shared split row")
            return
        }
        #expect(sharedRow.left?.highlightSegment?.side == .base)
        #expect(sharedRow.right?.highlightSegment?.side == .modified)
        #expect(sharedRow.left?.highlightSegment?.sourceLineIndex == 1)
        #expect(sharedRow.right?.highlightSegment?.sourceLineIndex == 1)
        #expect(split.sourceDocuments.sourceLines(for: .base) == ["let oldValue = 1", "print(\"shared\")"])
        #expect(split.sourceDocuments.sourceLines(for: .modified) == ["let newValue = 2", "print(\"shared\")"])
    }

    @Test func unifiedAndSplitProjectionsShareSourceDocumentVersions() {
        let snapshot = makeActualDiffSnapshot(DiffParser.parse("""
        --- a/file.swift
        +++ b/file.swift
        @@ -1,2 +1,2 @@
        -let greeting = "Hello"
        +let greeting = "Hello, Devys"
        print(greeting)
        """))
        let config = DiffRenderConfiguration(
            fontName: "Menlo",
            fontSize: 12,
            showLineNumbers: true,
            showPrefix: true,
            showWordDiff: true,
            wrapLines: true,
            changeStyle: .fullBackground,
            showsHunkHeaders: true
        )
        let metrics = EditorMetrics.measure(fontSize: 12, fontName: "Menlo")

        let unifiedLayout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .unified,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 320
        )
        let splitLayout = DiffRenderLayoutBuilder.build(
            snapshot: snapshot,
            mode: .split,
            configuration: config,
            lineHeight: metrics.lineHeight,
            cellWidth: metrics.cellWidth,
            availableWidth: 640,
            splitRatio: 0.63
        )

        guard case .unified(let unified) = unifiedLayout else {
            Issue.record("Expected unified layout")
            return
        }
        guard case .split(let split) = splitLayout else {
            Issue.record("Expected split layout")
            return
        }

        #expect(unified.sourceDocuments.baseSnapshot.version == split.sourceDocuments.baseSnapshot.version)
        #expect(unified.sourceDocuments.modifiedSnapshot.version == split.sourceDocuments.modifiedSnapshot.version)
        #expect(unified.sourceDocuments.lineMappings == split.sourceDocuments.lineMappings)
    }
}

private func contiguousRangesCoveringWholeText(
    for segments: [DiffHighlightSegment]
) -> [Range<Int>] {
    guard !segments.isEmpty else { return [] }

    var expected: [Range<Int>] = []
    var cursor = 0
    for segment in segments {
        let length = segment.utf16Range.upperBound - segment.utf16Range.lowerBound
        expected.append(cursor..<(cursor + length))
        cursor += length
    }

    return expected
}

private func makeActualDiffSnapshot(_ parsed: ParsedDiff) -> DiffSnapshot {
    var baseLines: [String] = []
    var modifiedLines: [String] = []

    for hunk in parsed.hunks {
        for line in hunk.lines where line.type != .header {
            switch line.type {
            case .context:
                baseLines.append(line.content)
                modifiedLines.append(line.content)
            case .removed:
                baseLines.append(line.content)
            case .added:
                modifiedLines.append(line.content)
            case .noNewline, .header:
                break
            }
        }
    }

    return DiffSnapshot(
        from: parsed,
        baseContent: baseLines.joined(separator: "\n"),
        modifiedContent: modifiedLines.joined(separator: "\n")
    )
}
