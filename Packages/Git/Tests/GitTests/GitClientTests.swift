import Diff
@testable import Git
import XCTest

final class GitClientTests: XCTestCase {
    func testStatusParserSplitsStagedAndUnstagedEntriesForSameFile() {
        let changes = GitStatusParser.parse("MM Sources/App.swift\n?? README.md\nR  Old.swift -> New.swift\n")

        XCTAssertEqual(changes.count, 4)
        XCTAssertTrue(changes.contains(GitFileChange(path: "Sources/App.swift", status: .modified, isStaged: true)))
        XCTAssertTrue(changes.contains(GitFileChange(path: "Sources/App.swift", status: .modified, isStaged: false)))
        XCTAssertTrue(changes.contains(GitFileChange(path: "README.md", status: .untracked, isStaged: false)))
        XCTAssertTrue(changes.contains(GitFileChange(
            path: "New.swift",
            previousPath: "Old.swift",
            status: .renamed,
            isStaged: true
        )))
    }

    func testStageAndUnstageFileMoveChangeBetweenStatusBuckets() async throws {
        let fixture = try GitRepositoryFixture()
        try fixture.write("one\n", to: "tracked.txt")
        try fixture.runGit(["add", "tracked.txt"])
        try fixture.runGit(["commit", "-m", "initial"])
        try fixture.write("two\n", to: "tracked.txt")

        let client = GitClient(repositoryURL: fixture.repositoryURL)
        let unstaged = try await client.status().singleChange(path: "tracked.txt", isStaged: false)
        try await client.stageFile(unstaged)

        let stagedStatus = try await client.status()
        XCTAssertNotNil(try stagedStatus.singleChange(path: "tracked.txt", isStaged: true))
        XCTAssertNil(try stagedStatus.optionalChange(path: "tracked.txt", isStaged: false))

        let staged = try stagedStatus.singleChange(path: "tracked.txt", isStaged: true)
        try await client.unstageFile(staged)

        let unstagedStatus = try await client.status()
        XCTAssertNil(try unstagedStatus.optionalChange(path: "tracked.txt", isStaged: true))
        XCTAssertNotNil(try unstagedStatus.singleChange(path: "tracked.txt", isStaged: false))
    }

    func testDiscardTrackedFileMovesCurrentFileThroughDiscarderAndRestoresContent() async throws {
        let fixture = try GitRepositoryFixture()
        try fixture.write("original\n", to: "tracked.txt")
        try fixture.runGit(["add", "tracked.txt"])
        try fixture.runGit(["commit", "-m", "initial"])
        try fixture.write("changed\n", to: "tracked.txt")
        let trash = try TrashRecorder()
        let client = GitClient(repositoryURL: fixture.repositoryURL, fileDiscarder: trash.discarder)

        let change = try await client.status().singleChange(path: "tracked.txt", isStaged: false)
        try await client.discardFile(change)

        XCTAssertEqual(try fixture.read("tracked.txt"), "original\n")
        let discardedFilenames = await trash.discardedFilenames()
        XCTAssertEqual(discardedFilenames, ["tracked.txt"])
        let status = try await client.status()
        XCTAssertTrue(status.isEmpty)
    }

