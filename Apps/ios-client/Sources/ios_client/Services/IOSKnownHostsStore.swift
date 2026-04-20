import Foundation
import SSH

actor IOSKnownHostsStore {
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        snapshotURL: URL = IOSKnownHostsStore.defaultSnapshotURL()
    ) {
        self.fileManager = fileManager
        self.snapshotURL = snapshotURL
    }

    func trustedContext(
        host: String,
        port: Int
    ) throws -> SSHHostKeyValidationContext? {
        try loadAll()[key(host: host, port: port)]
    }

    func trust(_ context: SSHHostKeyValidationContext) throws {
        var hosts = try loadAll()
        hosts[key(host: context.host, port: context.port)] = context
        try saveAll(hosts)
    }

    func clear() throws {
        try saveAll([:])
    }

    func count() throws -> Int {
        try loadAll().count
    }

    private func loadAll() throws -> [String: SSHHostKeyValidationContext] {
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return [:]
        }
        return try decoder.decode([String: SSHHostKeyValidationContext].self, from: data)
    }

    private func saveAll(
        _ hosts: [String: SSHHostKeyValidationContext]
    ) throws {
        try fileManager.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(hosts)
        try data.write(to: snapshotURL, options: .atomic)
    }

    private func key(host: String, port: Int) -> String {
        "\(host):\(port)"
    }

    static func defaultSnapshotURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Devys-iOS", isDirectory: true)
            .appendingPathComponent("Remote", isDirectory: true)

        return (baseURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("known-hosts.json", isDirectory: false)
    }
}
