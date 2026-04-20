import Foundation
import Testing
@testable import Git

struct GitRepositoryMetadataWatcherTests {
    @Test("Git directory resolver returns the in-place .git directory for standard repositories")
    func resolvesStandardRepositoryGitDirectory() throws {
        let fixture = try GitDirectoryFixture(mode: .directory)
        defer { fixture.cleanup() }

        let resolvedGitDirectory = try #require(
            GitRepositoryReferenceResolver.resolveGitDirectory(for: fixture.repositoryRoot)
        )

        #expect(resolvedGitDirectory == fixture.expectedGitDirectory)
    }

    @Test("Git directory resolver follows gitdir indirection for linked worktrees")
    func resolvesIndirectGitDirectory() throws {
        let fixture = try GitDirectoryFixture(mode: .fileReference)
        defer { fixture.cleanup() }

        let resolvedGitDirectory = try #require(
            GitRepositoryReferenceResolver.resolveGitDirectory(for: fixture.repositoryRoot)
        )

        #expect(resolvedGitDirectory == fixture.expectedGitDirectory)
    }

    @Test("Current reference resolver follows the common git directory for linked worktrees")
    func resolvesCurrentReferenceInCommonDirectory() throws {
        let fixture = try GitDirectoryFixture(mode: .linkedWorktree)
        defer { fixture.cleanup() }

        let currentReferenceURL = try #require(
            GitRepositoryReferenceResolver.resolveCurrentReferenceURL(for: fixture.repositoryRoot)
        )

        #expect(currentReferenceURL == fixture.expectedCurrentReferenceURL)
    }
}

private struct GitDirectoryFixture {
    enum Mode {
        case directory
        case fileReference
        case linkedWorktree
    }

    let repositoryRoot: URL
    let expectedGitDirectory: URL
    let expectedCurrentReferenceURL: URL?

    init(mode: Mode) throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)

        switch mode {
        case .directory:
            let gitDirectory = repositoryRoot.appendingPathComponent(".git")
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            expectedGitDirectory = gitDirectory.standardizedFileURL
            expectedCurrentReferenceURL = nil
        case .fileReference:
            let metadataRoot = repositoryRoot.appendingPathComponent(".worktree-metadata")
            let gitDirectory = metadataRoot.appendingPathComponent("gitdir")
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            let gitFile = repositoryRoot.appendingPathComponent(".git")
            let relativeGitPath = ".worktree-metadata/gitdir"
            try "gitdir: \(relativeGitPath)\n".write(
                to: gitFile,
                atomically: true,
                encoding: .utf8
            )
            expectedGitDirectory = gitDirectory.standardizedFileURL
            expectedCurrentReferenceURL = nil
        case .linkedWorktree:
            let metadataRoot = repositoryRoot.appendingPathComponent(".worktree-metadata")
            let worktreeGitDirectory = metadataRoot.appendingPathComponent("worktree-gitdir")
            let commonGitDirectory = metadataRoot.appendingPathComponent("common-gitdir")
            let branchReferenceURL = commonGitDirectory
                .appendingPathComponent("refs/heads/feature/external")

            try FileManager.default.createDirectory(
                at: worktreeGitDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: branchReferenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try "ref: refs/heads/feature/external\n".write(
                to: worktreeGitDirectory.appendingPathComponent("HEAD"),
                atomically: true,
                encoding: .utf8
            )
            try "../common-gitdir\n".write(
                to: worktreeGitDirectory.appendingPathComponent("commondir"),
                atomically: true,
                encoding: .utf8
            )
            try "1234567\n".write(
                to: branchReferenceURL,
                atomically: true,
                encoding: .utf8
            )

            let gitFile = repositoryRoot.appendingPathComponent(".git")
            try "gitdir: .worktree-metadata/worktree-gitdir\n".write(
                to: gitFile,
                atomically: true,
                encoding: .utf8
            )

            expectedGitDirectory = worktreeGitDirectory.standardizedFileURL
            expectedCurrentReferenceURL = branchReferenceURL.standardizedFileURL
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }
}
