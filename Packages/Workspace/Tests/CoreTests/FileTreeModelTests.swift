import Foundation
import Testing
@testable import Workspace

@Suite("FileTreeModel Tests")
struct FileTreeModelTests {
    @Test("Reloading an active tree reuses the existing watcher")
    @MainActor
    func refreshReusesExistingWatcher() async {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()

        await model.loadTree()
        await model.refresh()

        #expect(fixture.fileTreeService.buildTreeCallCount == 2)
        #expect(fixture.watchServiceFactory.services.count == 1)
        #expect(fixture.watchServiceFactory.services.first?.startWatchingCallCount == 1)
        #expect(fixture.watchServiceFactory.services.first?.stopWatchingCallCount == 0)
    }

    @Test("Deactivating and reactivating a loaded tree reuses the same watcher client")
    @MainActor
    func deactivateStopsWatchingWithoutRebuild() async {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()

        await model.loadTreeIfNeeded()
        model.deactivate()
        await model.loadTreeIfNeeded()

        #expect(fixture.fileTreeService.buildTreeCallCount == 1)
        #expect(fixture.watchServiceFactory.services.count == 1)
        #expect(fixture.watchServiceFactory.services.first?.stopWatchingCallCount == 1)
        #expect(fixture.watchServiceFactory.services.first?.startWatchingCallCount == 2)
    }

    @Test("Common file mutations reload only the affected directory")
    @MainActor
    func modifiedEventsReloadOnlyAffectedDirectory() async throws {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()
        let sourcesDirectoryURL = fixture.rootURL.appendingPathComponent("Sources")
        let docsDirectoryURL = fixture.rootURL.appendingPathComponent("Docs")

        await model.loadTree()
        try await expandDirectory(named: "Sources", in: model)
        try await expandDirectory(named: "Docs", in: model)
        fixture.fileTreeService.resetLoadChildrenCallCounts()

        await model.handleFileChange(.modified, at: sourcesDirectoryURL.appendingPathComponent("App.swift"))

        #expect(fixture.fileTreeService.buildTreeCallCount == 1)
        #expect(fixture.fileTreeService.loadChildrenCallCount(for: sourcesDirectoryURL) == 1)
        #expect(fixture.fileTreeService.loadChildrenCallCount(for: docsDirectoryURL) == 0)
    }

    @Test("Directory rename preserves expansion state when retargeting is safe")
    @MainActor
    func renameRetargetsExpandedDirectoryState() async throws {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()
        let engineDirectoryURL = fixture.rootURL.appendingPathComponent("Engine")
        let sourcesDirectoryURL = fixture.rootURL.appendingPathComponent("Sources")

        await model.loadTree()
        try await expandDirectory(named: "Sources", in: model)
        fixture.fileTreeService.renameRootDirectory(from: "Sources", to: "Engine")
        fixture.fileTreeService.resetLoadChildrenCallCounts()

        await model.handleFileChange(.renamed, at: engineDirectoryURL)

        let flattenedNames = model.flattenedNodes.map { $0.node.name }
        #expect(flattenedNames.contains("Engine"))
        #expect(flattenedNames.contains("App.swift"))
        #expect(!flattenedNames.contains("Sources"))
        #expect(fixture.fileTreeService.buildTreeCallCount == 1)
        #expect(fixture.fileTreeService.loadChildrenCallCount(for: fixture.rootURL) == 1)
        #expect(fixture.fileTreeService.loadChildrenCallCount(for: sourcesDirectoryURL) == 0)
    }

    @Test("Overflow falls back to a full reload")
    @MainActor
    func overflowFallsBackToFullReload() async {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()

        await model.loadTree()
        await model.handleFileChange(.overflow, at: fixture.rootURL)

        #expect(fixture.fileTreeService.buildTreeCallCount == 2)
    }

