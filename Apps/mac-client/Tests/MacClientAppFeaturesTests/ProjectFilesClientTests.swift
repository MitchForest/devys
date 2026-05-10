@testable import MacClientAppFeatures
import XCTest

final class ProjectFilesClientTests: XCTestCase {
    func testVisibleRowsSortDirectoriesFirstAndRespectExpansion() throws {
        let rootURL = try makeTemporaryProject()
        try makeDirectory(rootURL.appendingPathComponent("Sources"))
        try writeFile(rootURL.appendingPathComponent("README.md"))
        try writeFile(rootURL.appendingPathComponent("Sources/App.swift"))

        let rows = ProjectFilesClient.loadRowsSynchronously(
            ProjectFilesRequest(
                rootURL: rootURL,
                expandedDirectoryPaths: [rootURL.appendingPathComponent("Sources").path]
            )
        )

        XCTAssertEqual(rows.map(\.url.lastPathComponent), ["Sources", "App.swift", "README.md"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
        XCTAssertEqual(rows.map(\.isDirectory), [true, false, false])
    }

    func testSearchRowsFindNestedMatches() throws {
        let rootURL = try makeTemporaryProject()
        try makeDirectory(rootURL.appendingPathComponent("Sources"))
        try writeFile(rootURL.appendingPathComponent("Sources/AppFeature.swift"))
        try writeFile(rootURL.appendingPathComponent("README.md"))

        let rows = ProjectFilesClient.loadRowsSynchronously(
            ProjectFilesRequest(rootURL: rootURL, query: "feature")
        )

        XCTAssertEqual(rows.map(\.url.lastPathComponent), ["AppFeature.swift"])
        XCTAssertEqual(rows.map(\.depth), [1])
    }

    func testNoisyDirectoriesAreSkippedInVisibleAndSearchRows() throws {
        let rootURL = try makeTemporaryProject()
        try makeDirectory(rootURL.appendingPathComponent("node_modules/pkg"))
        try writeFile(rootURL.appendingPathComponent("node_modules/pkg/index.js"))
        try makeDirectory(rootURL.appendingPathComponent(".git"))
        try writeFile(rootURL.appendingPathComponent(".git/config"))
        try writeFile(rootURL.appendingPathComponent("Package.swift"))

        let visibleRows = ProjectFilesClient.loadRowsSynchronously(
            ProjectFilesRequest(rootURL: rootURL, expandedDirectoryPaths: [rootURL.appendingPathComponent("node_modules").path])
        )
        let searchedRows = ProjectFilesClient.loadRowsSynchronously(
            ProjectFilesRequest(rootURL: rootURL, query: "index")
        )

        XCTAssertEqual(visibleRows.map(\.url.lastPathComponent), ["Package.swift"])
        XCTAssertTrue(searchedRows.isEmpty)
    }

    func testRowBudgetIsRespected() throws {
        let rootURL = try makeTemporaryProject()
        try writeFile(rootURL.appendingPathComponent("A.md"))
        try writeFile(rootURL.appendingPathComponent("B.md"))
        try writeFile(rootURL.appendingPathComponent("C.md"))

        let rows = ProjectFilesClient.loadRowsSynchronously(
            ProjectFilesRequest(rootURL: rootURL, rowBudget: 2)
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.url.lastPathComponent), ["A.md", "B.md"])
    }

    private func makeTemporaryProject() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-project-files-\(UUID().uuidString)")
        try makeDirectory(rootURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootURL)
        }
        return rootURL
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func writeFile(_ url: URL) throws {
        try "content".write(to: url, atomically: true, encoding: .utf8)
    }
}
