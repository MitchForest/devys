// DevysSpacing.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Spacing tokens for Devys.
///
/// Based on a 4px base unit for precise, consistent spacing.
public enum DevysSpacing {
    // MARK: - Base Unit
    
    /// The base unit (4px)
    public static let unit: CGFloat = 4
    
    // MARK: - Spacing Scale
    
    /// 0px
    public static let space0: CGFloat = 0
    
    /// 4px - Tight gaps (icon + label)
    public static let space1: CGFloat = 4
    
    /// 8px - Default element gap
    public static let space2: CGFloat = 8
    
    /// 12px - Related groups
    public static let space3: CGFloat = 12
    
    /// 16px - Section padding
    public static let space4: CGFloat = 16
    
    /// 20px - Card padding
    public static let space5: CGFloat = 20
    
    /// 24px - Large section gaps
    public static let space6: CGFloat = 24
    
    /// 32px - Page margins
    public static let space8: CGFloat = 32
    
    /// 40px - Major section breaks
    public static let space10: CGFloat = 40
    
    /// 48px - Canvas gutters
    public static let space12: CGFloat = 48
    
    /// 64px - Hero spacing
    public static let space16: CGFloat = 64
    
    // MARK: - Semantic Aliases
    
    /// Tight spacing (4px)
    public static let tight: CGFloat = space1
    
    /// Default spacing (8px)
    public static let normal: CGFloat = space2
    
    /// Comfortable spacing (12px)
    public static let comfortable: CGFloat = space3
    
    /// Relaxed spacing (16px)
    public static let relaxed: CGFloat = space4
    
    /// Spacious (24px)
    public static let spacious: CGFloat = space6
    
    // MARK: - Layout Constants
    
    /// Sidebar collapsed width (icon rail)
    public static let sidebarCollapsed: CGFloat = 48
    
    /// Sidebar expanded width
    public static let sidebarExpanded: CGFloat = 240
    
    /// Tab bar height
    public static let tabBarHeight: CGFloat = 36
    
    /// Toolbar height
    public static let toolbarHeight: CGFloat = 44
    
    /// Status bar height
    public static let statusBarHeight: CGFloat = 24
    
    /// Minimum pane width
    public static let minPaneWidth: CGFloat = 300
    
    /// Minimum pane height
    public static let minPaneHeight: CGFloat = 200
    
    // MARK: - Corner Radii
    
    /// Small radius (4px)
    public static let radiusSm: CGFloat = 4
    
    /// Medium radius (6px)
    public static let radiusMd: CGFloat = 6
    
    /// Default radius (8px)
    public static let radius: CGFloat = 8
    
    /// Large radius (12px)
    public static let radiusLg: CGFloat = 12
    
    /// Extra large radius (16px)
    public static let radiusXl: CGFloat = 16
    
    // MARK: - Icon Sizes
    
    /// Small icon (12px)
    public static let iconSm: CGFloat = 12
    
    /// Medium icon (16px)
    public static let iconMd: CGFloat = 16
    
    /// Large icon (20px)
    public static let iconLg: CGFloat = 20
    
    /// Extra large icon (24px)
    public static let iconXl: CGFloat = 24
    
    // MARK: - Border
    
    /// Standard border width
    public static let borderWidth: CGFloat = 1
}

// MARK: - EdgeInsets Helpers

public extension EdgeInsets {
    /// Uniform insets
    static func all(_ value: CGFloat) -> EdgeInsets {
        EdgeInsets(top: value, leading: value, bottom: value, trailing: value)
    }
    
    /// Horizontal insets only
    static func horizontal(_ value: CGFloat) -> EdgeInsets {
        EdgeInsets(top: 0, leading: value, bottom: 0, trailing: value)
    }
    
    /// Vertical insets only
    static func vertical(_ value: CGFloat) -> EdgeInsets {
        EdgeInsets(top: value, leading: 0, bottom: value, trailing: 0)
    }
    
    /// Asymmetric insets
    static func symmetric(horizontal h: CGFloat = 0, vertical v: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(top: v, leading: h, bottom: v, trailing: h)
    }
}
