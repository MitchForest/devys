// ContentView+Preview.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import ComposableArchitecture
import SwiftUI

#Preview("Light Mode") {
    let container = AppContainer()
    let store = Store(initialState: WindowFeature.State()) {
        WindowFeature()
    }

    return ContentView(store: store)
        .frame(width: 1200, height: 800)
        .environment(container)
        .environment(container.appSettings)
        .environment(container.recentRepositoriesService)
        .environment(container.layoutPersistenceService)
        .environment(container.repositorySettingsStore)
}

#Preview("Dark Mode") {
    struct DarkPreview: View {
        let container = AppContainer()
        let store = Store(initialState: WindowFeature.State()) {
            WindowFeature()
        }

        var body: some View {
            ContentView(store: store)
                .frame(width: 1200, height: 800)
                .preferredColorScheme(.dark)
                .environment(container)
                .environment(container.appSettings)
                .environment(container.recentRepositoriesService)
                .environment(container.layoutPersistenceService)
                .environment(container.repositorySettingsStore)
        }
    }
    return DarkPreview()
}
