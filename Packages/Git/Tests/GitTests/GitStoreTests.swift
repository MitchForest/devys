import Foundation
import Testing
import Workspace
@testable import Git

@Suite("Git Store Tests")
struct GitStoreTests {
    @Test("Refresh treats plain folders as a normal non-git project state")
    @MainActor
    func refreshTreatsPlainFoldersAsNormalState() async {
        let service = StubGitService(isRepositoryAvailable: false)
        let store = GitStore(
            projectFolder: URL(fileURLWithPath: "/tmp/devys/plain-project"),
            gitService: service,
            fileWatchServiceFactory: { _ in NoopFileWatchService() }
        )

        await store.refresh()

        #expect(store.isRepositoryAvailable == false)
        #expect(store.errorMessage == nil)
        #expect(store.allChanges.isEmpty)
        #expect(store.repoInfo == nil)
    }

    @Test("Initialize Git promotes a plain folder into an active Git project")
    @MainActor
    func initializeGitPromotesProjectCapabilities() async {
        let service = StubGitService(
            isRepositoryAvailable: false,
            status: [],
            repositoryInfo: GitRepositoryInfo(currentBranch: "main")
        )
        let store = GitStore(
            projectFolder: URL(fileURLWithPath: "/tmp/devys/init-project"),
            gitService: service,
            fileWatchServiceFactory: { _ in NoopFileWatchService() }
        )

        await store.initializeRepository()

        #expect(service.initializeCallCount == 1)
        #expect(store.isRepositoryAvailable)
        #expect(store.errorMessage == nil)
        #expect(store.repoInfo?.currentBranch == "main")
    }

    @Test("Git store refreshes changes from external repository metadata events")
    @MainActor
    func refreshesOnExternalMetadataChange() async throws {
        let fixture = try PseudoRepositoryFixture()
        defer { fixture.cleanup() }

        let watcher = StubGitRepositoryMetadataWatcher()
        let service = StubGitService(
            isRepositoryAvailable: true,
            status: [GitFileChange(path: "Tracked.swift", status: .modified, isStaged: false)],
            repositoryInfo: GitRepositoryInfo(currentBranch: "main")
        )
        let store = GitStore(
            projectFolder: fixture.repositoryRoot,
            gitService: service,
            fileWatchServiceFactory: { _ in NoopFileWatchService() },
            metadataWatcherFactory: { _ in watcher },
            refreshDebounceNanoseconds: 1_000_000
        )

        await store.refresh()
        store.startWatching()

        service.statusResult = []
        try fixture.writeIndex(Data("updated-index".utf8))
        watcher.emit(.indexChanged)
        await waitUntil("metadata refresh clears changes") {
            store.allChanges.isEmpty
        }

        #expect(store.allChanges.isEmpty)
        #expect(service.repositoryAvailabilityCheckCount == 1)
    }

    @Test("Git store refreshes branch info from external HEAD changes")
    @MainActor
    func refreshesBranchInfoOnExternalHeadChange() async throws {
        let fixture = try PseudoRepositoryFixture()
        defer { fixture.cleanup() }

        let watcher = StubGitRepositoryMetadataWatcher()
        let service = StubGitService(
            isRepositoryAvailable: true,
            status: [],
            repositoryInfo: GitRepositoryInfo(currentBranch: "main")
        )
        let store = GitStore(
            projectFolder: fixture.repositoryRoot,
            gitService: service,
            fileWatchServiceFactory: { _ in NoopFileWatchService() },
            metadataWatcherFactory: { _ in watcher },
            refreshDebounceNanoseconds: 1_000_000
        )

        await store.refresh()
        store.startWatching()

        service.repositoryInfoResult = GitRepositoryInfo(currentBranch: "feature/external")
        try fixture.setHead(reference: "refs/heads/feature/external", commit: "2222222")
        watcher.emit(.headChanged)
        await waitUntil("metadata refresh updates branch info") {
            store.repoInfo?.currentBranch == "feature/external"
        }

        #expect(store.repoInfo?.currentBranch == "feature/external")
    }

