// RepositorySettingsPersistenceService.swift
// DevysCore - Persistence for repository-scoped settings.

import Foundation

public protocol RepositorySettingsPersistenceService {
    func loadSettings() -> [String: RepositorySettings]
    func saveSettings(_ settings: [String: RepositorySettings])
}

public struct UserDefaultsRepositorySettingsPersistence: RepositorySettingsPersistenceService {
    private enum Keys {
        static let repositorySettings = "devys.repositorySettings"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadSettings() -> [String: RepositorySettings] {
        if let data = userDefaults.data(forKey: Keys.repositorySettings),
           let settings = try? JSONDecoder().decode([String: RepositorySettings].self, from: data) {
            return settings
        }

        return [:]
    }

    public func saveSettings(_ settings: [String: RepositorySettings]) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: Keys.repositorySettings)
    }
}
