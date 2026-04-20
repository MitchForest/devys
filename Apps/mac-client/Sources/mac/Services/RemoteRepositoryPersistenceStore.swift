import AppFeatures
import Foundation
import RemoteCore

actor RemoteRepositoryPersistenceStore {
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        snapshotURL: URL = RemoteRepositoryPersistenceStore.defaultSnapshotURL()
    ) {
        self.fileManager = fileManager
        self.snapshotURL = snapshotURL
    }

    func load() throws -> [RemoteRepositoryAuthority] {
        guard let data = try? Data(contentsOf: snapshotURL) else { return [] }
        return try decoder.decode([RemoteRepositoryAuthority].self, from: data)
    }

    func save(_ repositories: [RemoteRepositoryAuthority]) throws {
        let directoryURL = snapshotURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(repositories)
        try data.write(to: snapshotURL, options: .atomic)
    }

    static func defaultSnapshotURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Devys", isDirectory: true)
            .appendingPathComponent("Remote", isDirectory: true)

        return (baseURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("repositories.json", isDirectory: false)
    }
}