    @Test("Git store clears stale selected file state after external commit")
    @MainActor
    func clearsSelectedFileStateAfterExternalCommit() async throws {
        let fixture = try PseudoRepositoryFixture()
        defer { fixture.cleanup() }

        let watcher = StubGitRepositoryMetadataWatcher()
        let service = StubGitService(
            isRepositoryAvailable: true,
            status: [GitFileChange(path: "Tracked.swift", status: .modified, isStaged: false)],
            repositoryInfo: GitRepositoryInfo(currentBranch: "main")
        )
        let store = GitStore(
            projectFolder: fixture.repositoryRoot,
            gitService: service,
            fileWatchServiceFactory: { _ in NoopFileWatchService() },
            metadataWatcherFactory: { _ in watcher },
            refreshDebounceNanoseconds: 1_000_000
        )

        await store.refresh()
        await store.selectFile("Tracked.swift", isStaged: false)
        store.startWatching()

        service.statusResult = []
        try fixture.writeIndex(Data("committed-index".utf8))
        watcher.emit(.indexChanged)
        await waitUntil("metadata refresh clears stale selected file state") {
            store.selectedFilePath == nil
        }

        #expect(store.selectedFilePath == nil)
        #expect(store.selectedDiff == nil)
    }

    @Test("Git store ignores unchanged metadata events")
    @MainActor
    func ignoresUnchangedMetadataEvents() async throws {
        let fixture = try PseudoRepositoryFixture()
        defer { fixture.cleanup() }

        let watcher = StubGitRepositoryMetadataWatcher()
        let service = StubGitService(
            isRepositoryAvailable: true,
            status: [],
            repositoryInfo: GitRepositoryInfo(currentBranch: "main")
        )
        let store = GitStore(
            projectFolder: fixture.repositoryRoot,
            gitService: service,
            fileWatchServiceFactory: { _ in NoopFileWatchService() },
            metadataWatcherFactory: { _ in watcher },
            refreshDebounceNanoseconds: 1_000_000
        )

        await store.refresh()
        store.startWatching()

        watcher.emit(.indexChanged)
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(service.statusCallCount == 1)
        #expect(service.repositoryAvailabilityCheckCount == 1)
        #expect(store.isRepositoryAvailable)
    }
}

@MainActor
private final class StubGitService: GitService {
    private(set) var initializeCallCount = 0
    private(set) var repositoryAvailabilityCheckCount = 0
    private(set) var statusCallCount = 0
    private var repositoryAvailable: Bool
    var statusResult: [GitFileChange]
    var repositoryInfoResult: GitRepositoryInfo

    var hasPRClient: Bool = false

    init(
        isRepositoryAvailable: Bool,
        status: [GitFileChange] = [],
        repositoryInfo: GitRepositoryInfo = GitRepositoryInfo(currentBranch: nil)
    ) {
        self.repositoryAvailable = isRepositoryAvailable
        self.statusResult = status
        self.repositoryInfoResult = repositoryInfo
    }

    func isRepositoryAvailable() async -> Bool {
        repositoryAvailabilityCheckCount += 1
        return repositoryAvailable
    }

    func initializeRepository() async throws {
        initializeCallCount += 1
        repositoryAvailable = true
    }

    func status() async throws -> [GitFileChange] {
        statusCallCount += 1
        return statusResult
    }

    func statusIncludingIgnored() async throws -> [GitFileChange] {
        statusResult
    }

    func repositoryInfo() async throws -> GitRepositoryInfo {
        repositoryInfoResult
    }

    func diff(
        for path: String,
        staged: Bool,
        contextLines: Int,
        ignoreWhitespace: Bool
    ) async throws -> String {
        _ = path
        _ = staged
        _ = contextLines
        _ = ignoreWhitespace
        return ""
    }

    func diffSnapshot(
        for path: String,
        staged: Bool,
        contextLines: Int,
        ignoreWhitespace: Bool
    ) async throws -> DiffSnapshot {
        _ = path
        _ = staged
        _ = contextLines
        _ = ignoreWhitespace
        return DiffSnapshot(from: ParsedDiff(hunks: [], isBinary: false, oldPath: nil, newPath: nil))
    }

