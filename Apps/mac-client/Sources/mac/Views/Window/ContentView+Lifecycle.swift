// ContentView+Lifecycle.swift
// Root content and lifecycle modifier wiring.
//
// Copyright © 2026 Devys. All rights reserved.

import GhosttyTerminal
import SwiftUI

@MainActor
extension ContentView {
    @ViewBuilder
    var rootContent: some View {
        if store.hasRepositories {
            workspaceShellView
        } else {
            ProjectPickerView(
                recentRepositories: Array(recentRepositoriesService.load().prefix(5)),
                canRestorePreviousSession: availableRelaunchSnapshot != nil,
                onAddRepository: { requestOpenRepository() },
                onRestorePreviousSession: {
                    Task { @MainActor in
                        await restorePreviousSession()
                    }
                },
                onOpenRecentRepository: { url in
                    Task { @MainActor in
                        await openRepository(url)
                    }
                }
            )
        }
    }

    func applyLifecycleModifiers<V: View>(_ view: V) -> some View {
        applyShellCommandRequestModifiers(
            applyAppearanceModifiers(view)
        )
    }

    private func applyAppearanceModifiers<V: View>(_ view: V) -> some View {
        view
            .onAppear {
                handleRootContentAppear()
            }
            .onChange(of: themeManager.isDarkMode) { _, _ in
                applyCurrentAppearance()
            }
            .onChange(of: appSettings.appearance.accentColor) { _, newValue in
                themeManager.setAccentColor(from: newValue)
                GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
                controller.updateColors(splitColorsFromTheme(themeManager.theme))
            }
            .onChange(of: themeManager.isDarkMode) { _, _ in
                controller.updateColors(splitColorsFromTheme(themeManager.theme))
            }
            .onChange(of: appSettings.appearance.isDarkMode) { _, newValue in
                themeManager.isDarkMode = newValue
            }
            .onChange(of: restoreSettingsSnapshot) { _, _ in
                persistTerminalRelaunchSnapshotIfNeeded()
                refreshAvailableRelaunchSnapshot()
            }
            .onChange(of: notificationSettingsSnapshot) { _, _ in
                store.send(
                    .setWorkspaceNotificationPreferences(
                        terminalActivity: appSettings.notifications.terminalActivity,
                        agentActivity: appSettings.notifications.agentActivity
                    )
                )
            }
    }

    private func handleRootContentAppear() {
        configureSplitDelegate()
        hostedContentBridge.setPublishHandler { workspaceID, content in
            store.send(.setHostedWorkspaceContent(workspaceID, content))
        }
        guard !hasInitialized else { return }

        hasInitialized = true
        themeManager.isDarkMode = appSettings.appearance.isDarkMode
        themeManager.setAccentColor(from: appSettings.appearance.accentColor)
        applyCurrentAppearance()
        configureRuntimeRegistryFactories()
        store.send(
            .setWorkspaceNotificationPreferences(
                terminalActivity: appSettings.notifications.terminalActivity,
                agentActivity: appSettings.notifications.agentActivity
            )
        )
        Task {
            refreshAvailableRelaunchSnapshot()
            await warmPersistentTerminalHostIfNeeded()
            await requestWindowRelaunchRestore(force: false)
        }
    }

    private func applyCurrentAppearance() {
        themeManager.applyAppearance()
        GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
    }

    private func configureRuntimeRegistryFactories() {
        runtimeRegistry.configure(
            makeGitStore: { workingDirectory in
                guard let workingDirectory else { return nil }
                return container.makeGitStore(projectFolder: workingDirectory)
            },
            makeFileTreeModel: { rootURL in
                container.makeFileTreeModel(rootURL: rootURL)
            }
        )
    }
}
