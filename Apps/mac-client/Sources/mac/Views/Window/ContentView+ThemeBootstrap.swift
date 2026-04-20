// ContentView+ThemeBootstrap.swift
// Initial appearance bootstrap for themed shell surfaces.
//
// Copyright © 2026 Devys. All rights reserved.

import AppFeatures
import ComposableArchitecture
import Split
import SwiftUI
import UI
import Workspace

@MainActor
extension ContentView {
    static func makeSplitColors(from theme: DevysTheme) -> DevysSplitConfiguration.Colors {
        DevysSplitConfiguration.Colors(
            accent: theme.accent,
            tabBarBackground: theme.card,
            activeTabBackground: theme.base,
            inactiveText: theme.textSecondary,
            activeText: theme.text,
            separator: theme.border,
            contentBackground: theme.card,
            baseBackground: theme.base,
            paneCornerRadius: Spacing.radius,
            paneGap: Spacing.paneGap
        )
    }
}
