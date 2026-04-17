import AppFeatures
import ComposableArchitecture
import SwiftUI
import UI
import Workspace

struct SettingsSceneRoot: View {
    let store: StoreOf<WindowFeature>

    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(AppSettings.self) private var appSettings

    private var theme: DevysTheme {
        DevysTheme(
            isDark: appSettings.appearance.mode.resolvedColorScheme(systemColorScheme: systemColorScheme) == .dark,
            accentColor: AccentColor(rawValue: appSettings.appearance.accentColor) ?? .graphite
        )
    }

    var body: some View {
        SettingsView(
            repositoryRootURL: store.selectedRepository?.rootURL,
            repositoryDisplayName: store.selectedRepository?.displayName
        )
        .frame(minWidth: 760, minHeight: 680)
        .environment(\.devysTheme, theme)
        .preferredColorScheme(appSettings.appearance.mode.preferredColorScheme)
    }
}
