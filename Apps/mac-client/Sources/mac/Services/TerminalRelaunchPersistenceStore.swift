// TerminalRelaunchPersistenceStore.swift
// Devys - Persistence for workspace terminal relaunch state.

import Foundation

struct TerminalRelaunchPersistenceStore {
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        snapshotURL: URL = TerminalRelaunchPersistenceStore.defaultSnapshotURL()
    ) {
        self.fileManager = fileManager
        self.snapshotURL = snapshotURL
    }

    func load() -> TerminalRelaunchSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? decoder.decode(TerminalRelaunchSnapshot.self, from: data)
    }

    func save(_ snapshot: TerminalRelaunchSnapshot) throws {
        let directoryURL = snapshotURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: snapshotURL.path) else { return }
        try fileManager.removeItem(at: snapshotURL)
    }

    static func defaultSnapshotURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Devys", isDirectory: true)
            .appendingPathComponent("TerminalHost", isDirectory: true)

        return (baseURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("relaunch-snapshot.json", isDirectory: false)
    }
}
