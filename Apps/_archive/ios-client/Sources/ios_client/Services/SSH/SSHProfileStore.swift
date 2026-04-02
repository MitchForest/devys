import Foundation

@MainActor
final class SSHProfileStore {
    private enum Keys {
        static let profiles = "ios_client.ssh_profiles"
    }

    private let defaults: UserDefaults
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }

    func loadProfiles() -> [SSHConnectionProfile] {
        guard let data = defaults.data(forKey: Keys.profiles) else { return [] }
        guard let profiles = try? decoder.decode([SSHConnectionProfile].self, from: data) else { return [] }
        return profiles.sorted(by: Self.sortProfiles)
    }

    func saveProfiles(_ profiles: [SSHConnectionProfile]) {
        guard let data = try? encoder.encode(profiles) else { return }
        defaults.set(data, forKey: Keys.profiles)
    }

    func upsertProfile(_ profile: SSHConnectionProfile) -> [SSHConnectionProfile] {
        var profiles = loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort(by: Self.sortProfiles)
        saveProfiles(profiles)
        return profiles
    }

    func deleteProfile(id: String) -> [SSHConnectionProfile] {
        var profiles = loadProfiles()
        profiles.removeAll { $0.id == id }
        saveProfiles(profiles)
        return profiles
    }

    func markProfileUsed(id: String, usedAt: Date = .now) -> [SSHConnectionProfile] {
        var profiles = loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return profiles
        }
        profiles[index].markUsed(now: usedAt)
        profiles.sort(by: Self.sortProfiles)
        saveProfiles(profiles)
        return profiles
    }
}

private extension SSHProfileStore {
    static func sortProfiles(lhs: SSHConnectionProfile, rhs: SSHConnectionProfile) -> Bool {
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case let (.some(left), .some(right)):
            if left != right {
                return left > right
            }
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            break
        }

        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
