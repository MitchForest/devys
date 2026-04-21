// SettingsScopeTests.swift
// DevysCore Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Testing
@testable import Workspace

@Suite("Global Settings Persistence Tests")
struct GlobalSettingsPersistenceTests {
    @Test("Global settings round-trip through a single blob")
    func globalSettingsRoundTrip() {
        let suiteName = "com.devys.tests.global-settings.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = UserDefaultsSettingsPersistenceService(userDefaults: userDefaults)
        let settings = GlobalSettings(
            shell: ShellSettings(
                defaultExternalEditorBundleIdentifier: "com.microsoft.VSCode"
            ),
            explorer: ExplorerSettings(showDotfiles: false, excludePatterns: ["node_modules"]),
            appearance: AppearanceSettings(mode: .auto, uiFontScale: 1.25, accentColor: "#FF0000"),
            chat: ChatSettings(defaultHarness: ChatSettings.Harness.codex.rawValue),
            notifications: NotificationSettings(
                terminalActivity: false,
                chatActivity: true
            ),
            restore: RestoreSettings(
                restoreRepositoriesOnLaunch: true,
                restoreSelectedWorkspace: true,
                restoreWorkspaceLayoutAndTabs: false,
                restoreTerminalSessions: true,
                restoreChatSessions: false
            ),
            shortcuts: WorkspaceShellShortcutSettings(
                bindingsByAction: [
                    .nextWorkspace: ShortcutBinding(
                        key: "downarrow",
                        modifiers: ShortcutModifierSet(command: true, option: true)
                    ),
                    .launchClaude: ShortcutBinding(
                        key: "l",
                        modifiers: ShortcutModifierSet(command: true, control: true)
                    ),
                ]
            )
        )

        service.saveGlobalSettings(settings)

        #expect(service.loadGlobalSettings() == settings)
    }

    @Test("Global settings default cleanly when nothing is persisted")
    func globalSettingsDefaultToCleanState() {
        let suiteName = "com.devys.tests.global-settings-defaults.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let service = UserDefaultsSettingsPersistenceService(userDefaults: userDefaults)

        #expect(service.loadGlobalSettings() == GlobalSettings())
    }

    @Test("Legacy global settings decode into the new restore model")
    func legacyGlobalSettingsDecodeIntoRestoreSettings() throws {
        let suiteName = "com.devys.tests.global-settings-legacy.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let encoder = JSONEncoder()
        let legacySettings = LegacyGlobalSettings(
            shell: LegacyShellSettings(
                defaultExternalEditorBundleIdentifier: "com.microsoft.VSCode",
                preserveTerminalsOnRelaunch: true
            ),
            explorer: ExplorerSettings(showDotfiles: false, excludePatterns: ["DerivedData"]),
            appearance: AppearanceSettings(mode: .light, uiFontScale: 1.1, accentColor: "#00FF00"),
            agent: ChatSettings(defaultHarness: ChatSettings.Harness.claudeCode.rawValue)
        )

        userDefaults.set(
            try encoder.encode(legacySettings),
            forKey: "com.devys.settings.global"
        )

        let loaded = UserDefaultsSettingsPersistenceService(userDefaults: userDefaults).loadGlobalSettings()

        #expect(loaded.shell.defaultExternalEditorBundleIdentifier == "com.microsoft.VSCode")
        #expect(loaded.notifications == NotificationSettings())
        #expect(loaded.restore.restoreRepositoriesOnLaunch)
        #expect(loaded.restore.restoreSelectedWorkspace)
        #expect(loaded.restore.restoreTerminalSessions)
        #expect(loaded.restore.restoreWorkspaceLayoutAndTabs)
        #expect(loaded.restore.restoreChatSessions)
        #expect(loaded.shortcuts == WorkspaceShellShortcutSettings())
    }

