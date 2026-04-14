import Foundation
import Testing
import Workspace
@testable import mac_client

@Suite("Workspace File Index Tests")
struct WorkspaceFileIndexTests {
    @Test("Reload indexes files and respects explorer exclusions")
    @MainActor
    func reloadIndexesFilesAndRespectsExplorerExclusions() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try makeFile(at: rootURL.appendingPathComponent("README.md"), contents: "docs")
        try makeFile(at: rootURL.appendingPathComponent("Sources/App.swift"), contents: "let app = true")
        try makeFile(at: rootURL.appendingPathComponent("Sources/.secret.swift"), contents: "secret")
        try makeFile(at: rootURL.appendingPathComponent(".git/config"), contents: "[core]")
        try makeFile(at: rootURL.appendingPathComponent("ignore.me"), contents: "ignored")

        let index = WorkspaceFileIndex(rootURL: rootURL) {
            ExplorerSettings(showDotfiles: false, excludePatterns: [".git", "ignore.me"])
        }

        index.reload()

        #expect(await waitUntil { index.isLoading == false })
        #expect(index.lastError == nil)
        #expect(Set(index.entries.map(\.relativePath)) == ["README.md", "Sources/App.swift"])
    }

    @Test("Matches favor open files over equally matching paths")
    @MainActor
    func matchesFavorOpenFiles() async throws {
        let rootURL = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let openURL = rootURL.appendingPathComponent("Sources/ViewModel.swift")
        let otherURL = rootURL.appendingPathComponent("Views/View.swift")
        try makeFile(at: openURL, contents: "struct ViewModel {}")
        try makeFile(at: otherURL, contents: "struct View {}")

        let index = WorkspaceFileIndex(rootURL: rootURL) {
            ExplorerSettings(showDotfiles: true, excludePatterns: [])
        }

        index.reload()

        #expect(await waitUntil { index.isLoading == false })

        let matches = index.matches(for: "view", openURLs: [openURL])
        #expect(matches.count == 2)
        #expect(matches.first?.entry.fileURL == openURL.standardizedFileURL)
    }

    @MainActor
    private func makeTemporaryDirectory() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func makeFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    interval: Duration = .milliseconds(20),
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: interval)
    }

    return condition()
}
