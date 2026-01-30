// DevysTypography.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI
import AppKit

/// Typography tokens for Devys.
///
/// Uses SF Pro for UI, SF Mono for code.
/// Scale based on 1.25 ratio.
public enum DevysTypography {
    // MARK: - Text Sizes
    
    /// 11px - Metadata, timestamps
    public static let xs = Font.system(size: 11)
    
    /// 12px - Secondary text, labels
    public static let sm = Font.system(size: 12)
    
    /// 13px - Body text, UI elements
    public static let base = Font.system(size: 13)
    
    /// 14px - Emphasized body
    public static let md = Font.system(size: 14)
    
    /// 16px - Section headers
    public static let lg = Font.system(size: 16, weight: .medium)
    
    /// 20px - Page titles
    public static let xl = Font.system(size: 20, weight: .semibold)
    
    /// 24px - Modal titles
    public static let xxl = Font.system(size: 24, weight: .semibold)
    
    // MARK: - Semantic Fonts
    
    /// Body text
    public static let body = base
    
    /// Labels and buttons
    public static let label = Font.system(size: 13, weight: .medium)
    
    /// Headings
    public static let heading = Font.system(size: 15, weight: .semibold)
    
    /// Titles
    public static let title = Font.system(size: 18, weight: .semibold)
    
    /// Caption text
    public static let caption = Font.system(size: 11, weight: .regular)
    
    // MARK: - Monospace (Code/Terminal)
    
    /// Standard code font (13px)
    public static let mono = Font.system(size: 13, design: .monospaced)
    
    /// Small code font (11px)
    public static let monoSm = Font.system(size: 11, design: .monospaced)
    
    /// Large code font (14px)
    public static let monoLg = Font.system(size: 14, design: .monospaced)
    
    // MARK: - Line Heights
    
    /// Standard line height multiplier
    public static let lineHeight: CGFloat = 1.5
    
    /// Tight line height for UI
    public static let lineHeightTight: CGFloat = 1.25
    
    /// Relaxed line height for reading
    public static let lineHeightRelaxed: CGFloat = 1.75
}

// MARK: - Font Weights Reference
// Use SwiftUI's built-in weight modifiers:
// .fontWeight(.regular)   - 400
// .fontWeight(.medium)    - 500
// .fontWeight(.semibold)  - 600
// .fontWeight(.bold)      - 700
