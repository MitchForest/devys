import ComposableArchitecture
import Git
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class ProjectDrawerFeatureTests: XCTestCase {
    func testTaskLoadsPinAndSectionStateForRoot() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: ProjectDrawerFeature.State()) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.projectDrawerPersistenceClient = ProjectDrawerPersistenceClient(
                loadPinned: { url in
                    XCTAssertEqual(url, rootURL)
                    return true
                },
                savePinned: { _, _ in },
                loadSections: { url in
                    XCTAssertEqual(url, rootURL)
                    return ProjectDrawerSectionState(changesExpanded: false, filesExpanded: true)
                },
                saveSections: { _, _ in }
            )
        }

        await store.send(.task(projectRootURL: rootURL)) {
            $0.projectRootURL = rootURL
            $0.isPinned = true
            $0.changesExpanded = false
            $0.filesExpanded = true
        }
    }

    func testTogglePinPersistsAndHidesTransientDrawer() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let recorder = ProjectDrawerPersistenceRecorder()
        let store = TestStore(
            initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)
        ) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.projectDrawerPersistenceClient = recorder.client
        }

        await store.send(.reveal) {
            $0.isTransientlyVisible = true
        }
        await store.send(.togglePin) {
            $0.isPinned = true
            $0.isTransientlyVisible = false
        }
        XCTAssertEqual(recorder.savedPinnedRootURL, rootURL)
        XCTAssertEqual(recorder.savedPinnedValue, true)
    }

    func testRevealAndHideAreIgnoredWhenPinned() async {
        let recorder = ProjectDrawerPersistenceRecorder()
        let store = TestStore(initialState: ProjectDrawerFeature.State()) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.projectDrawerPersistenceClient = recorder.client
        }

        await store.send(.reveal) {
            $0.isTransientlyVisible = true
        }
        await store.send(.hide) {
            $0.isTransientlyVisible = false
        }
        await store.send(.togglePin) {
            $0.isPinned = true
        }
        await store.send(.reveal)
        await store.send(.hide)
    }

    func testSectionTogglesPersist() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let recorder = ProjectDrawerPersistenceRecorder()
        let store = TestStore(
            initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)
        ) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.projectDrawerPersistenceClient = recorder.client
        }

        await store.send(.setChangesExpanded(false)) {
            $0.changesExpanded = false
        }
        XCTAssertEqual(recorder.savedSectionRootURL, rootURL)
        XCTAssertEqual(recorder.savedSectionState, ProjectDrawerSectionState(changesExpanded: false, filesExpanded: true))

        await store.send(.setFilesExpanded(false)) {
            $0.filesExpanded = false
        }
        XCTAssertEqual(recorder.savedSectionState, ProjectDrawerSectionState(changesExpanded: false, filesExpanded: false))
    }

    func testSearchAndRootChanges() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: ProjectDrawerFeature.State()) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.projectDrawerPersistenceClient = ProjectDrawerPersistenceClient(
                loadPinned: { _ in false },
                savePinned: { _, _ in },
                loadSections: { _ in ProjectDrawerSectionState() },
                saveSections: { _, _ in }
            )
        }

        await store.send(.searchQueryChanged(" README ")) {
            $0.searchQuery = " README "
        }
        XCTAssertEqual(store.state.trimmedSearchQuery, "README")
        await store.send(.clearSearch) {
            $0.searchQuery = ""
        }
        await store.send(.task(projectRootURL: rootURL)) {
            $0.projectRootURL = rootURL
        }
    }

    func testToggleDirectoryAndFileRows() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let fileURL = rootURL.appendingPathComponent("README.md")
        let row = ProjectFileRow(url: fileURL, isDirectory: false, depth: 0)
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        }

        await store.send(.toggleDirectory(rootURL)) {
            $0.expandedDirectoryPaths = [rootURL.path]
        }
        await store.send(.toggleDirectory(rootURL)) {
            $0.expandedDirectoryPaths = []
        }
        await store.send(.fileRowsLoadingChanged(true)) {
            $0.filesIsLoading = true
        }
        await store.send(.fileRowsLoaded([row])) {
            $0.fileRows = [row]
            $0.filesIsLoading = false
        }
    }

    func testGitLoadingStates() async {
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let store = TestStore(initialState: ProjectDrawerFeature.State()) {
            ProjectDrawerFeature()
        }

        await store.send(.gitRefreshStarted) {
            $0.gitIsLoading = true
        }
        await store.send(.gitStatusLoaded([change])) {
            $0.gitChanges = [change]
            $0.gitIsRepositoryAvailable = true
            $0.gitIsLoading = false
        }
        await store.send(.gitFailed("boom")) {
            $0.gitChanges = []
            $0.gitIsRepositoryAvailable = false
            $0.gitErrorMessage = "boom"
        }
        await store.send(.gitNotRepository) {
            $0.gitErrorMessage = nil
        }
    }

    func testGitRefreshSuccess() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.gitRepositoryClient = projectDrawerGitClient(status: { url in
                XCTAssertEqual(url, rootURL)
                return [change]
            })
        }

        await store.send(.gitRefreshRequested) {
            $0.gitIsLoading = true
        }
        await store.receive(.gitStatusLoaded([change])) {
            $0.gitChanges = [change]
            $0.gitIsRepositoryAvailable = true
            $0.gitIsLoading = false
        }
    }

    func testGitRefreshNotRepository() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.gitRepositoryClient = projectDrawerGitClient(status: { _ in
                throw GitError.notRepository
            })
        }

        await store.send(.gitRefreshRequested) {
            $0.gitIsLoading = true
        }
        await store.receive(.gitNotRepository) {
            $0.gitChanges = []
            $0.gitIsRepositoryAvailable = false
            $0.gitIsLoading = false
        }
    }

    func testGitRefreshFailure() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.gitRepositoryClient = projectDrawerGitClient(status: { _ in
                throw ProjectDrawerFeatureTestError.gitFailed
            })
        }

        await store.send(.gitRefreshRequested) {
            $0.gitIsLoading = true
        }
        await store.receive(.gitFailed("gitFailed")) {
            $0.gitChanges = []
            $0.gitIsRepositoryAvailable = false
            $0.gitIsLoading = false
            $0.gitErrorMessage = "gitFailed"
        }
    }

    func testGitStageFileRunsThroughDependencyAndRefreshes() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let recorder = ProjectDrawerGitRecorder()
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.gitRepositoryClient = projectDrawerGitClient(
                status: { _ in [change] },
                stageFile: { url, fileChange in
                    await recorder.record("stage", url: url, change: fileChange)
                }
            )
        }

        await store.send(.gitStageFileRequested(change)) {
            $0.gitActionIDs = [change.id]
        }
        await store.receive(.gitActionFinished(change.id)) {
            $0.gitActionIDs = []
        }
        await store.receive(.gitRefreshRequested) {
            $0.gitIsLoading = true
        }
        await store.receive(.gitStatusLoaded([change])) {
            $0.gitChanges = [change]
            $0.gitIsRepositoryAvailable = true
            $0.gitIsLoading = false
        }
        let actions = await recorder.recordedActions()
        XCTAssertEqual(actions, ["stage:README.md"])
    }

    func testGitUnstageFileRunsThroughDependencyAndRefreshes() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: true)
        let recorder = ProjectDrawerGitRecorder()
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.gitRepositoryClient = projectDrawerGitClient(
                status: { _ in [change] },
                unstageFile: { url, fileChange in
                    await recorder.record("unstage", url: url, change: fileChange)
                }
            )
        }

        await store.send(.gitUnstageFileRequested(change)) {
            $0.gitActionIDs = [change.id]
        }
        await store.receive(.gitActionFinished(change.id)) {
            $0.gitActionIDs = []
        }
        await store.receive(.gitRefreshRequested) {
            $0.gitIsLoading = true
        }
        await store.receive(.gitStatusLoaded([change])) {
            $0.gitChanges = [change]
            $0.gitIsRepositoryAvailable = true
            $0.gitIsLoading = false
        }
        let actions = await recorder.recordedActions()
        XCTAssertEqual(actions, ["unstage:README.md"])
    }

    func testGitDiscardCancelDoesNotRunDependency() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let recorder = ProjectDrawerGitRecorder()
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.alertClient = AlertClient { request in
                XCTAssertEqual(request.title, "Discard changes to README.md?")
                return false
            }
            $0.gitRepositoryClient = projectDrawerGitClient(
                discardFile: { url, fileChange in
                    await recorder.record("discard", url: url, change: fileChange)
                }
            )
        }

        await store.send(.gitDiscardFileRequested(change))
        await store.receive(.gitDiscardFileCancelled(change.id))
        let actions = await recorder.recordedActions()
        XCTAssertEqual(actions, [])
    }

    func testGitDiscardConfirmRunsThroughDependencyAndRefreshes() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let recorder = ProjectDrawerGitRecorder()
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.alertClient = AlertClient { request in
                XCTAssertEqual(request.title, "Discard changes to README.md?")
                return true
            }
            $0.gitRepositoryClient = projectDrawerGitClient(
                status: { _ in [] },
                discardFile: { url, fileChange in
                    await recorder.record("discard", url: url, change: fileChange)
                }
            )
        }

        await store.send(.gitDiscardFileRequested(change))
        await store.receive(.gitDiscardFileConfirmed(change)) {
            $0.gitActionIDs = [change.id]
        }
        await store.receive(.gitActionFinished(change.id)) {
            $0.gitActionIDs = []
        }
        await store.receive(.gitRefreshRequested) {
            $0.gitIsLoading = true
        }
        await store.receive(.gitStatusLoaded([])) {
            $0.gitChanges = []
            $0.gitIsRepositoryAvailable = true
            $0.gitIsLoading = false
        }
        let actions = await recorder.recordedActions()
        XCTAssertEqual(actions, ["discard:README.md"])
    }

    func testLocalPortsRefreshSuccess() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let port = LocalPort(
            port: 5173,
            processID: 42,
            processName: "node",
            workingDirectory: rootURL
        )
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.localPortsClient = LocalPortsClient { url in
                XCTAssertEqual(url, rootURL)
                return [port]
            }
        }

        await store.send(.localPortsRefreshRequested) {
            $0.localPortsIsLoading = true
        }
        await store.receive(.localPortsLoaded([port])) {
            $0.localPorts = [port]
            $0.localPortsIsLoading = false
        }
    }

    func testLocalPortsRefreshFailure() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.localPortsClient = LocalPortsClient { _ in
                throw ProjectDrawerFeatureTestError.localPortsFailed
            }
        }

        await store.send(.localPortsRefreshRequested) {
            $0.localPortsIsLoading = true
        }
        await store.receive(.localPortsFailed("localPortsFailed")) {
            $0.localPortsIsLoading = false
            $0.localPortsErrorMessage = "localPortsFailed"
        }
    }

    func testLocalPortsRefreshWithoutRootClearsState() async {
        let rootURL = URL(fileURLWithPath: "/tmp/devys")
        let store = TestStore(initialState: ProjectDrawerFeature.State(projectRootURL: rootURL)) {
            ProjectDrawerFeature()
        } withDependencies: {
            $0.projectDrawerPersistenceClient = ProjectDrawerPersistenceClient(
                loadPinned: { _ in false },
                savePinned: { _, _ in },
                loadSections: { _ in ProjectDrawerSectionState() },
                saveSections: { _, _ in }
            )
        }

        await store.send(.localPortsLoaded([
            LocalPort(port: 3000, processID: 42, processName: "node", workingDirectory: rootURL)
        ])) {
            $0.localPorts = [
                LocalPort(port: 3000, processID: 42, processName: "node", workingDirectory: rootURL)
            ]
        }
        await store.send(.task(projectRootURL: nil)) {
            $0.projectRootURL = nil
        }
        await store.send(.localPortsRefreshRequested) {
            $0.localPorts = []
        }
    }
}

