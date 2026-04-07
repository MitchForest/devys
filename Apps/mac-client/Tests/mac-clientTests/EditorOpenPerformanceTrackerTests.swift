import Testing
@testable import mac_client

@Suite("Editor Open Performance Tracker Tests")
struct EditorOpenPerformanceTrackerTests {
    @Test("Text loads emit ordered checkpoints and a final loaded outcome")
    func textLoadCheckpoints() {
        var tracker = EditorOpenPerformanceTracker()

        #expect(
            tracker.recordPresentation(.loading) == [
                .checkpoint(
                    name: "tab-visible",
                    context: ["file_size_bucket": "unknown"]
                )
            ]
        )

        #expect(
            tracker.recordPresentation(.previewText(fileSize: 180_000)) == [
                .checkpoint(
                    name: "preview-content-visible",
                    context: ["file_size_bucket": "0_256kb"]
                )
            ]
        )

        #expect(
            tracker.recordPresentation(.loaded(fileSize: 180_000)) == [
                .checkpoint(
                    name: "interactive-document-visible",
                    context: ["file_size_bucket": "0_256kb"]
                ),
                .finish(
                    outcome: "text_loaded",
                    context: ["file_size_bucket": "0_256kb"]
                )
            ]
        )
    }

    @Test("Loaded content can coalesce preview and interactive checkpoints")
    func coalescedLoadedContent() {
        var tracker = EditorOpenPerformanceTracker()

        #expect(
            tracker.recordPresentation(.loaded(fileSize: 700_000)) == [
                .checkpoint(
                    name: "tab-visible",
                    context: ["file_size_bucket": "256kb_1mb"]
                ),
                .checkpoint(
                    name: "preview-content-visible",
                    context: ["file_size_bucket": "256kb_1mb"]
                ),
                .checkpoint(
                    name: "interactive-document-visible",
                    context: ["file_size_bucket": "256kb_1mb"]
                ),
                .finish(
                    outcome: "text_loaded",
                    context: ["file_size_bucket": "256kb_1mb"]
                )
            ]
        )
    }

    @Test("Preview-only outcomes finish without full interactive checkpoints")
    func previewOnlyOutcomes() {
        var binaryTracker = EditorOpenPerformanceTracker()
        #expect(
            binaryTracker.recordPresentation(.binary(fileSize: 32_000)) == [
                .checkpoint(
                    name: "tab-visible",
                    context: ["file_size_bucket": "0_256kb"]
                ),
                .finish(
                    outcome: "binary",
                    context: ["file_size_bucket": "0_256kb"]
                )
            ]
        )

        var tooLargeTracker = EditorOpenPerformanceTracker()
        #expect(
            tooLargeTracker.recordPresentation(.tooLarge(fileSize: 8_388_608)) == [
                .checkpoint(
                    name: "tab-visible",
                    context: ["file_size_bucket": "4mb_plus"]
                ),
                .finish(
                    outcome: "too_large",
                    context: ["file_size_bucket": "4mb_plus"]
                )
            ]
        )
    }
}
