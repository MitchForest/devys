// DevysColors.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// The Devys color palette.
///
/// A calm, monochrome-first palette with surgical accent use.
/// Colors create depth through background levels, not shadows.
public enum DevysColors {
    // MARK: - Background Levels (Depth System)
    
    /// Level 0: Deepest background (canvas, terminal)
    public static let bg0 = Color(hex: "#0D0D0D")
    
    /// Level 1: Pane backgrounds
    public static let bg1 = Color(hex: "#141414")
    
    /// Level 2: Elevated surfaces (cards, popovers)
    public static let bg2 = Color(hex: "#1A1A1A")
    
    /// Level 3: Hover states
    public static let bg3 = Color(hex: "#242424")
    
    /// Level 4: Active/selected states
    public static let bg4 = Color(hex: "#2A2A2A")
    
    // MARK: - Borders
    
    /// Subtle border (barely visible separation)
    public static let borderSubtle = Color(hex: "#1F1F1F")
    
    /// Default border
    public static let border = Color(hex: "#2A2A2A")
    
    /// Strong border (rare, for emphasis)
    public static let borderStrong = Color(hex: "#3A3A3A")
    
    // MARK: - Text
    
    /// Primary text (95% white)
    public static let text = Color(hex: "#EFEFEF")
    
    /// Secondary text (descriptions, metadata)
    public static let textSecondary = Color(hex: "#888888")
    
    /// Tertiary text (placeholders, disabled)
    public static let textTertiary = Color(hex: "#555555")
    
    /// Inverted text (on light backgrounds)
    public static let textInverted = Color(hex: "#0D0D0D")
    
    // MARK: - Accent (Use Sparingly)
    
    /// Primary accent: Indigo (focus rings, primary actions only)
    public static let accent = Color(hex: "#6366F1")
    
    /// Accent hover state
    public static let accentHover = Color(hex: "#818CF8")
    
    /// Accent muted (for subtle highlights)
    public static let accentMuted = Color(hex: "#6366F1").opacity(0.15)
    
    // MARK: - Semantic (Status Only)
    
    /// Success (explicit success states only)
    public static let success = Color(hex: "#22C55E")
    
    /// Warning (caution states)
    public static let warning = Color(hex: "#F59E0B")
    
    /// Error (errors only)
    public static let error = Color(hex: "#EF4444")
    
    /// Info (links, informational)
    public static let info = Color(hex: "#3B82F6")
    
    // MARK: - Legacy Compatibility
    
    /// Alias for bg0
    public static let base = bg0
    
    /// Alias for bg1
    public static let surface = bg1
    
    /// Alias for bg2
    public static let elevated = bg2
    
    /// Alias for accent
    public static let primary = accent
    
    /// Alias for info
    public static let secondary = info
    
    /// Alias for text
    public static let textPrimary = text
}

// MARK: - Color Extension

extension Color {
    /// Initialize a Color from a hex string.
    /// - Parameter hex: Hex string (with or without #)
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
