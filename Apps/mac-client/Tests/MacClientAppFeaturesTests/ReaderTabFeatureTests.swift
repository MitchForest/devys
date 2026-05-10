import ComposableArchitecture
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class ReaderTabFeatureTests: XCTestCase {
    func testReadableRouting() {
        XCTAssertTrue(MarkdownReaderRouting.isReadable(URL(fileURLWithPath: "/repo/README.md")))
        XCTAssertTrue(MarkdownReaderRouting.isReadable(URL(fileURLWithPath: "/repo/notes.mdx")))
        XCTAssertTrue(MarkdownReaderRouting.isReadable(URL(fileURLWithPath: "/repo/plain.txt")))
        XCTAssertFalse(MarkdownReaderRouting.isReadable(URL(fileURLWithPath: "/repo/App.swift")))
    }

    func testModeAndRelativePathAreReducerOwned() async {
        let rootURL = URL(fileURLWithPath: "/Users/devys/project")
        let fileURL = rootURL.appendingPathComponent("README.md")
        let store = TestStore(
            initialState: ReaderTabFeature.State(fileURL: fileURL, projectRootURL: rootURL)
        ) {
            ReaderTabFeature()
        }

        XCTAssertEqual(store.state.relativePath, "README.md")
        await store.send(.modeChanged(.edit)) {
            $0.mode = .edit
        }
        await store.send(.toggleMode) {
            $0.mode = .read
        }
    }

    func testDocumentContentChangedParsesBlocks() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let store = TestStore(initialState: ReaderTabFeature.State(fileURL: fileURL)) {
            ReaderTabFeature()
        }

        await store.send(.documentContentChanged("# Title\n\nBody")) {
            $0.blocks = MarkdownDocumentParser.parse("# Title\n\nBody")
        }
        XCTAssertEqual(store.state.blocks.count, 2)
    }

    func testDirtyStateIsReducerVisible() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let store = TestStore(initialState: ReaderTabFeature.State(fileURL: fileURL)) {
            ReaderTabFeature()
        }

        await store.send(.dirtyStateChanged(true)) {
            $0.isDirty = true
        }
        await store.send(.dirtyStateChanged(false)) {
            $0.isDirty = false
        }
    }

    func testRevealCommandIntentRunsThroughDependency() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let recorder = ReaderTabRecorder()
        let store = TestStore(initialState: ReaderTabFeature.State(fileURL: fileURL)) {
            ReaderTabFeature()
        } withDependencies: {
            $0.documentClient = DocumentClient(
                loadPreview: { _, _ in throw ReaderTabFeatureTestError.unused },
                save: { _, _ in },
                revealInFinder: { url in
                    await recorder.recordReveal(url)
                }
            )
        }

        await store.send(.revealInFinderRequested)
        await store.receive(.revealInFinderFinished)
        let revealedURLs = await recorder.revealedURLs()
        XCTAssertEqual(revealedURLs, [fileURL])
    }

    func testMarkdownParserRecognizesCoreBlocks() {
        let blocks = MarkdownDocumentParser.parse(
            """
            # Title

            Intro **bold**

            - Item
              1. Nested
            > Quote

            ---

            ```
            let value = 1
            ```
            """
        )

        XCTAssertEqual(blocks.count, 7)
        XCTAssertEqual(blocks[0].headingLevel, 1)
        XCTAssertEqual(blocks[1].plainText, "Intro bold")
        XCTAssertEqual(blocks[2].bulletDepth, 0)
        XCTAssertEqual(blocks[3].numberedMarker, "1.")
        XCTAssertEqual(blocks[4].plainText, "Quote")
        XCTAssertTrue(blocks[5].isHorizontalRule)
        XCTAssertEqual(blocks[6].codeBody, "let value = 1")
    }
}

private enum ReaderTabFeatureTestError: Error {
    case unused
}

private actor ReaderTabRecorder {
    private var revealedValues: [URL] = []

    func recordReveal(_ url: URL) {
        revealedValues.append(url)
    }

    func revealedURLs() -> [URL] {
        revealedValues
    }
}

private extension MarkdownBlock {
    var headingLevel: Int? {
        if case .heading(let level, _) = kind { return level }
        return nil
    }

    var bulletDepth: Int? {
        if case .bullet(_, let depth) = kind { return depth }
        return nil
    }

    var numberedMarker: String? {
        if case .numbered(let marker, _, _) = kind { return marker }
        return nil
    }

    var isHorizontalRule: Bool {
        if case .horizontalRule = kind { return true }
        return false
    }

    var codeBody: String? {
        if case .code(let body) = kind { return body }
        return nil
    }

    var plainText: String? {
        switch kind {
        case .heading(_, let attributed),
             .prose(let attributed),
             .bullet(let attributed, _),
             .numbered(_, let attributed, _),
             .blockquote(let attributed):
            String(attributed.characters)
        case .code(let body):
            body
        case .horizontalRule:
            nil
        }
    }
}
