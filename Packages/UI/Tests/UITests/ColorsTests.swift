// ColorsTests.swift
// DevysUI Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import SwiftUI
@testable import UI

@Suite("DevysColors Tests")
struct ColorsTests {
    @Test("Color from hex creates valid color")
    func colorFromHex() {
        let red = Color(hex: "#FF0000")
        let green = Color(hex: "#00FF00")
        let blue = Color(hex: "#0000FF")
        
        // Colors should be created without crashing
        _ = red
        _ = green
        _ = blue
    }
    
    @Test("Color from hex handles different formats")
    func colorFormats() {
        // With hash
        _ = Color(hex: "#AABBCC")
        
        // Without hash
        _ = Color(hex: "AABBCC")
        
        // With alpha
        _ = Color(hex: "#FFAABBCC")
    }
    
    @Test("Design system colors are defined")
    func designSystemColors() {
        // Background colors
        _ = DevysColors.base
        _ = DevysColors.surface
        _ = DevysColors.elevated
        _ = DevysColors.border
        
        // Semantic colors
        _ = DevysColors.success
        _ = DevysColors.warning
        _ = DevysColors.error
        
        // Text colors
        _ = DevysColors.textPrimary
        _ = DevysColors.textSecondary
        _ = DevysColors.textTertiary
        
        // Theme colors
        _ = DevysColors.darkBg0
        _ = DevysColors.lightBg0
    }
    
    @Test("Accent color variants are available")
    func accentColorVariants() {
        let accent = AccentColor.cyan
        _ = accent.color
        _ = accent.hover
        _ = accent.muted
    }
}

@Suite("DevysSpacing Tests")
struct SpacingTests {
    @Test("Spacing values follow scale")
    func spacingGrid() {
        #expect(DevysSpacing.space2 == 8)
        #expect(DevysSpacing.space4 == 16)
        #expect(DevysSpacing.space6 == 24)
        #expect(DevysSpacing.space8 == 32)
    }
    
    @Test("Corner radii are defined")
    func cornerRadii() {
        #expect(DevysSpacing.radiusSm == 4)
        #expect(DevysSpacing.radiusMd == 6)
        #expect(DevysSpacing.radius == 8)
    }
}
