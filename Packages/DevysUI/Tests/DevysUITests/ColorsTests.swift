// ColorsTests.swift
// DevysUI Tests
//
// Copyright © 2026 Devys. All rights reserved.

import Testing
import SwiftUI
@testable import DevysUI

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
        
        // Accent colors
        _ = DevysColors.primary
        _ = DevysColors.secondary
        _ = DevysColors.warning
        _ = DevysColors.error
        
        // Text colors
        _ = DevysColors.textPrimary
        _ = DevysColors.textSecondary
        _ = DevysColors.textTertiary
        
        // Status colors
        _ = DevysColors.statusRunning
        _ = DevysColors.statusPending
        _ = DevysColors.statusComplete
        _ = DevysColors.statusError
    }
    
    @Test("Icon color mapping works")
    func iconColorMapping() {
        let orange = DevysColors.color(for: .orange)
        let blue = DevysColors.color(for: .blue)
        let tertiary = DevysColors.color(for: .tertiary)
        
        _ = orange
        _ = blue
        _ = tertiary
    }
}

@Suite("DevysSpacing Tests")
struct SpacingTests {
    @Test("Spacing values follow 8px grid")
    func spacingGrid() {
        #expect(DevysSpacing.xs == 8)
        #expect(DevysSpacing.md == 16)
        #expect(DevysSpacing.lg == 24)
        #expect(DevysSpacing.xl == 32)
    }
    
    @Test("Corner radii are defined")
    func cornerRadii() {
        #expect(DevysSpacing.cornerRadiusSm == 4)
        #expect(DevysSpacing.cornerRadiusMd == 6)
        #expect(DevysSpacing.cornerRadiusLg == 8)
    }
}
