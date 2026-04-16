// ChatTokens.swift
// Devys Design System — Chat-specific geometry tokens
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Chat-specific design tokens.
///
/// Typography lives in `Typography.Chat`. Colors come from `Theme`.
/// This file only holds geometry/layout values specific to chat UI.
public enum ChatTokens {

    // MARK: - Bubble Geometry

    /// Chat bubbles use the standard radius.
    public static let bubbleRadius: CGFloat = Spacing.radius
    public static let bubblePaddingH: CGFloat = 14
    public static let bubblePaddingV: CGFloat = 10
    public static let bubbleMaxWidthFraction: CGFloat = 0.78
    public static let groupedSpacing: CGFloat = 2
    public static let groupBreakSpacing: CGFloat = 12
    public static let timestampSpacing: CGFloat = 24

    // MARK: - Session Row

    public static let sessionRowMinHeight: CGFloat = 72
    public static let avatarSize: CGFloat = 48
    public static let avatarRadius: CGFloat = Spacing.radiusFull
    public static let badgeSize: CGFloat = 20

    // MARK: - Composer

    /// Composer uses the standard radius.
    public static let composerRadius: CGFloat = Spacing.radius
    public static let composerMinHeight: CGFloat = 36
    public static let sendButtonSize: CGFloat = 30

    // MARK: - Typing Indicator

    public static let typingDotSize: CGFloat = 7
    public static let typingDotSpacing: CGFloat = 4

}
