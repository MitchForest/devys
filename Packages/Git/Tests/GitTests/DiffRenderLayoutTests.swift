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

        let layout = DiffRenderLayoutBuilder.build(
            diff: parsed,
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
}
