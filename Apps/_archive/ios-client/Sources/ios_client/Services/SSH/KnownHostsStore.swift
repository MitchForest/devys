import Foundation

struct KnownHostRecord: Codable, Sendable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let host: String
    let port: Int
    let algorithm: String
    let fingerprint: String
    let firstSeenAt: Date
    var lastVerifiedAt: Date
}

enum KnownHostTrustResult: Equatable {
    case trusted(KnownHostRecord)
    case unknown
    case mismatch(existing: KnownHostRecord)
}

@MainActor
final class KnownHostsStore {
    private enum Keys {
        static let knownHosts = "ios_client.ssh_known_hosts"
    }

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func allRecords() -> [KnownHostRecord] {
        guard let data = defaults.data(forKey: Keys.knownHosts) else { return [] }
        guard let records = try? decoder.decode([KnownHostRecord].self, from: data) else { return [] }
        return records.sorted { lhs, rhs in
            if lhs.host != rhs.host {
                return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            if lhs.port != rhs.port {
                return lhs.port < rhs.port
            }
            if lhs.lastVerifiedAt != rhs.lastVerifiedAt {
                return lhs.lastVerifiedAt > rhs.lastVerifiedAt
            }
            return lhs.algorithm.localizedCaseInsensitiveCompare(rhs.algorithm) == .orderedAscending
        }
    }

    func trustRecord(
        host: String,
        port: Int,
        algorithm: String,
        fingerprint: String,
        now: Date = .now
    ) -> KnownHostRecord {
        var records = allRecords()
        let key = Self.key(host: host, port: port, algorithm: algorithm)

        if let index = records.firstIndex(where: { $0.key == key }) {
            var updated = records[index]
            updated.lastVerifiedAt = now
            let rewritten = KnownHostRecord(
                key: key,
                host: host,
                port: port,
                algorithm: algorithm,
                fingerprint: fingerprint,
                firstSeenAt: updated.firstSeenAt,
                lastVerifiedAt: now
            )
            records[index] = rewritten
            persist(records)
            return rewritten
        }

        let created = KnownHostRecord(
            key: key,
            host: host,
            port: port,
            algorithm: algorithm,
            fingerprint: fingerprint,
            firstSeenAt: now,
            lastVerifiedAt: now
        )
        records.append(created)
        persist(records)
        return created
    }

    func verify(
        host: String,
        port: Int,
        algorithm: String,
        fingerprint: String,
        now: Date = .now
    ) -> KnownHostTrustResult {
        let key = Self.key(host: host, port: port, algorithm: algorithm)
        var records = allRecords()
        guard let index = records.firstIndex(where: { $0.key == key }) else {
            return .unknown
        }

        let existing = records[index]
        guard existing.fingerprint == fingerprint else {
            return .mismatch(existing: existing)
        }

        var updated = existing
        updated.lastVerifiedAt = now
        records[index] = updated
        persist(records)
        return .trusted(updated)
    }

}

private extension KnownHostsStore {
    func persist(_ records: [KnownHostRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        defaults.set(data, forKey: Keys.knownHosts)
    }

    static func key(host: String, port: Int, algorithm: String) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAlgorithm = algorithm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedHost):\(port):\(normalizedAlgorithm)"
    }
}
