import ComposableArchitecture
import Diff
import Foundation
import Git

struct GitRepositoryClient: Sendable {
    var status: @Sendable (URL) async throws -> [GitFileChange]
    var diffSnapshot: @Sendable (URL, GitFileChange) async throws -> DiffSnapshot
    var stageFile: @Sendable (URL, GitFileChange) async throws -> Void
    var unstageFile: @Sendable (URL, GitFileChange) async throws -> Void
    var discardFile: @Sendable (URL, GitFileChange) async throws -> Void
    var stageHunk: @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void
    var unstageHunk: @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void
    var discardHunk: @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void

    init(
        status: @escaping @Sendable (URL) async throws -> [GitFileChange],
        diffSnapshot: @escaping @Sendable (URL, GitFileChange) async throws -> DiffSnapshot,
        stageFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void,
        unstageFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void,
        discardFile: @escaping @Sendable (URL, GitFileChange) async throws -> Void,
        stageHunk: @escaping @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void,
        unstageHunk: @escaping @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void,
        discardHunk: @escaping @Sendable (URL, DiffHunk, GitFileChange) async throws -> Void
    ) {
        self.status = status
        self.diffSnapshot = diffSnapshot
        self.stageFile = stageFile
        self.unstageFile = unstageFile
        self.discardFile = discardFile
        self.stageHunk = stageHunk
        self.unstageHunk = unstageHunk
        self.discardHunk = discardHunk
    }

    static let liveValue = GitRepositoryClient(
        status: { repositoryURL in
            try await GitClient(repositoryURL: repositoryURL.standardizedFileURL).status()
        },
        diffSnapshot: { repositoryURL, change in
            try await GitClient(repositoryURL: repositoryURL.standardizedFileURL)
                .diffSnapshot(for: change)
        },
        stageFile: { repositoryURL, change in
            try await GitClient(repositoryURL: repositoryURL.standardizedFileURL)
                .stageFile(change)
        },
        unstageFile: { repositoryURL, change in
            try await GitClient(repositoryURL: repositoryURL.standardizedFileURL)
                .unstageFile(change)
        },
        discardFile: { repositoryURL, change in
            try await GitClient(
                repositoryURL: repositoryURL.standardizedFileURL,
                fileDiscarder: .macTrash
            )
            .discardFile(change)
        },
        stageHunk: { repositoryURL, hunk, change in
            try await GitClient(repositoryURL: repositoryURL.standardizedFileURL)
                .stageHunk(hunk, for: change)
        },
        unstageHunk: { repositoryURL, hunk, change in
            try await GitClient(repositoryURL: repositoryURL.standardizedFileURL)
                .unstageHunk(hunk, for: change)
        },
        discardHunk: { repositoryURL, hunk, change in
            try await GitClient(
                repositoryURL: repositoryURL.standardizedFileURL,
                fileDiscarder: .macTrash
            )
            .discardHunk(hunk, for: change)
        }
    )
}

private enum GitRepositoryClientKey: DependencyKey {
    static let liveValue = GitRepositoryClient.liveValue
}

extension DependencyValues {
    var gitRepositoryClient: GitRepositoryClient {
        get { self[GitRepositoryClientKey.self] }
        set { self[GitRepositoryClientKey.self] = newValue }
    }
}

private extension GitFileDiscarder {
    static let macTrash = GitFileDiscarder { url in
        try await MainActor.run {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(
                at: url,
                resultingItemURL: &resultingURL
            )
        }
    }
}
