// RepositorySettingsStore.swift
// DevysCore - Repository settings store.

import Foundation
import Observation

@MainActor
@Observable
public final class RepositorySettingsStore {
    public private(set) var settingsByRepository: [String: RepositorySettings]
    private let persistence: RepositorySettingsPersistenceService

    public init(
        persistence: RepositorySettingsPersistenceService = UserDefaultsRepositorySettingsPersistence()
    ) {
        self.persistence = persistence
        self.settingsByRepository = persistence.loadSettings()
    }

    public func settings(for repositoryRoot: URL?) -> RepositorySettings {
        guard let repositoryRoot else { return RepositorySettings() }
        return settingsByRepository[repositoryRoot.standardizedFileURL.path] ?? RepositorySettings()
    }

    public func portLabelsByPort(for repositoryRoot: URL?) -> [Int: RepositoryPortLabel] {
        Dictionary(
            uniqueKeysWithValues: settings(for: repositoryRoot)
                .portLabels
                .map { ($0.port, $0) }
        )
    }

    public func updateSettings(_ settings: RepositorySettings, for repositoryRoot: URL) {
        let key = repositoryRoot.standardizedFileURL.path
        settingsByRepository[key] = settings
        persistence.saveSettings(settingsByRepository)
    }

    public func updateWorkspaceCreation(
        _ workspaceCreation: WorkspaceCreationDefaults,
        for repositoryRoot: URL
    ) {
        var settings = settings(for: repositoryRoot)
        settings.workspaceCreation = workspaceCreation
        updateSettings(settings, for: repositoryRoot)
    }

    public func updateClaudeLauncher(_ launcher: LauncherTemplate, for repositoryRoot: URL) {
        var settings = settings(for: repositoryRoot)
        settings.claudeLauncher = launcher
        updateSettings(settings, for: repositoryRoot)
    }

    public func updateCodexLauncher(_ launcher: LauncherTemplate, for repositoryRoot: URL) {
        var settings = settings(for: repositoryRoot)
        settings.codexLauncher = launcher
        updateSettings(settings, for: repositoryRoot)
    }

    public func updateStartupProfiles(_ startupProfiles: [StartupProfile], for repositoryRoot: URL) {
        var settings = settings(for: repositoryRoot)
        settings.startupProfiles = startupProfiles
        updateSettings(settings, for: repositoryRoot)
    }

    public func updateDefaultStartupProfileID(
        _ startupProfileID: StartupProfile.ID?,
        for repositoryRoot: URL
    ) {
        var settings = settings(for: repositoryRoot)
        settings.defaultStartupProfileID = startupProfileID
        updateSettings(settings, for: repositoryRoot)
    }
}