    func testDiscardUntrackedFileMovesItThroughDiscarder() async throws {
        let fixture = try GitRepositoryFixture()
        try fixture.write("scratch\n", to: "scratch.txt")
        let trash = try TrashRecorder()
        let client = GitClient(repositoryURL: fixture.repositoryURL, fileDiscarder: trash.discarder)

        let change = try await client.status().singleChange(path: "scratch.txt", isStaged: false)
        try await client.discardFile(change)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url("scratch.txt").path))
        let discardedFilenames = await trash.discardedFilenames()
        XCTAssertEqual(discardedFilenames, ["scratch.txt"])
        let status = try await client.status()
        XCTAssertTrue(status.isEmpty)
    }

    func testStageAndUnstageSingleHunk() async throws {
        let fixture = try GitRepositoryFixture()
        try fixture.write("one\nmiddle\ntwo\n", to: "tracked.txt")
        try fixture.runGit(["add", "tracked.txt"])
        try fixture.runGit(["commit", "-m", "initial"])
        try fixture.write("ONE\nmiddle\nTWO\n", to: "tracked.txt")
        let client = GitClient(repositoryURL: fixture.repositoryURL)

        let change = try await client.status().singleChange(path: "tracked.txt", isStaged: false)
        let snapshot = try await client.diffSnapshot(for: change, contextLines: 0, ignoreWhitespace: false)
        XCTAssertGreaterThanOrEqual(snapshot.hunks.count, 2)

        try await client.stageHunk(snapshot.hunks[0], for: change)
        let partiallyStaged = try await client.status()
        XCTAssertNotNil(try partiallyStaged.singleChange(path: "tracked.txt", isStaged: true))
        XCTAssertNotNil(try partiallyStaged.singleChange(path: "tracked.txt", isStaged: false))

        let stagedChange = try partiallyStaged.singleChange(path: "tracked.txt", isStaged: true)
        let stagedSnapshot = try await client.diffSnapshot(for: stagedChange, contextLines: 0, ignoreWhitespace: false)
        try await client.unstageHunk(stagedSnapshot.hunks[0], for: stagedChange)

        let unstagedStatus = try await client.status()
        XCTAssertNil(try unstagedStatus.optionalChange(path: "tracked.txt", isStaged: true))
        XCTAssertNotNil(try unstagedStatus.singleChange(path: "tracked.txt", isStaged: false))
    }

    func testDiscardSingleUnstagedHunkRestoresOnlyThatHunk() async throws {
        let fixture = try GitRepositoryFixture()
        try fixture.write("one\nmiddle\ntwo\n", to: "tracked.txt")
        try fixture.runGit(["add", "tracked.txt"])
        try fixture.runGit(["commit", "-m", "initial"])
        try fixture.write("ONE\nmiddle\nTWO\n", to: "tracked.txt")
        let trash = try TrashRecorder()
        let client = GitClient(repositoryURL: fixture.repositoryURL, fileDiscarder: trash.discarder)

        let change = try await client.status().singleChange(path: "tracked.txt", isStaged: false)
        let snapshot = try await client.diffSnapshot(for: change, contextLines: 0, ignoreWhitespace: false)
        XCTAssertGreaterThanOrEqual(snapshot.hunks.count, 2)
        try await client.discardHunk(snapshot.hunks[0], for: change)

        let content = try fixture.read("tracked.txt")
        XCTAssertTrue(content == "one\nmiddle\nTWO\n" || content == "ONE\nmiddle\ntwo\n")
        let discardedFilenames = await trash.discardedFilenames()
        XCTAssertEqual(discardedFilenames, ["tracked.txt"])
    }
}

private final class GitRepositoryFixture {
    let repositoryURL: URL

    init() throws {
        repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init"])
        try runGit(["config", "user.email", "devys@example.com"])
        try runGit(["config", "user.name", "Devys Tests"])
    }

    func url(_ path: String) -> URL {
        repositoryURL.appendingPathComponent(path)
    }

    func write(_ content: String, to path: String) throws {
        let url = url(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryURL
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw XCTSkip("git \(arguments.joined(separator: " ")) failed: \(error)")
        }
    }
}

private actor TrashRecorder {
    private let trashURL: URL
    private var filenames: [String] = []

    nonisolated var discarder: GitFileDiscarder {
        GitFileDiscarder { [self] url in
            try await discard(url)
        }
    }

    init() throws {
        trashURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-trash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trashURL, withIntermediateDirectories: true)
    }

    func discard(_ url: URL) throws {
        let destination = trashURL.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
        filenames.append(url.lastPathComponent)
    }

    func discardedFilenames() -> [String] {
        filenames
    }
}

private extension Array where Element == GitFileChange {
    func optionalChange(path: String, isStaged: Bool) throws -> GitFileChange? {
        first { $0.path == path && $0.isStaged == isStaged }
    }

    func singleChange(path: String, isStaged: Bool) throws -> GitFileChange {
        let matches = filter { $0.path == path && $0.isStaged == isStaged }
        XCTAssertEqual(matches.count, 1)
        guard let match = matches.first else {
            throw GitError.commandFailed(message: "Expected one change for \(path)")
        }
        return match
    }
}
