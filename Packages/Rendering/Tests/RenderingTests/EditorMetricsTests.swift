import Testing
@testable import Rendering

@Suite("EditorMetrics Tests")
struct EditorMetricsTests {
    @Test("Visible lines rounds up and never drops below one")
    func visibleLines() {
        let metrics = EditorMetrics(
            cellWidth: 8,
            lineHeight: 20,
            fontSize: 13,
            baseline: 10,
            fontName: "Menlo"
        )

        #expect(metrics.visibleLines(for: 0) == 1)
        #expect(metrics.visibleLines(for: 39) == 2)
        #expect(metrics.visibleLines(for: 40) == 2)
        #expect(metrics.visibleLines(for: 41) == 3)
    }

    @Test("Column and x-position conversions account for gutter width")
    func columnConversions() {
        let metrics = EditorMetrics(
            cellWidth: 8,
            lineHeight: 20,
            fontSize: 13,
            baseline: 10,
            fontName: "Menlo",
            gutterWidth: 50
        )

        #expect(metrics.xPosition(forColumn: 0) == 50)
        #expect(metrics.xPosition(forColumn: 3) == 74)
        #expect(metrics.columnAt(x: 49) == 0)
        #expect(metrics.columnAt(x: 50) == 0)
        #expect(metrics.columnAt(x: 74) == 3)
    }
}
