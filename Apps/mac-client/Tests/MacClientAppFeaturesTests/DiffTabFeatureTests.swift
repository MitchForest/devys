import ComposableArchitecture
import Diff
import Git
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class DiffTabFeatureTests: XCTestCase {
    func testTaskLoadsPersistedModeAndDiffSnapshot() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "Sources/App.swift", status: .modified, isStaged: false)
        let snapshot = diffSnapshot()
        let store = TestStore(initialState: DiffTabFeature.State(change: change, projectRootURL: rootURL)) {
            DiffTabFeature()
        } withDependencies: {
            $0.diffModePersistenceClient = DiffModePersistenceClient(loadMode: { .split }, saveMode: { _ in })
            $0.gitRepositoryClient = diffGitClient(diffSnapshot: { url, requestedChange in
                XCTAssertEqual(url, rootURL)
                XCTAssertEqual(requestedChange, change)
                return snapshot
            })
        }

        await store.send(.task) {
            $0.mode = .split
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(snapshot)) {
            $0.diffSnapshot = snapshot
            $0.isLoading = false
        }
    }

    func testLoadDiffFailureStoresError() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let store = TestStore(initialState: DiffTabFeature.State(change: change, projectRootURL: rootURL)) {
            DiffTabFeature()
        } withDependencies: {
            $0.gitRepositoryClient = diffGitClient(diffSnapshot: { _, _ in
                throw DiffTabFeatureTestError.failed
            })
        }

        await store.send(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffFailed("failed")) {
            $0.diffSnapshot = nil
            $0.isLoading = false
            $0.errorMessage = "failed"
        }
    }

    func testModeChangePersistsThroughDependency() async {
        let recorder = DiffTabRecorder()
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let store = TestStore(initialState: DiffTabFeature.State(change: change)) {
            DiffTabFeature()
        } withDependencies: {
            $0.diffModePersistenceClient = DiffModePersistenceClient(
                loadMode: { .unified },
                saveMode: { mode in recorder.savedModes.append(mode) }
            )
        }

        await store.send(.modeChanged(.split)) {
            $0.mode = .split
        }
        XCTAssertEqual(recorder.savedModes, [.split])
    }

    func testStageFileRunsThroughGitClientAndRefreshesDiff() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "Sources/App.swift", status: .modified, isStaged: false)
        let snapshot = diffSnapshot()
        let recorder = DiffTabActionRecorder()
        let store = TestStore(initialState: DiffTabFeature.State(change: change, projectRootURL: rootURL)) {
            DiffTabFeature()
        } withDependencies: {
            $0.gitRepositoryClient = diffGitClient(
                diffSnapshot: { _, _ in snapshot },
                stageFile: { url, fileChange in
                    await recorder.record("stage-file:\(url.path):\(fileChange.path)")
                }
            )
        }

        await store.send(.fileActionRequested(.stage)) {
            $0.isGitActionRunning = true
        }
        await store.receive(.fileActionSucceeded(.stage)) {
            $0.isGitActionRunning = false
            $0.gitRefreshCount = 1
            $0.change = GitFileChange(path: change.path, status: change.status, isStaged: true)
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(snapshot)) {
            $0.diffSnapshot = snapshot
            $0.isLoading = false
        }
        let actions = await recorder.actions()
        XCTAssertEqual(actions, ["stage-file:\(rootURL.path):Sources/App.swift"])
    }

    func testUnstageFileRunsThroughGitClientAndRefreshesDiff() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "Sources/App.swift", status: .modified, isStaged: true)
        let snapshot = diffSnapshot()
        let store = TestStore(initialState: DiffTabFeature.State(change: change, projectRootURL: rootURL)) {
            DiffTabFeature()
        } withDependencies: {
            $0.gitRepositoryClient = diffGitClient(diffSnapshot: { _, _ in snapshot })
        }

        await store.send(.fileActionRequested(.unstage)) {
            $0.isGitActionRunning = true
        }
        await store.receive(.fileActionSucceeded(.unstage)) {
            $0.isGitActionRunning = false
            $0.gitRefreshCount = 1
            $0.change = GitFileChange(path: change.path, status: change.status, isStaged: false)
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(snapshot)) {
            $0.diffSnapshot = snapshot
            $0.isLoading = false
        }
    }

    func testDiscardFileCancelDoesNotRunGitAction() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let store = TestStore(initialState: DiffTabFeature.State(change: change, projectRootURL: rootURL)) {
            DiffTabFeature()
        } withDependencies: {
            $0.alertClient = AlertClient(confirm: { _ in false })
            $0.gitRepositoryClient = diffGitClient(discardFile: { _, _ in
                XCTFail("discardFile should not run when confirmation is cancelled")
            })
        }

        await store.send(.fileActionRequested(.discard))
        await store.receive(.fileDiscardCancelled)
    }

    func testDiscardFileConfirmRunsGitActionAndRefreshesDiff() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let snapshot = diffSnapshot()
        let recorder = DiffTabActionRecorder()
        let store = TestStore(initialState: DiffTabFeature.State(change: change, projectRootURL: rootURL)) {
            DiffTabFeature()
        } withDependencies: {
            $0.alertClient = AlertClient(confirm: { _ in true })
            $0.gitRepositoryClient = diffGitClient(
                diffSnapshot: { _, _ in snapshot },
                discardFile: { _, fileChange in
                    await recorder.record("discard-file:\(fileChange.path)")
                }
            )
        }

        await store.send(.fileActionRequested(.discard))
        await store.receive(.fileDiscardConfirmed) {
            $0.isGitActionRunning = true
        }
        await store.receive(.fileActionSucceeded(.discard)) {
            $0.isGitActionRunning = false
            $0.gitRefreshCount = 1
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(snapshot)) {
            $0.diffSnapshot = snapshot
            $0.isLoading = false
        }
        let actions = await recorder.actions()
        XCTAssertEqual(actions, ["discard-file:README.md"])
    }

    func testStageAndUnstageHunkRunThroughGitClient() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let snapshot = diffSnapshot()
        let refreshedSnapshot = DiffSnapshot.empty
        let recorder = DiffTabActionRecorder()
        var initialState = DiffTabFeature.State(change: change, projectRootURL: rootURL)
        initialState.diffSnapshot = snapshot
        let store = TestStore(initialState: initialState) {
            DiffTabFeature()
        } withDependencies: {
            $0.gitRepositoryClient = diffGitClient(
                diffSnapshot: { _, _ in refreshedSnapshot },
                stageHunk: { _, hunk, _ in
                    await recorder.record("stage-hunk:\(hunk.id)")
                },
                unstageHunk: { _, hunk, _ in
                    await recorder.record("unstage-hunk:\(hunk.id)")
                }
            )
        }

        await store.send(.hunkActionRequested(.stage, hunkIndex: 0)) {
            $0.isGitActionRunning = true
        }
        await store.receive(.hunkActionSucceeded(.stage)) {
            $0.isGitActionRunning = false
            $0.gitRefreshCount = 1
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(refreshedSnapshot)) {
            $0.diffSnapshot = refreshedSnapshot
            $0.isLoading = false
        }
        await store.send(.diffLoaded(snapshot)) {
            $0.diffSnapshot = snapshot
        }
        await store.send(.hunkActionRequested(.unstage, hunkIndex: 0)) {
            $0.isGitActionRunning = true
        }
        await store.receive(.hunkActionSucceeded(.unstage)) {
            $0.isGitActionRunning = false
            $0.gitRefreshCount = 2
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(refreshedSnapshot)) {
            $0.diffSnapshot = refreshedSnapshot
            $0.isLoading = false
        }
        let actions = await recorder.actions()
        XCTAssertEqual(actions, ["stage-hunk:hunk-1", "unstage-hunk:hunk-1"])
    }

    func testDiscardHunkCancelAndConfirm() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let snapshot = diffSnapshot()
        let recorder = DiffTabActionRecorder()
        let confirmations = DiffTabConfirmations([false, true])
        var initialState = DiffTabFeature.State(change: change, projectRootURL: rootURL)
        initialState.diffSnapshot = snapshot
        let store = TestStore(initialState: initialState) {
            DiffTabFeature()
        } withDependencies: {
            $0.alertClient = AlertClient(confirm: { _ in await confirmations.next() })
            $0.gitRepositoryClient = diffGitClient(
                diffSnapshot: { _, _ in snapshot },
                discardHunk: { _, hunk, _ in
                    await recorder.record("discard-hunk:\(hunk.id)")
                }
            )
        }

        await store.send(.hunkActionRequested(.discard, hunkIndex: 0))
        await store.receive(.hunkDiscardCancelled)
        await store.send(.hunkActionRequested(.discard, hunkIndex: 0))
        await store.receive(.hunkDiscardConfirmed(0)) {
            $0.isGitActionRunning = true
        }
        await store.receive(.hunkActionSucceeded(.discard)) {
            $0.isGitActionRunning = false
            $0.gitRefreshCount = 1
        }
        await store.receive(.loadDiffRequested) {
            $0.isLoading = true
        }
        await store.receive(.diffLoaded(snapshot)) {
            $0.diffSnapshot = snapshot
            $0.isLoading = false
        }
        let actions = await recorder.actions()
        XCTAssertEqual(actions, ["discard-hunk:hunk-1"])
    }

    func testCopyPathUsesPasteboardClient() async {
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let recorder = DiffTabActionRecorder()
        let store = TestStore(initialState: DiffTabFeature.State(change: change)) {
            DiffTabFeature()
        } withDependencies: {
            $0.pasteboardClient = PasteboardClient(
                readString: { nil },
                writeString: { value in await recorder.record("copy:\(value)") }
            )
        }

        await store.send(.copyPathRequested)
        await store.receive(.copyPathFinished)
        let actions = await recorder.actions()
        XCTAssertEqual(actions, ["copy:README.md"])
    }
}

