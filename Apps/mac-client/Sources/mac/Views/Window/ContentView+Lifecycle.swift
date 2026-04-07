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
        if workspaceCatalog.hasRepositories {
            workspaceShell
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
        applyNotificationModifiers(
            applySessionModifiers(
                applyAppearanceModifiers(view)
            )
        )
    }

    private func applyAppearanceModifiers<V: View>(_ view: V) -> some View {
        view
            .onAppear {
                configureSplitDelegate()
                if !hasInitialized {
                    hasInitialized = true
                    themeManager.isDarkMode = appSettings.appearance.isDarkMode
                    themeManager.setAccentColor(from: appSettings.appearance.accentColor)
                    themeManager.applyAppearance()
                    GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
                    runtimeRegistry.configure(container: container)
                    syncCatalogRuntimeState()
                    Task {
                        refreshAvailableRelaunchSnapshot()
                        await warmPersistentTerminalHostIfNeeded()
                        await restorePersistentTerminalRelaunchStateIfNeeded()
                    }
                }
            }
            .onChange(of: themeManager.isDarkMode) { _, _ in
                themeManager.applyAppearance()
                GhosttyTerminalThemeController.apply(themeManager.ghosttyAppearance)
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
                syncAttentionPreferences()
            }
    }

    private func applySessionModifiers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: terminalBellSnapshot) { _, _ in
                syncTerminalNotifications()
            }
    }
}
