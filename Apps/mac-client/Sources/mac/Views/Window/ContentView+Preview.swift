// ContentView+Preview.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

#Preview("Light Mode") {
    let container = AppContainer()
    return ContentView()
        .frame(width: 1200, height: 800)
        .environment(container)
        .environment(container.appSettings)
        .environment(container.recentFoldersService)
        .environment(container.layoutPersistenceService)
}

#Preview("Dark Mode") {
    struct DarkPreview: View {
        let container = AppContainer()

        var body: some View {
            ContentView()
                .frame(width: 1200, height: 800)
                .preferredColorScheme(.dark)
                .environment(container)
                .environment(container.appSettings)
                .environment(container.recentFoldersService)
                .environment(container.layoutPersistenceService)
        }
    }
    return DarkPreview()
}