    @Test("Restore settings default chat restore when the persisted field is absent")
    func restoreSettingsDecodeDefaultsChatRestore() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "restoreRepositoriesOnLaunch": true,
            "restoreSelectedWorkspace": false,
            "restoreWorkspaceLayoutAndTabs": true,
            "restoreTerminalSessions": true
        ])

        let decoded = try JSONDecoder().decode(RestoreSettings.self, from: data)

        #expect(decoded.restoreRepositoriesOnLaunch)
        #expect(!decoded.restoreSelectedWorkspace)
        #expect(decoded.restoreWorkspaceLayoutAndTabs)
        #expect(decoded.restoreTerminalSessions)
        #expect(decoded.restoreChatSessions)
    }

    @Test("Legacy notification and restore keys decode into chat settings")
    func legacyNotificationAndRestoreKeysDecodeIntoChatSettings() throws {
        let notificationData = try JSONSerialization.data(withJSONObject: [
            "terminalActivity": false,
            "agentActivity": true
        ])
        let restoreData = try JSONSerialization.data(withJSONObject: [
            "restoreRepositoriesOnLaunch": true,
            "restoreSelectedWorkspace": true,
            "restoreWorkspaceLayoutAndTabs": true,
            "restoreTerminalSessions": false,
            "restoreAgentSessions": false
        ])

        let decodedNotifications = try JSONDecoder().decode(NotificationSettings.self, from: notificationData)
        let decodedRestore = try JSONDecoder().decode(RestoreSettings.self, from: restoreData)

        #expect(decodedNotifications.terminalActivity == false)
        #expect(decodedNotifications.chatActivity == true)
        #expect(decodedRestore.restoreChatSessions == false)
    }
}

private struct LegacyGlobalSettings: Codable {
    var shell: LegacyShellSettings
    var explorer: ExplorerSettings
    var appearance: AppearanceSettings
    var agent: ChatSettings
}

private struct LegacyShellSettings: Codable {
    var defaultExternalEditorBundleIdentifier: String?
    var preserveTerminalsOnRelaunch: Bool
}

@Suite("Repository Settings Store Tests")
struct RepositorySettingsStoreTests {
    @Test("Repository settings do not leak across repositories")
    @MainActor
    func repositorySettingsIsolation() {
        let suiteName = "com.devys.tests.repository-settings.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = RepositorySettingsStore(
            persistence: UserDefaultsRepositorySettingsPersistence(userDefaults: userDefaults)
        )
        let firstRoot = URL(fileURLWithPath: "/tmp/devys/repo-a")
        let secondRoot = URL(fileURLWithPath: "/tmp/devys/repo-b")
        let webPortLabel = RepositoryPortLabel(
            port: 3000,
            label: "Web",
            scheme: "http",
            path: "/health"
        )

        store.updateSettings(
            RepositorySettings(
                workspaceCreation: WorkspaceCreationDefaults(
                    defaultBaseBranch: "develop",
                    copyIgnoredFiles: true,
                    copyUntrackedFiles: false
                ),
                claudeLauncher: LauncherTemplate(
                    executable: "cc",
                    model: "opus",
                    reasoningLevel: "high",
                    dangerousPermissions: true,
                    extraArguments: ["--foo"],
                    executionBehavior: .stageInTerminal
                ),
                codexLauncher: .codexDefault,
                review: ReviewSettings(
                    isEnabled: true,
                    reviewOnCommit: true,
                    reviewOnPullRequestUpdates: true,
                    auditHarness: .claude,
                    followUpHarness: .codex,
                    auditModelOverride: "sonnet",
                    followUpModelOverride: "gpt-5.2",
                    auditReasoningOverride: "medium",
                    followUpReasoningOverride: "high",
                    auditDangerousPermissionsOverride: false,
                    followUpDangerousPermissionsOverride: true,
                    additionalInstructions: "Prefer explicit ownership findings."
                ),
                startupProfiles: [
                    StartupProfile(
                        displayName: "Dev",
                        steps: [
                            StartupProfileStep(
                                displayName: "Web",
                                workingDirectory: "apps/web",
                                command: "pnpm dev",
                                launchMode: .newTab
                            )
                        ]
                    )
                ],
                portLabels: [webPortLabel]
            ),
            for: firstRoot
        )

        let firstSettings = store.settings(for: firstRoot)
        let secondSettings = store.settings(for: secondRoot)

