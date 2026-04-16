import AppFeatures
import ComposableArchitecture
import SwiftUI
import UI
import Workspace

struct SettingsSceneRoot: View {
    let store: StoreOf<WindowFeature>

    @Environment(AppSettings.self) private var appSettings

    private var theme: DevysTheme {
        DevysTheme(
            isDark: appSettings.appearance.isDarkMode,
            accentColor: AccentColor(rawValue: appSettings.appearance.accentColor) ?? .graphite
        )
    }

    private var colorScheme: ColorScheme {
        appSettings.appearance.isDarkMode ? .dark : .light
    }

    var body: some View {
        SettingsView(
            repositoryRootURL: store.selectedRepository?.rootURL,
            repositoryDisplayName: store.selectedRepository?.displayName
        )
        .frame(minWidth: 760, minHeight: 680)
        .environment(\.devysTheme, theme)
        .preferredColorScheme(colorScheme)
    }
}
