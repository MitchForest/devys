// Spacing.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Spacing tokens.
///
/// 4px base unit. One corner radius for everything (12pt).
/// Continuous curvature (squircle) on all rounded corners.
public enum Spacing {

    // MARK: - Base Unit

    public static let unit: CGFloat = 4

    // MARK: - Scale

    public static let space0: CGFloat = 0
    public static let space1: CGFloat = 4
    public static let space2: CGFloat = 8
    public static let space3: CGFloat = 12
    public static let space4: CGFloat = 16
    public static let space5: CGFloat = 20
    public static let space6: CGFloat = 24
    public static let space8: CGFloat = 32
    public static let space12: CGFloat = 48

    // MARK: - Semantic Aliases

    public static let tight: CGFloat = space1
    public static let normal: CGFloat = space2
    public static let comfortable: CGFloat = space3
    public static let relaxed: CGFloat = space4
    public static let spacious: CGFloat = space6

    // MARK: - Corner Radii

    /// 12pt — the one radius. Buttons, inputs, cards, tabs, dropdowns,
    /// modals, popovers, chips, badges, code blocks. Everything.
    public static let radius: CGFloat = 12

    /// 4pt — tiny inline elements: checkbox corners, inline code spans,
    /// progress bar tracks.
    public static let radiusMicro: CGFloat = 4

    /// Full circle — status dots, avatars, toggle tracks, status capsule.
    public static let radiusFull: CGFloat = 9999

    /// Computes the inner radius for nested rounded rectangles.
    /// Rule: inner = outer − padding. Minimum 0.
    public static func innerRadius(padding: CGFloat) -> CGFloat {
        max(radius - padding, 0)
    }

    // MARK: - Pane Gap

    /// Gap between split-pane cards. Base surface visible in the gap.
    public static let paneGap: CGFloat = 6

    // MARK: - Icon Sizes

    public static let iconSm: CGFloat = 12
    public static let iconMd: CGFloat = 16
    public static let iconLg: CGFloat = 20
    public static let iconXl: CGFloat = 24

    // MARK: - Border

    public static let borderWidth: CGFloat = 1

    // MARK: - Layout Constants

    public static let repoRailWidth: CGFloat = 48
    public static let sidebarDefaultWidth: CGFloat = 260
    public static let sidebarMinWidth: CGFloat = 180
    public static let sidebarMaxWidth: CGFloat = 400
    public static let minPaneWidth: CGFloat = 200
    public static let minPaneHeight: CGFloat = 200

    // MARK: - Tab Bar

    public static let tabBarHeight: CGFloat = 36
    public static let tabMinWidth: CGFloat = 120
    public static let tabMaxWidth: CGFloat = 200

    // MARK: - Status Capsule

    public static let capsuleMinWidth: CGFloat = 140

}