    @Test("Selection uses normalized URLs and supports replace toggle and range operations")
    @MainActor
    func selectionOperationsUseURLs() async throws {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()

        await model.loadTree()

        let docsURL = fixture.rootURL.appendingPathComponent("Docs").standardizedFileURL
        let sourcesURL = fixture.rootURL.appendingPathComponent("Sources").standardizedFileURL
        let visibleURLs = model.flattenedNodes.map { $0.node.url.standardizedFileURL }

        model.replaceSelection(with: docsURL)
        #expect(model.selectedURLs == Set([docsURL]))
        #expect(model.focusedURL == docsURL)
        #expect(model.selectionAnchorURL == docsURL)

        model.toggleSelection(of: sourcesURL)
        #expect(model.selectedURLs == Set([docsURL, sourcesURL]))
        #expect(model.focusedURL == sourcesURL)
        #expect(model.selectionAnchorURL == docsURL)

        model.selectRange(to: sourcesURL, visibleURLs: visibleURLs)
        #expect(model.selectedURLs == Set(visibleURLs))
        #expect(model.focusedURL == sourcesURL)
        #expect(model.selectionAnchorURL == docsURL)
    }

    @Test("Deleting a selected subtree clears selection state for missing URLs")
    @MainActor
    func deletingSelectedSubtreeClearsSelectionState() async throws {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()
        let docsURL = fixture.rootURL.appendingPathComponent("Docs").standardizedFileURL

        await model.loadTree()
        model.replaceSelection(with: docsURL)

        await model.handleFileChange(.deleted, at: docsURL)

        #expect(model.selectedURLs.isEmpty)
        #expect(model.focusedURL == nil)
        #expect(model.selectionAnchorURL == nil)
    }

    @Test("Directory rename retargets selected URLs under the renamed subtree")
    @MainActor
    func directoryRenameRetargetsSelectedURLs() async throws {
        let fixture = FileTreeFixture()
        let model = fixture.makeModel()
        let sourcesURL = fixture.rootURL.appendingPathComponent("Sources").standardizedFileURL
        let engineURL = fixture.rootURL.appendingPathComponent("Engine").standardizedFileURL

        await model.loadTree()
        model.replaceSelection(with: sourcesURL)
        try await expandDirectory(named: "Sources", in: model)
        fixture.fileTreeService.renameRootDirectory(from: "Sources", to: "Engine")

        await model.handleFileChange(.renamed, at: engineURL)

        #expect(model.selectedURLs == Set([engineURL]))
        #expect(model.focusedURL == engineURL)
        #expect(model.selectionAnchorURL == engineURL)
    }

    @MainActor
    private func expandDirectory(named name: String, in model: FileTreeModel) async throws {
        let node = try #require(model.flattenedNodes.first(where: { $0.node.name == name })?.node)
        model.toggleExpansion(node)
        await settleAsyncTreeWork()
    }

