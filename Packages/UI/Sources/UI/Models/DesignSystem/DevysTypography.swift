// DevysTypography.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Typography tokens for Devys.
///
/// Terminal-first: ALL text uses monospace for consistency.
/// This creates the authentic developer/hacker aesthetic.
public enum DevysTypography {
    
    // MARK: - Font Family
    
    /// Primary monospace font - SF Mono (system) for reliability
    /// Could be swapped for JetBrains Mono, Fira Code, etc.
    public static let fontDesign: Font.Design = .monospaced
    
    // MARK: - Size Scale (Monospace)
    
    /// 10px - Micro text (timestamps, metadata)
    public static let micro = Font.system(size: 10, design: fontDesign)
    
    /// 11px - Extra small (labels, hints)
    public static let xs = Font.system(size: 11, design: fontDesign)
    
    /// 12px - Small (secondary text)
    public static let sm = Font.system(size: 12, design: fontDesign)
    
    /// 13px - Base (body text, UI elements)
    public static let base = Font.system(size: 13, design: fontDesign)
    
    /// 14px - Medium (emphasized text)
    public static let md = Font.system(size: 14, design: fontDesign)
    
    /// 16px - Large (section headers)
    public static let lg = Font.system(size: 16, weight: .medium, design: fontDesign)
    
    /// 20px - Extra large (page titles)
    public static let xl = Font.system(size: 20, weight: .semibold, design: fontDesign)
    
    /// 24px - Hero (welcome screens, modals)
    public static let xxl = Font.system(size: 24, weight: .semibold, design: fontDesign)
    
    /// 32px - Display (ASCII art, logos)
    public static let display = Font.system(size: 32, weight: .bold, design: fontDesign)
    
    // MARK: - Semantic Fonts
    
    /// Body text - standard readable size
    public static let body = base
    
    /// Labels and buttons - slightly emphasized
    public static let label = Font.system(size: 13, weight: .medium, design: fontDesign)
    
    /// Section headings - ALL CAPS style
    public static let heading = Font.system(size: 11, weight: .semibold, design: fontDesign)
    
    /// Page titles
    public static let title = Font.system(size: 18, weight: .semibold, design: fontDesign)
    
    /// Caption text - smallest readable
    public static let caption = Font.system(size: 11, weight: .regular, design: fontDesign)
    
    /// Code/Terminal - same as base (everything is mono!)
    public static let mono = base
    public static let monoSm = sm
    public static let monoLg = md
    
    // MARK: - Line Heights
    
    /// Standard line height multiplier
    public static let lineHeight: CGFloat = 1.5
    
    /// Tight line height for UI elements
    public static let lineHeightTight: CGFloat = 1.25
    
    /// Relaxed line height for reading
    public static let lineHeightRelaxed: CGFloat = 1.75
    
    // MARK: - Letter Spacing
    
    /// Header letter spacing (for ALL_CAPS headers)
    public static let headerTracking: CGFloat = 1.5
    
    /// Normal letter spacing
    public static let normalTracking: CGFloat = 0
}
// MARK: - Font Weights Reference
// Use SwiftUI's built-in weight modifiers:
// .fontWeight(.regular)   - 400
// .fontWeight(.medium)    - 500
// .fontWeight(.semibold)  - 600
// .fontWeight(.bold)      - 700
