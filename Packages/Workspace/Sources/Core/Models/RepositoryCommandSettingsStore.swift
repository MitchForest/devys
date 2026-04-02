// RepositoryCommandSettingsStore.swift
// DevysCore - Command settings store.

import Foundation
import Observation

@MainActor
@Observable
public final class RepositoryCommandSettingsStore {
    public private(set) var settingsByRepository: [String: RepositoryCommandSettings]
    private let persistence: RepositoryCommandSettingsPersistenceService

    public init(
        persistence: RepositoryCommandSettingsPersistenceService = UserDefaultsRepositoryCommandSettingsPersistence()
    ) {
        self.persistence = persistence
        self.settingsByRepository = persistence.loadSettings()
    }

    public func settings(for repositoryRoot: URL?) -> RepositoryCommandSettings {
        guard let repositoryRoot else { return RepositoryCommandSettings() }
        return settingsByRepository[repositoryRoot.standardizedFileURL.path] ?? RepositoryCommandSettings()
    }

    public func updateSettings(_ settings: RepositoryCommandSettings, for repositoryRoot: URL) {
        let key = repositoryRoot.standardizedFileURL.path
        settingsByRepository[key] = settings
        persistence.saveSettings(settingsByRepository)
    }

    public func updateRunCommand(_ command: String?, for repositoryRoot: URL) {
        var settings = settings(for: repositoryRoot)
        settings.runCommand = command
        updateSettings(settings, for: repositoryRoot)
    }
}
