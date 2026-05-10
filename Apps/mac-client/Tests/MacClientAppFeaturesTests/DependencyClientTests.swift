import ComposableArchitecture
import Diff
import Editor
import Git
@testable import MacClientAppFeatures
import XCTest

@MainActor
final class DependencyClientTests: XCTestCase {
    func testDependencyClientsCanBeReplaced() async throws {
        let projectURL = URL(fileURLWithPath: "/tmp/devys-project")
        let fileURL = projectURL.appendingPathComponent("README.md")
        let change = GitFileChange(path: "README.md", status: .modified, isStaged: false)
        let hunk = DiffHunk(
            id: "hunk",
            header: "@@ -1 +1 @@",
            lines: [],
            oldStart: 1,
            oldCount: 1,
            newStart: 1,
            newCount: 1
        )
        let recorder = DependencyClientRecorder()

        try await withDependencies {
            $0.alertClient = AlertClient { request in
                request.title == "Confirm"
            }
            $0.documentClient = DocumentClient(
                loadPreview: { url, request in
                    XCTAssertEqual(url, fileURL)
                    XCTAssertEqual(request.maxBytes, 128)
                    return LoadedDocumentPreview(
                        kind: .text("content"),
                        language: "markdown",
                        revision: DocumentPreviewRevision(fileSize: 7, contentModificationDate: nil),
                        exceededLimit: false,
                        maxBytes: request.maxBytes
                    )
                },
                save: { content, url in
                    XCTAssertEqual(content, "content")
                    XCTAssertEqual(url, fileURL)
                    await recorder.recordSavedDocumentURL(url)
                },
                revealInFinder: { url in
                    await recorder.recordRevealedURL(url)
                }
            )
            $0.fileTrashClient = FileTrashClient { url in
                await recorder.recordTrashURL(url)
            }
            $0.gitRepositoryClient = GitRepositoryClient(
                status: { repositoryURL in
                    XCTAssertEqual(repositoryURL, projectURL)
                    return [change]
                },
                diffSnapshot: { repositoryURL, fileChange in
                    XCTAssertEqual(repositoryURL, projectURL)
                    XCTAssertEqual(fileChange, change)
                    return .empty
                },
                stageFile: { _, _ in },
                unstageFile: { _, _ in },
                discardFile: { _, _ in },
                stageHunk: { _, _, _ in },
                unstageHunk: { _, _, _ in },
                discardHunk: { _, _, _ in }
            )
            $0.localPortsClient = LocalPortsClient { rootURL in
                XCTAssertEqual(rootURL, projectURL)
                return [
                    LocalPort(
                        port: 3000,
                        processID: 42,
                        processName: "node",
                        workingDirectory: rootURL
                    )
                ]
            }
            $0.openPanelClient = OpenPanelClient {
                projectURL
            }
            $0.pasteboardClient = PasteboardClient(
                readString: { "copied" },
                writeString: { value in
                    await recorder.recordPasteboardString(value)
                }
            )
            $0.projectFilesClient = ProjectFilesClient { request in
                XCTAssertEqual(request.rootURL, projectURL)
                return [
                    ProjectFileRow(url: fileURL, isDirectory: false, depth: 0)
                ]
            }
            $0.projectRootResolverClient = ProjectRootResolverClient { workingDirectory in
                XCTAssertEqual(workingDirectory, fileURL.deletingLastPathComponent())
                return projectURL
            }
            $0.recentProjectsClient = RecentProjectsClient(
                load: { [projectURL] },
                record: { url in
                    await recorder.recordRecentProject(url)
                }
            )
            $0.windowClient = WindowClient { request in
                await recorder.recordWindowRequest(request)
            }
        } operation: {
            @Dependency(\.alertClient) var alertClient
            @Dependency(\.documentClient) var documentClient
            @Dependency(\.fileTrashClient) var fileTrashClient
            @Dependency(\.gitRepositoryClient) var gitRepositoryClient
            @Dependency(\.localPortsClient) var localPortsClient
            @Dependency(\.openPanelClient) var openPanelClient
            @Dependency(\.pasteboardClient) var pasteboardClient
            @Dependency(\.projectFilesClient) var projectFilesClient
            @Dependency(\.projectRootResolverClient) var projectRootResolverClient
            @Dependency(\.recentProjectsClient) var recentProjectsClient
            @Dependency(\.windowClient) var windowClient

            let confirmed = await alertClient.confirm(
                AlertRequest(title: "Confirm", confirmTitle: "Continue")
            )
            XCTAssertTrue(confirmed)

            let preview = try await documentClient.loadPreview(
                fileURL,
                DocumentPreviewRequest(maxBytes: 128)
            )
            XCTAssertEqual(preview.content, "content")
            try await documentClient.save("content", fileURL)
            let savedDocumentURL = await recorder.savedDocumentURL
            XCTAssertEqual(savedDocumentURL, fileURL)
            await documentClient.revealInFinder(fileURL)
            let revealedURL = await recorder.revealedURL
            XCTAssertEqual(revealedURL, fileURL)

            try await fileTrashClient.moveToTrash(fileURL)
            let recordedTrashURL = await recorder.trashURL
            XCTAssertEqual(recordedTrashURL, fileURL)

            let status = try await gitRepositoryClient.status(projectURL)
            XCTAssertEqual(status, [change])
            let diffSnapshot = try await gitRepositoryClient.diffSnapshot(projectURL, change)
            XCTAssertEqual(diffSnapshot, .empty)
            try await gitRepositoryClient.stageFile(projectURL, change)
            try await gitRepositoryClient.unstageFile(projectURL, change)
            try await gitRepositoryClient.discardFile(projectURL, change)
            try await gitRepositoryClient.stageHunk(projectURL, hunk, change)
            try await gitRepositoryClient.unstageHunk(projectURL, hunk, change)
            try await gitRepositoryClient.discardHunk(projectURL, hunk, change)

            let detectedPorts = try await localPortsClient.detect(projectURL).map(\.port)
            XCTAssertEqual(detectedPorts, [3000])
            let selectedProjectURL = await openPanelClient.chooseProjectDirectory()
            XCTAssertEqual(selectedProjectURL, projectURL)

            let pasteboardString = await pasteboardClient.readString()
            XCTAssertEqual(pasteboardString, "copied")
            await pasteboardClient.writeString("written")
            let recordedPasteboardString = await recorder.pasteboardString
            XCTAssertEqual(recordedPasteboardString, "written")

            let fileRows = await projectFilesClient.loadRows(ProjectFilesRequest(rootURL: projectURL))
            XCTAssertEqual(fileRows, [ProjectFileRow(url: fileURL, isDirectory: false, depth: 0)])
            let resolvedRoot = await projectRootResolverClient.resolveCandidateProjectRoot(
                fileURL.deletingLastPathComponent()
            )
            XCTAssertEqual(resolvedRoot, projectURL)

            let recentProjects = await recentProjectsClient.load()
            XCTAssertEqual(recentProjects, [projectURL])
            await recentProjectsClient.record(projectURL)
            let recordedRecentProject = await recorder.recentProject
            XCTAssertEqual(recordedRecentProject, projectURL)

            let request = WindowOpenRequest(
                disposition: .currentWindowGroup,
                tabKind: .file(fileURL),
                projectRootURL: projectURL
            )
            await windowClient.open(request)
            let recordedWindowRequest = await recorder.windowRequest
            XCTAssertEqual(recordedWindowRequest, request)
        }
    }
}

private actor DependencyClientRecorder {
    private(set) var pasteboardString: String?
    private(set) var trashURL: URL?
    private(set) var windowRequest: WindowOpenRequest?
    private(set) var recentProject: URL?
    private(set) var savedDocumentURL: URL?
    private(set) var revealedURL: URL?

    func recordPasteboardString(_ value: String) {
        pasteboardString = value
    }

    func recordTrashURL(_ value: URL) {
        trashURL = value
    }

    func recordSavedDocumentURL(_ value: URL) {
        savedDocumentURL = value
    }

    func recordRevealedURL(_ value: URL) {
        revealedURL = value
    }

    func recordWindowRequest(_ value: WindowOpenRequest) {
        windowRequest = value
    }

    func recordRecentProject(_ value: URL) {
        recentProject = value
    }
}
