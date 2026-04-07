// SettingsPersistenceService.swift
// Settings persistence abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public protocol SettingsPersistenceService {
    func loadGlobalSettings() -> GlobalSettings
    func saveGlobalSettings(_ settings: GlobalSettings)
}

public struct UserDefaultsSettingsPersistenceService: SettingsPersistenceService {
    private enum Keys {
        static let global = "com.devys.settings.global"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func loadGlobalSettings() -> GlobalSettings {
        if let settings: GlobalSettings = load(key: Keys.global) {
            return settings
        }

        return GlobalSettings()
    }

    public func saveGlobalSettings(_ settings: GlobalSettings) {
        save(settings, key: Keys.global)
    }

    private func save<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            userDefaults.set(data, forKey: key)
        }
    }

    private func load<T: Codable>(key: String) -> T? {
        guard let data = userDefaults.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return value
    }
}
