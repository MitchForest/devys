// RepositoryCommandSettingsPersistenceService.swift
// DevysCore - Persistence for per-repository command settings.

import Foundation

public protocol RepositoryCommandSettingsPersistenceService {
    func loadSettings() -> [String: RepositoryCommandSettings]
    func saveSettings(_ settings: [String: RepositoryCommandSettings])
}

public struct UserDefaultsRepositoryCommandSettingsPersistence: RepositoryCommandSettingsPersistenceService {
    private let userDefaults: UserDefaults
    private let key = "devys.repositoryCommandSettings"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadSettings() -> [String: RepositoryCommandSettings] {
        guard let data = userDefaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: RepositoryCommandSettings].self, from: data)) ?? [:]
    }

    public func saveSettings(_ settings: [String: RepositoryCommandSettings]) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: key)
    }
}