    func stage(_ path: String) async throws {
        _ = path
    }

    func unstage(_ path: String) async throws {
        _ = path
    }

    func stageAll() async throws {}
    func unstageAll() async throws {}

    func stageHunk(_ hunk: DiffHunk, for path: String) async throws {
        _ = hunk
        _ = path
    }

    func unstageHunk(_ hunk: DiffHunk, for path: String) async throws {
        _ = hunk
        _ = path
    }

    func discard(_ path: String) async throws {
        _ = path
    }

    func discardUntracked(_ path: String) async throws {
        _ = path
    }

    func discardHunk(_ hunk: DiffHunk, for path: String) async throws {
        _ = hunk
        _ = path
    }

    func commit(message: String) async throws -> String {
        _ = message
        return "commit"
    }

    func fetch() async throws {}
    func push() async throws {}
    func pull() async throws {}

    func branches() async throws -> [GitBranch] {
        []
    }

    func checkout(branch: String) async throws {
        _ = branch
    }

    func createBranch(name: String) async throws {
        _ = name
    }

    func deleteBranch(name: String, force: Bool) async throws {
        _ = name
        _ = force
    }

    func log(count: Int) async throws -> [GitCommit] {
        _ = count
        return []
    }

    func show(commit: String) async throws -> String {
        _ = commit
        return ""
    }

    func isPRAvailable() async -> Bool {
        false
    }

    func listPRs(state: PRStateFilter) async throws -> [PullRequest] {
        _ = state
        return []
    }

    func getPRFiles(number: Int) async throws -> [PRFile] {
        _ = number
        return []
    }

    func checkoutPR(number: Int) async throws {
        _ = number
    }

    func createPR(title: String, body: String, base: String, draft: Bool) async throws -> Int {
        _ = title
        _ = body
        _ = base
        _ = draft
        return 0
    }

    func mergePR(number: Int, method: MergeMethod) async throws {
        _ = number
        _ = method
    }

    func prURL(number: Int) async -> URL? {
        _ = number
        return nil
    }
}

private final class StubGitRepositoryMetadataWatcher: GitRepositoryMetadataWatcher, @unchecked Sendable {
    var onChange: (@Sendable (GitRepositoryMetadataEvent) -> Void)?

    func startWatching() {}
    func stopWatching() {}

    func emit(_ event: GitRepositoryMetadataEvent) {
        onChange?(event)
    }
}

private struct PseudoRepositoryFixture {
    let repositoryRoot: URL
    let gitDirectory: URL

    init() throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-store-\(UUID().uuidString)")
        gitDirectory = repositoryRoot.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: gitDirectory.appendingPathComponent("refs/heads"),
            withIntermediateDirectories: true
        )
        try "ref: refs/heads/main\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "1111111\n".write(
            to: gitDirectory.appendingPathComponent("refs/heads/main"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: gitDirectory.appendingPathComponent("index"))
    }

    func writeIndex(_ data: Data) throws {
        try data.write(to: gitDirectory.appendingPathComponent("index"))
    }

    func setHead(reference: String, commit: String) throws {
        let referenceURL = gitDirectory.appendingPathComponent(reference)
        try FileManager.default.createDirectory(
            at: referenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "ref: \(reference)\n".write(
            to: gitDirectory.appendingPathComponent("HEAD"),
            atomically: true,
            encoding: .utf8
        )
        try "\(commit)\n".write(
            to: referenceURL,
            atomically: true,
            encoding: .utf8
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }
}

private final class NoopFileWatchService: FileWatchService, @unchecked Sendable {
    var onFileChange: FileChangeHandler?

    func startWatching() {}
    func stopWatching() {}
    func watchDirectory(_ url: URL) { _ = url }
    func unwatchDirectory(_ url: URL) { _ = url }
}

@MainActor
private func waitUntil(
    _ description: String,
    timeoutNanoseconds: UInt64 = 5_000_000_000,
    stepNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: stepNanoseconds)
    }

    Issue.record("Timed out waiting for \(description)")
}
