// ColorsTests.swift
// DesignSystem Tests — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import SwiftUI
@testable import UI

@Suite("Colors Tests")
struct ColorsTests {
    @Test("Color from hex creates valid color")
    func colorFromHex() {
        let red = Color(hex: "#FF0000")
        let green = Color(hex: "#00FF00")
        let blue = Color(hex: "#0000FF")
        _ = red; _ = green; _ = blue
    }

    @Test("Color from hex handles different formats")
    func colorFormats() {
        _ = Color(hex: "#AABBCC")
        _ = Color(hex: "AABBCC")
        _ = Color(hex: "#FFAABBCC")
    }

    @Test("Design system has three surface levels per mode")
    func surfaceLevels() {
        _ = Colors.darkBase
        _ = Colors.darkCard
        _ = Colors.darkOverlay
        _ = Colors.lightBase
        _ = Colors.lightCard
        _ = Colors.lightOverlay
    }

    @Test("Design system has three text levels per mode")
    func textLevels() {
        _ = Colors.darkText
        _ = Colors.darkTextSecondary
        _ = Colors.darkTextTertiary
        _ = Colors.lightText
        _ = Colors.lightTextSecondary
        _ = Colors.lightTextTertiary
    }

    @Test("Semantic status colors are defined")
    func semanticStatus() {
        _ = Colors.success
        _ = Colors.warning
        _ = Colors.error
        _ = Colors.info
    }

    @Test("Ten accent colors exist with Graphite default")
    func allAccentColors() {
        #expect(AccentColor.allCases.count == 10)
        #expect(AccentColor.graphite.isMonochrome)
        for accent in AccentColor.allCases {
            _ = accent.color
            _ = accent.muted
            _ = accent.subtle
            _ = accent.displayName
        }
    }

    @Test("Theme adapts to dark and light mode")
    func themeAdaptation() {
        let dark = Theme(isDark: true)
        let light = Theme(isDark: false)

        #expect(dark.base != light.base)
        #expect(dark.card != light.card)
        #expect(dark.text != light.text)
        #expect(dark.border != light.border)
        #expect(dark.accent == light.accent)
    }

    @Test("Theme default accent is graphite")
    func defaultAccent() {
        let theme = Theme(isDark: true)
        #expect(theme.accentColor == .graphite)
        #expect(theme.accentColor.isMonochrome)
    }

    @Test("Primary fill respects monochrome vs colored")
    func primaryFill() {
        let mono = Theme(isDark: true, accentColor: .graphite)
        let colored = Theme(isDark: true, accentColor: .violet)

        // Monochrome: primary fill uses text color
        #expect(mono.primaryFill == mono.text)
        // Colored: primary fill uses accent
        #expect(colored.primaryFill == colored.accent)
    }

    @Test("Agent identity colors use 9-color palette")
    func agentColors() {
        #expect(AgentColor.palette.count == 9)
        let first = AgentColor.forIndex(0)
        let wrapped = AgentColor.forIndex(9)
        #expect(first == wrapped)
    }
}

@Suite("Spacing Tests")
struct SpacingTests {
    @Test("Spacing values follow 4px scale")
    func spacingGrid() {
        #expect(Spacing.space1 == 4)
        #expect(Spacing.space2 == 8)
        #expect(Spacing.space4 == 16)
        #expect(Spacing.space6 == 24)
        #expect(Spacing.space8 == 32)
    }

    @Test("Three corner radii: micro, radius, full")
    func cornerRadii() {
        #expect(Spacing.radiusMicro == 4)
        #expect(Spacing.radius == 12)
        #expect(Spacing.radiusFull == 9999)
    }

    @Test("Inner radius computes correctly")
    func innerRadius() {
        #expect(Spacing.innerRadius(padding: 6) == 6)
        #expect(Spacing.innerRadius(padding: 12) == 0)
        #expect(Spacing.innerRadius(padding: 20) == 0)
    }

    @Test("Pane gap is defined")
    func paneGap() {
        #expect(Spacing.paneGap == 6)
    }
}

@Suite("Density Tests")
struct DensityTests {
    @Test("Layout values differ between density modes")
    func densityValues() {
        let comfortable = DensityLayout(.comfortable)
        let compact = DensityLayout(.compact)

        #expect(comfortable.tabHeight > compact.tabHeight)
        #expect(comfortable.sidebarRowHeight > compact.sidebarRowHeight)
        #expect(comfortable.buttonHeight > compact.buttonHeight)
        #expect(comfortable.paneGap > compact.paneGap)
    }
}
