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
}

private struct GitDirectoryFixture {
    enum Mode {
        case directory
        case fileReference
    }

    let repositoryRoot: URL
    let expectedGitDirectory: URL

    init(mode: Mode) throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devys-git-metadata-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)

        switch mode {
        case .directory:
            let gitDirectory = repositoryRoot.appendingPathComponent(".git")
            try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
            expectedGitDirectory = gitDirectory.standardizedFileURL
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
        }
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }
}
