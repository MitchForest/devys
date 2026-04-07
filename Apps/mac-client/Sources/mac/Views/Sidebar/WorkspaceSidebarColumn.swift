// WorkspaceSidebarColumn.swift
// Devys - Workspace-scoped sidebar container.
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import UI

struct WorkspaceSidebarColumn<Content: View>: View {
    @Environment(\.devysTheme) private var theme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface)
    }
}
