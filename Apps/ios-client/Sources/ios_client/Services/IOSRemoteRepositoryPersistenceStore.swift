import Foundation
import RemoteFeatures
import RemoteCore
import SSH
import Security

enum IOSRemoteRepositoryPersistenceStoreError: LocalizedError {
    case authorityConnectionMismatch(missingConnectionIDs: [String], orphanConnectionIDs: [String])

    var errorDescription: String? {
        switch self {
        case let .authorityConnectionMismatch(missingConnectionIDs, orphanConnectionIDs):
            var parts: [String] = []
            if !missingConnectionIDs.isEmpty {
                parts.append("Missing credentials for: \(missingConnectionIDs.joined(separator: ", "))")
            }
            if !orphanConnectionIDs.isEmpty {
                parts.append("Unexpected credentials for: \(orphanConnectionIDs.joined(separator: ", "))")
            }
            return "Stored remote repository state is inconsistent. " + parts.joined(separator: ". ")
        }
    }
}

actor IOSRemoteRepositoryPersistenceStore {
    private let fileManager: FileManager
    private let snapshotURL: URL
    private let keychainService = "com.devys.ios-client.remote-repositories"
    private let keychainAccount = "connections"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        snapshotURL: URL = IOSRemoteRepositoryPersistenceStore.defaultSnapshotURL()
    ) {
        self.fileManager = fileManager
        self.snapshotURL = snapshotURL
    }

    func load() throws -> [RemoteRepositoryRecord] {
        let authorities = try loadAuthorities()
        let connections = try loadConnections()
        try validateStoredRepositories(authorities: authorities, connections: connections)
        var repositories: [RemoteRepositoryRecord] = []
        repositories.reserveCapacity(authorities.count)

        for authority in authorities {
            guard let connection = connections[authority.id] else {
                throw IOSRemoteRepositoryPersistenceStoreError.authorityConnectionMismatch(
                    missingConnectionIDs: [authority.id],
                    orphanConnectionIDs: []
                )
            }

            repositories.append(
                RemoteRepositoryRecord(
                    authority: authority,
                    connection: connection
                )
            )
        }

        return repositories
    }

    func save(_ repositories: [RemoteRepositoryRecord]) throws {
        try fileManager.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let authorities = repositories.map(\.authority)
        let authorityData = try encoder.encode(authorities)
        try authorityData.write(to: snapshotURL, options: .atomic)

        let connections = Dictionary(
            uniqueKeysWithValues: repositories.map { ($0.id, $0.connection) }
        )
        try saveConnections(connections)
    }

    private func loadAuthorities() throws -> [RemoteRepositoryAuthority] {
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return []
        }
        return try decoder.decode([RemoteRepositoryAuthority].self, from: data)
    }

    private func loadConnections() throws -> [String: SSHConnectionConfiguration] {
        guard let data = try readKeychainData() else {
            return [:]
        }
        return try decoder.decode([String: SSHConnectionConfiguration].self, from: data)
    }

    private func saveConnections(
        _ connections: [String: SSHConnectionConfiguration]
    ) throws {
        if connections.isEmpty {
            try deleteKeychainData()
            return
        }

        let data = try encoder.encode(connections)
        try writeKeychainData(data)
    }

    private func validateStoredRepositories(
        authorities: [RemoteRepositoryAuthority],
        connections: [String: SSHConnectionConfiguration]
    ) throws {
        let authorityIDs = Set(authorities.map(\.id))
        let connectionIDs = Set(connections.keys)
        let missingConnectionIDs = authorityIDs.subtracting(connectionIDs).sorted()
        let orphanConnectionIDs = connectionIDs.subtracting(authorityIDs).sorted()
        guard missingConnectionIDs.isEmpty, orphanConnectionIDs.isEmpty else {
            throw IOSRemoteRepositoryPersistenceStoreError.authorityConnectionMismatch(
                missingConnectionIDs: missingConnectionIDs,
                orphanConnectionIDs: orphanConnectionIDs
            )
        }
    }

    private func readKeychainData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to load remote repository credentials."]
            )
        }
    }

    private func writeKeychainData(_ data: Data) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insertQuery = baseQuery
            insertQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(addStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Failed to save remote repository credentials."]
                )
            }
        default:
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to save remote repository credentials."]
            )
        }
    }

    private func deleteKeychainData() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to clear remote repository credentials."]
            )
        }
    }

    static func defaultSnapshotURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("Devys-iOS", isDirectory: true)
            .appendingPathComponent("Remote", isDirectory: true)

        return (baseURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("repositories.json", isDirectory: false)
    }
}
