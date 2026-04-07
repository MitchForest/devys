import Foundation
import Testing
@testable import Git

struct GitClientStatusTests {
    @Test("Git status excludes ignored files on the default path")
    func statusExcludesIgnoredFilesByDefault() async throws {
        let fixture = try TestStatusRepositoryFixture()
        defer { fixture.cleanup() }

        try ".build/\n".write(
            to: fixture.repositoryRoot.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try "notes\n".write(
            to: fixture.repositoryRoot.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let ignoredDirectory = fixture.repositoryRoot.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try "artifact\n".write(
            to: ignoredDirectory.appendingPathComponent("output.txt"),
            atomically: true,
            encoding: .utf8
        )

        let client = GitClient(repositoryURL: fixture.repositoryRoot)
        let changes = try await client.status()

        #expect(changes.contains { $0.path == "notes.txt" && $0.status == .untracked })
        #expect(changes.contains { $0.path == ".gitignore" && $0.status == .untracked })
        #expect(!changes.contains { $0.path == ".build/output.txt" && $0.status == .ignored })
    }

    @Test("Git ignored-file expansion is only available through an explicit API")
    func statusIncludingIgnoredFiles() async throws {
        let fixture = try TestStatusRepositoryFixture()
        defer { fixture.cleanup() }

        try ".build/\n".write(
            to: fixture.repositoryRoot.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try "notes\n".write(
            to: fixture.repositoryRoot.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let ignoredDirectory = fixture.repositoryRoot.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try "artifact\n".write(
            to: ignoredDirectory.appendingPathComponent("output.txt"),
            atomically: true,
            encoding: .utf8
        )

        let client = GitClient(repositoryURL: fixture.repositoryRoot)
        let changes = try await client.statusIncludingIgnored()

        #expect(changes.contains { $0.path == "notes.txt" && $0.status == .untracked })
        #expect(changes.contains { $0.path == ".gitignore" && $0.status == .untracked })
        #expect(changes.contains { $0.path == ".build/output.txt" && $0.status == .ignored })
    }

    @Test("Git status summary counts tracked changes without ignored file expansion")
    func statusSummaryCountsChanges() async throws {
        let fixture = try TestStatusRepositoryFixture()
        defer { fixture.cleanup() }

        let trackedFile = fixture.repositoryRoot.appendingPathComponent("tracked.swift")
        try "print(\"one\")\n".write(
            to: trackedFile,
            atomically: true,
            encoding: .utf8
        )
        try fixture.runGit(arguments: ["add", "tracked.swift"])
        try fixture.runGit(arguments: ["commit", "-m", "Track file"])

        try "print(\"two\")\n".write(
            to: trackedFile,
            atomically: true,
            encoding: .utf8
        )

        let stagedFile = fixture.repositoryRoot.appendingPathComponent("staged.swift")
        try "print(\"staged\")\n".write(
            to: stagedFile,
            atomically: true,
            encoding: .utf8
        )
        try fixture.runGit(arguments: ["add", "staged.swift"])

        try "ignored/\n".write(
            to: fixture.repositoryRoot.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try fixture.runGit(arguments: ["add", ".gitignore"])
        let ignoredDirectory = fixture.repositoryRoot.appendingPathComponent("ignored")
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try "artifact\n".write(
            to: ignoredDirectory.appendingPathComponent("output.txt"),
            atomically: true,
            encoding: .utf8
        )

        let untrackedFile = fixture.repositoryRoot.appendingPathComponent("notes.txt")
        try "notes\n".write(
            to: untrackedFile,
            atomically: true,
            encoding: .utf8
        )

        let client = GitClient(repositoryURL: fixture.repositoryRoot)
        let summary = try await client.statusSummary()

        #expect(summary.staged == 2)
        #expect(summary.unstaged == 1)
        #expect(summary.untracked == 1)
        #expect(summary.conflicts == 0)
    }
}

private struct TestStatusRepositoryFixture {
    let repositoryRoot: URL

    init() throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-status-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        try runGit(arguments: ["init", "-b", "main"])
        try runGit(arguments: ["config", "user.name", "Devys Tests"])
        try runGit(arguments: ["config", "user.email", "tests@devys.local"])
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func runGit(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = repositoryRoot
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