private func diffSnapshot() -> DiffSnapshot {
    DiffSnapshot(
        from: ParsedDiff(
            hunks: [
                DiffHunk(
                    id: "hunk-1",
                    header: "@@ -1 +1 @@",
                    lines: [
                        DiffLine(id: "line-1", type: .removed, content: "old", oldLineNumber: 1, newLineNumber: nil),
                        DiffLine(id: "line-2", type: .added, content: "new", oldLineNumber: nil, newLineNumber: 1)
                    ],
                    oldStart: 1,
                    oldCount: 1,
                    newStart: 1,
                    newCount: 1
                )
            ],
            oldPath: "README.md",
            newPath: "README.md"
        )
    )
}

private func diffGitClient(
    diffSnapshot: @escaping @Sendable (URL, GitFileChange) async throws -> DiffSnapshot = { _, _ in .empty },
    stageFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void = { _, _ in },
    unstageFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void = { _, _ in },
    discardFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void = { _, _ in },
    stageHunk: @escaping @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void = { _, _, _ in },
    unstageHunk: @escaping @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void = { _, _, _ in },
    discardHunk: @escaping @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void = { _, _, _ in }
) -> GitRepositoryClient {
    GitRepositoryClient(
        status: { _ in [] },
        diffSnapshot: diffSnapshot,
        stageFile: stageFile,
        unstageFile: unstageFile,
        discardFile: discardFile,
        stageHunk: stageHunk,
        unstageHunk: unstageHunk,
        discardHunk: discardHunk
    )
}

private enum DiffTabFeatureTestError: Error, LocalizedError {
    case failed

    var errorDescription: String? {
        "failed"
    }
}

private final class DiffTabRecorder: @unchecked Sendable {
    var savedModes: [DiffViewMode] = []
}

private actor DiffTabActionRecorder {
    private var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }

    func actions() -> [String] {
        values
    }
}

private actor DiffTabConfirmations {
    private var values: [Bool]

    init(_ values: [Bool]) {
        self.values = values
    }

    func next() -> Bool {
        values.removeFirst()
    }
}
