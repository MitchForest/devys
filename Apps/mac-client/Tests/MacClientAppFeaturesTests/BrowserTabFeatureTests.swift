import ComposableArchitecture
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class BrowserTabFeatureTests: XCTestCase {
    func testURLNormalization() {
        XCTAssertEqual(
            BrowserTabRouting.normalizedUserURL(" localhost:3000 ")?.absoluteString,
            "http://localhost:3000"
        )
        XCTAssertEqual(
            BrowserTabRouting.normalizedUserURL("example.com")?.absoluteString,
            "https://example.com"
        )
        XCTAssertEqual(
            BrowserTabRouting.normalizedUserURL("https://example.com/docs")?.absoluteString,
            "https://example.com/docs"
        )
        XCTAssertNil(BrowserTabRouting.normalizedUserURL("   "))
    }

    func testFileReadAccessUsesProjectRootForDescendantFiles() {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let fileURL = rootURL.appendingPathComponent("web/index.html")

        XCTAssertTrue(BrowserTabRouting.isBrowserPreviewFile(fileURL))
        XCTAssertEqual(
            BrowserTabRouting.readAccessURL(for: fileURL, projectRootURL: rootURL),
            rootURL.standardizedFileURL
        )
    }

    func testFileReadAccessFallsBackToFileDirectoryOutsideProject() {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let fileURL = URL(fileURLWithPath: "/tmp/other/index.html")

        XCTAssertEqual(
            BrowserTabRouting.readAccessURL(for: fileURL, projectRootURL: rootURL),
            fileURL.deletingLastPathComponent().standardizedFileURL
        )
    }

    func testMetadataChangeUpdatesReducerOwnedTitleAndURL() async {
        let initialURL = URL(string: "http://localhost:3000")!
        let nextURL = URL(string: "http://localhost:5173/app")!
        let store = TestStore(initialState: BrowserTabFeature.State(url: initialURL)) {
            BrowserTabFeature()
        }

        XCTAssertEqual(store.state.displayTitle, "localhost")
        await store.send(.metadataChanged(BrowserTabMetadata(url: nextURL, title: "Preview"))) {
            $0.url = nextURL
            $0.title = "Preview"
        }
        XCTAssertEqual(store.state.displayTitle, "Preview")
    }
}
