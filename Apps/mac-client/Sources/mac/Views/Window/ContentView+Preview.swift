// ContentView+Preview.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import ComposableArchitecture
import SwiftUI

@MainActor
private struct ContentViewPreviewHost: View {
    let preferredColorScheme: ColorScheme?

    private let container = AppContainer()
    private let store = Store(initialState: WindowFeature.State()) {
        WindowFeature()
    }

    var body: some View {
        ContentView(store: store)
            .frame(width: 1200, height: 800)
            .preferredColorScheme(preferredColorScheme)
            .environment(container)
            .environment(container.appSettings)
            .environment(container.recentRepositoriesService)
            .environment(container.layoutPersistenceService)
            .environment(container.repositorySettingsStore)
    }
}

#Preview("Light Mode") {
    ContentViewPreviewHost(preferredColorScheme: nil)
}

#Preview("Dark Mode") {
    ContentViewPreviewHost(preferredColorScheme: .dark)
}