        #expect(firstSettings.workspaceCreation.defaultBaseBranch == "develop")
        #expect(firstSettings.claudeLauncher.model == "opus")
        #expect(firstSettings.review.reviewOnCommit)
        #expect(firstSettings.review.reviewOnPullRequestUpdates)
        #expect(firstSettings.review.auditHarness == .claude)
        #expect(firstSettings.review.followUpHarness == .codex)
        #expect(firstSettings.review.auditModelOverride == "sonnet")
        #expect(firstSettings.review.followUpModelOverride == "gpt-5.2")
        #expect(firstSettings.review.auditReasoningOverride == "medium")
        #expect(firstSettings.review.followUpReasoningOverride == "high")
        #expect(firstSettings.review.auditDangerousPermissionsOverride == false)
        #expect(firstSettings.review.followUpDangerousPermissionsOverride == true)
        #expect(firstSettings.review.additionalInstructions == "Prefer explicit ownership findings.")
        #expect(firstSettings.startupProfiles.count == 1)
        #expect(firstSettings.portLabels == [webPortLabel])
        #expect(secondSettings == RepositorySettings())
    }

    @Test("Repository settings decode default review settings when absent")
    func repositorySettingsDecodeDefaultsReviewSettings() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "workspaceCreation": [
                "defaultBaseBranch": "main",
                "copyIgnoredFiles": false,
                "copyUntrackedFiles": false
            ],
            "claudeLauncher": [
                "executable": "claude",
                "dangerousPermissions": true,
                "extraArguments": [],
                "executionBehavior": "runImmediately"
            ],
            "codexLauncher": [
                "executable": "codex",
                "dangerousPermissions": false,
                "extraArguments": [],
                "executionBehavior": "runImmediately"
            ],
            "startupProfiles": [],
            "portLabels": []
        ])

        let decoded = try JSONDecoder().decode(RepositorySettings.self, from: data)

        #expect(decoded.review == ReviewSettings())
    }

    @Test("Review settings decode explicit overrides")
    func reviewSettingsDecodeExplicitOverrides() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "isEnabled": false,
            "reviewOnCommit": true,
            "reviewOnPullRequestUpdates": true,
            "auditHarness": "claude",
            "followUpHarness": "codex",
            "auditModelOverride": "sonnet",
            "followUpModelOverride": "gpt-5.2",
            "auditReasoningOverride": "medium",
            "followUpReasoningOverride": "high",
            "auditDangerousPermissionsOverride": false,
            "followUpDangerousPermissionsOverride": true,
            "additionalInstructions": "Prefer explicit ownership findings."
        ])

        let decoded = try JSONDecoder().decode(ReviewSettings.self, from: data)

        #expect(decoded.isEnabled == false)
        #expect(decoded.reviewOnCommit)
        #expect(decoded.reviewOnPullRequestUpdates)
        #expect(decoded.auditHarness == .claude)
        #expect(decoded.followUpHarness == .codex)
        #expect(decoded.auditModelOverride == "sonnet")
        #expect(decoded.followUpModelOverride == "gpt-5.2")
        #expect(decoded.auditReasoningOverride == "medium")
        #expect(decoded.followUpReasoningOverride == "high")
        #expect(decoded.auditDangerousPermissionsOverride == false)
        #expect(decoded.followUpDangerousPermissionsOverride == true)
        #expect(decoded.additionalInstructions == "Prefer explicit ownership findings.")
    }

    @Test("Port labels are indexed by port per repository")
    @MainActor
    func repositoryPortLabelsByPort() {
        let suiteName = "com.devys.tests.repository-port-labels.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create UserDefaults suite")
            return
        }
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
        }

        let store = RepositorySettingsStore(
            persistence: UserDefaultsRepositorySettingsPersistence(userDefaults: userDefaults)
        )
        let repositoryRoot = URL(fileURLWithPath: "/tmp/devys/repo-a")
        let webLabel = RepositoryPortLabel(
            port: 3000,
            label: "Web",
            scheme: "http",
            path: "/health"
        )
        let apiLabel = RepositoryPortLabel(
            port: 4000,
            label: "API",
            scheme: "https",
            path: "/ready"
        )

        store.updateSettings(
            RepositorySettings(portLabels: [webLabel, apiLabel]),
            for: repositoryRoot
        )

        #expect(store.portLabelsByPort(for: nil).isEmpty)
        #expect(store.portLabelsByPort(for: repositoryRoot) == [
            3000: webLabel,
            4000: apiLabel
        ])
    }
}