private enum ProjectDrawerFeatureTestError: Error, LocalizedError {
    case localPortsFailed
    case gitFailed

    var errorDescription: String? {
        switch self {
        case .localPortsFailed:
            "localPortsFailed"
        case .gitFailed:
            "gitFailed"
        }
    }
}

private actor ProjectDrawerGitRecorder {
    private(set) var actions: [String] = []

    func record(_ action: String, url: URL, change: GitFileChange) {
        actions.append("\(action):\(change.path)")
    }

    func recordedActions() -> [String] {
        actions
    }
}

private func projectDrawerGitClient(
    status: @escaping @Sendable (URL) async throws -> [GitFileChange] = { _ in [] },
    stageFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void = { _, _ in },
    unstageFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void = { _, _ in },
    discardFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void = { _, _ in }
) -> GitRepositoryClient {
    GitRepositoryClient(
        status: status,
        diffSnapshot: { _, _ in .empty },
        stageFile: stageFile,
        unstageFile: unstageFile,
        discardFile: discardFile,
        stageHunk: { _, _, _ in },
        unstageHunk: { _, _, _ in },
        discardHunk: { _, _, _ in }
    )
}

private final class ProjectDrawerPersistenceRecorder: @unchecked Sendable {
    var savedPinnedRootURL: URL?
    var savedPinnedValue: Bool?
    var savedSectionRootURL: URL?
    var savedSectionState: ProjectDrawerSectionState?

    var client: ProjectDrawerPersistenceClient {
        ProjectDrawerPersistenceClient(
            loadPinned: { _ in false },
            savePinned: { [weak self] rootURL, isPinned in
                self?.savedPinnedRootURL = rootURL
                self?.savedPinnedValue = isPinned
            },
            loadSections: { _ in ProjectDrawerSectionState() },
            saveSections: { [weak self] rootURL, state in
                self?.savedSectionRootURL = rootURL
                self?.savedSectionState = state
            }
        )
    }
}
