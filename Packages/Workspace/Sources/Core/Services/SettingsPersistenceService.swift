// SettingsPersistenceService.swift
// Settings persistence abstraction.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

public protocol SettingsPersistenceService {
    func loadExplorerSettings() -> ExplorerSettings
    func loadAppearanceSettings() -> AppearanceSettings
    func loadAgentSettings() -> AgentSettings

    func saveExplorerSettings(_ settings: ExplorerSettings)
    func saveAppearanceSettings(_ settings: AppearanceSettings)
    func saveAgentSettings(_ settings: AgentSettings)
}

public struct UserDefaultsSettingsPersistenceService: SettingsPersistenceService {
    private enum Keys {
        static let explorer = "com.devys.settings.explorer"
        static let appearance = "com.devys.settings.appearance"
        static let agent = "com.devys.settings.agent"
    }

    public init() {}

    public func loadExplorerSettings() -> ExplorerSettings {
        load(key: Keys.explorer) ?? ExplorerSettings()
    }

    public func loadAppearanceSettings() -> AppearanceSettings {
        load(key: Keys.appearance) ?? AppearanceSettings()
    }

    public func loadAgentSettings() -> AgentSettings {
        load(key: Keys.agent) ?? AgentSettings()
    }

    public func saveExplorerSettings(_ settings: ExplorerSettings) {
        save(settings, key: Keys.explorer)
    }

    public func saveAppearanceSettings(_ settings: AppearanceSettings) {
        save(settings, key: Keys.appearance)
    }

    public func saveAgentSettings(_ settings: AgentSettings) {
        save(settings, key: Keys.agent)
    }

    private func save<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load<T: Codable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return value
    }
}