    @MainActor
    private func settleAsyncTreeWork() async {
        try? await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor
private final class FileTreeFixture {
    let rootURL = URL(fileURLWithPath: "/devys-tests/tree-root").standardizedFileURL
    let fileTreeService: RecordingFileTreeService
    let watchServiceFactory = RecordingFileWatchServiceFactory()

    init() {
        self.fileTreeService = RecordingFileTreeService(rootURL: rootURL)
    }

    func makeModel() -> FileTreeModel {
        FileTreeModel(
            rootURL: rootURL,
            settings: AppSettings(),
            fileTreeService: fileTreeService,
            fileWatchServiceFactory: watchServiceFactory.make
        )
    }
}

@MainActor
private final class RecordingFileTreeService: FileTreeService {
    struct DirectoryListing {
        var directories: [String]
        var files: [String]
    }

    private let rootURL: URL
    private var listingsByDirectoryURL: [URL: DirectoryListing]
    private var loadChildrenCallCounts: [URL: Int] = [:]

    private(set) var buildTreeCallCount = 0

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.listingsByDirectoryURL = [
            self.rootURL: DirectoryListing(directories: ["Docs", "Sources"], files: []),
            self.rootURL.appendingPathComponent("Sources"): DirectoryListing(directories: [], files: ["App.swift"]),
            self.rootURL.appendingPathComponent("Docs"): DirectoryListing(directories: [], files: ["Guide.md"])
        ]
    }

    func buildTree(rootURL: URL, explorerSettings: ExplorerSettings) async -> CEWorkspaceFileNode {
        _ = explorerSettings
        buildTreeCallCount += 1

        let root = CEWorkspaceFileNode(url: rootURL, isDirectory: true)
        root.children = makeChildren(for: root)
        return root
    }

    func loadChildren(
        for node: CEWorkspaceFileNode,
        explorerSettings: ExplorerSettings
    ) async -> [CEWorkspaceFileNode] {
        _ = explorerSettings
        let normalizedURL = node.url.standardizedFileURL
        loadChildrenCallCounts[normalizedURL, default: 0] += 1
        return makeChildren(for: node)
    }

    func resetLoadChildrenCallCounts() {
        loadChildrenCallCounts.removeAll()
    }

    func loadChildrenCallCount(for directoryURL: URL) -> Int {
        loadChildrenCallCounts[directoryURL.standardizedFileURL, default: 0]
    }

    func renameRootDirectory(from oldName: String, to newName: String) {
        var rootListing = listingsByDirectoryURL[rootURL] ?? DirectoryListing(directories: [], files: [])
        rootListing.directories.removeAll { $0 == oldName }
        rootListing.directories.append(newName)
        rootListing.directories.sort()
        listingsByDirectoryURL[rootURL] = rootListing

        let oldURL = rootURL.appendingPathComponent(oldName).standardizedFileURL
        let newURL = rootURL.appendingPathComponent(newName).standardizedFileURL
        let existing = listingsByDirectoryURL.removeValue(forKey: oldURL)
        listingsByDirectoryURL[newURL] = existing ?? DirectoryListing(directories: [], files: [])
    }

    private func makeChildren(for parent: CEWorkspaceFileNode) -> [CEWorkspaceFileNode] {
        let normalizedURL = parent.url.standardizedFileURL
        let listing = listingsByDirectoryURL[normalizedURL] ?? DirectoryListing(directories: [], files: [])

        let directoryChildren = listing.directories.map { name in
            CEWorkspaceFileNode(
                url: normalizedURL.appendingPathComponent(name),
                isDirectory: true,
                parent: parent
            )
        }
        let fileChildren = listing.files.map { name in
            CEWorkspaceFileNode(
                url: normalizedURL.appendingPathComponent(name),
                isDirectory: false,
                parent: parent
            )
        }

        return (directoryChildren + fileChildren).sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private final class RecordingFileWatchServiceFactory {
    private(set) var services: [RecordingFileWatchService] = []

    func make(rootURL: URL) -> FileWatchService {
        let service = RecordingFileWatchService(rootURL: rootURL)
        services.append(service)
        return service
    }
}

private final class RecordingFileWatchService: FileWatchService, @unchecked Sendable {
    let rootURL: URL
    private let lock = NSLock()
    private var onFileChangeStorage: FileChangeHandler?
    private var startWatchingCallCountStorage = 0
    private var stopWatchingCallCountStorage = 0

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    var onFileChange: FileChangeHandler? {
        get {
            lock.withLock { onFileChangeStorage }
        }
        set {
            lock.withLock {
                onFileChangeStorage = newValue
            }
        }
    }

    var startWatchingCallCount: Int {
        lock.withLock { startWatchingCallCountStorage }
    }

    var stopWatchingCallCount: Int {
        lock.withLock { stopWatchingCallCountStorage }
    }

    func startWatching() {
        lock.withLock {
            startWatchingCallCountStorage += 1
        }
    }

    func stopWatching() {
        lock.withLock {
            stopWatchingCallCountStorage += 1
        }
    }

    func watchDirectory(_ url: URL) {
        _ = url
    }

    func unwatchDirectory(_ url: URL) {
        _ = url
    }

    func emit(_ changeType: FileChangeType, at url: URL) {
        let handler = lock.withLock { onFileChangeStorage }
        handler?(changeType, url)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
