import ComposableArchitecture
import Editor
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class FileTabFeatureTests: XCTestCase {
    func testTaskLoadsTextPreviewAndRelativePath() async {
        let rootURL = URL(fileURLWithPath: "/Users/devys/project")
        let fileURL = rootURL.appendingPathComponent("Sources/App.swift")
        let preview = filePreview(kind: .text("let value = 1"))
        let store = TestStore(
            initialState: FileTabFeature.State(fileURL: fileURL, projectRootURL: rootURL)
        ) {
            FileTabFeature()
        } withDependencies: {
            $0.documentClient = documentClient(loadPreview: { url, _ in
                XCTAssertEqual(url, fileURL)
                return preview
            })
        }

        XCTAssertEqual(store.state.relativePath, "Sources/App.swift")
        await store.send(.task) {
            $0.phase = .loading
        }
        await store.receive(.previewLoaded(preview)) {
            $0.phase = .preview(preview)
        }
    }

    func testEditorLoadedMarksLoaded() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        }

        await store.send(.editorLoaded) {
            $0.phase = .loaded
        }
    }

    func testBinaryPreviewIsReducerVisible() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/image.bin")
        let preview = filePreview(kind: .binary)
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        } withDependencies: {
            $0.documentClient = documentClient(loadPreview: { _, _ in preview })
        }

        await store.send(.task) {
            $0.phase = .loading
        }
        await store.receive(.previewLoaded(preview)) {
            $0.phase = .preview(preview)
        }
        XCTAssertTrue(preview.isBinary)
    }

    func testTooLargePreviewIsReducerVisible() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/large.log")
        let preview = filePreview(
            kind: .tooLarge,
            revision: DocumentPreviewRevision(fileSize: 2_000_000, contentModificationDate: nil),
            exceededLimit: true
        )
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        } withDependencies: {
            $0.documentClient = documentClient(loadPreview: { _, _ in preview })
        }

        await store.send(.task) {
            $0.phase = .loading
        }
        await store.receive(.previewLoaded(preview)) {
            $0.phase = .preview(preview)
        }
        XCTAssertTrue(preview.isTooLarge)
    }

    func testDirtyStateIsReducerVisible() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        }

        await store.send(.dirtyStateChanged(true)) {
            $0.isDirty = true
        }
        await store.send(.dirtyStateChanged(false)) {
            $0.isDirty = false
        }
    }

    func testSaveSuccessClearsDirtyState() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let recorder = FileTabRecorder()
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        } withDependencies: {
            $0.documentClient = documentClient(save: { content, url in
                await recorder.recordSave(content: content, url: url)
            })
        }

        await store.send(.dirtyStateChanged(true)) {
            $0.isDirty = true
        }
        await store.send(.saveRequested(content: "updated", saveURL: nil)) {
            $0.isSaving = true
            $0.saveErrorMessage = nil
        }
        await store.receive(.saveSucceeded(fileURL)) {
            $0.isSaving = false
            $0.isDirty = false
        }
        let saves = await recorder.saves()
        XCTAssertEqual(saves, ["updated@\(fileURL.path)"])
    }

    func testSaveFailureKeepsDirtyStateAndStoresError() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        } withDependencies: {
            $0.documentClient = documentClient(save: { _, _ in
                throw FileTabFeatureTestError.saveFailed
            })
        }

        await store.send(.dirtyStateChanged(true)) {
            $0.isDirty = true
        }
        await store.send(.saveRequested(content: "updated", saveURL: nil)) {
            $0.isSaving = true
            $0.saveErrorMessage = nil
        }
        await store.receive(.saveFailed("saveFailed")) {
            $0.isSaving = false
            $0.saveErrorMessage = "saveFailed"
        }
    }

    func testRevealCommandIntentRunsThroughDependency() async {
        let fileURL = URL(fileURLWithPath: "/Users/devys/project/README.md")
        let recorder = FileTabRecorder()
        let store = TestStore(initialState: FileTabFeature.State(fileURL: fileURL)) {
            FileTabFeature()
        } withDependencies: {
            $0.documentClient = documentClient(revealInFinder: { url in
                await recorder.recordReveal(url: url)
            })
        }

        await store.send(.revealInFinderRequested)
        await store.receive(.revealInFinderFinished)
        let revealedURLs = await recorder.revealedURLs()
        XCTAssertEqual(revealedURLs, [fileURL])
    }
}

private func filePreview(
    kind: LoadedDocumentPreviewKind,
    revision: DocumentPreviewRevision = DocumentPreviewRevision(fileSize: 10, contentModificationDate: nil),
    exceededLimit: Bool = false
) -> LoadedDocumentPreview {
    LoadedDocumentPreview(
        kind: kind,
        language: "swift",
        revision: revision,
        exceededLimit: exceededLimit,
        maxBytes: 1_500_000
    )
}

private func documentClient(
    loadPreview: @escaping @Sendable (URL, DocumentPreviewRequest) async throws -> LoadedDocumentPreview = { _, _ in
        filePreview(kind: .text(""))
    },
    save: @escaping @Sendable (String, URL) async throws -> Void = { _, _ in },
    revealInFinder: @escaping @Sendable (URL) async -> Void = { _ in }
) -> DocumentClient {
    DocumentClient(
        loadPreview: loadPreview,
        save: save,
        revealInFinder: revealInFinder
    )
}

private enum FileTabFeatureTestError: Error, LocalizedError {
    case saveFailed

    var errorDescription: String? {
        "saveFailed"
    }
}

private actor FileTabRecorder {
    private var savedValues: [String] = []
    private var revealedValues: [URL] = []

    func recordSave(content: String, url: URL) {
        savedValues.append("\(content)@\(url.path)")
    }

    func recordReveal(url: URL) {
        revealedValues.append(url)
    }

    func saves() -> [String] {
        savedValues
    }

    func revealedURLs() -> [URL] {
        revealedValues
    }
}
