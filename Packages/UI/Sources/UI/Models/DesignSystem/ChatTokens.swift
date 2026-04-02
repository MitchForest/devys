// ChatTokens.swift
// DevysUI - Chat-specific design tokens
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Chat-specific design tokens for iMessage-quality conversation UI.
///
/// Chat surfaces use the system font (`.default`) for readability, while
/// code blocks and metadata retain the monospace design.
public enum ChatTokens {

    // MARK: - Typography (System Font for Chat)

    /// Chat body text — 16pt system default, optimized for reading
    public static let body = Font.system(size: 16, weight: .regular, design: .default)

    /// Chat body bold — for unread previews, emphasis
    public static let bodyBold = Font.system(size: 16, weight: .semibold, design: .default)

    /// Chat secondary — 14pt for metadata, previews
    public static let secondary = Font.system(size: 14, weight: .regular, design: .default)

    /// Chat caption — 12pt for timestamps, status labels
    public static let caption = Font.system(size: 12, weight: .regular, design: .default)

    /// Chat caption bold — 12pt semibold for badges, counts
    public static let captionBold = Font.system(size: 12, weight: .semibold, design: .default)

    /// Chat micro — 11pt for fine metadata
    public static let micro = Font.system(size: 11, weight: .regular, design: .default)

    /// Chat title — 17pt semibold for session titles
    public static let title = Font.system(size: 17, weight: .semibold, design: .default)

    /// Chat heading — 20pt bold for section/page headings
    public static let heading = Font.system(size: 20, weight: .bold, design: .default)

    /// Code in chat — 14pt monospace for inline code
    public static let code = Font.system(size: 14, weight: .regular, design: .monospaced)

    /// Code small — 12pt monospace for block metadata
    public static let codeSm = Font.system(size: 12, weight: .regular, design: .monospaced)

    // MARK: - Bubble Geometry

    /// Corner radius for message bubbles (18pt for pill-like feel)
    public static let bubbleRadius: CGFloat = 18

    /// Corner radius for grouped/continuation bubbles (smaller)
    public static let bubbleRadiusSm: CGFloat = 6

    /// Bubble horizontal padding
    public static let bubblePaddingH: CGFloat = 14

    /// Bubble vertical padding
    public static let bubblePaddingV: CGFloat = 10

    /// Maximum bubble width as fraction of screen
    public static let bubbleMaxWidthFraction: CGFloat = 0.78

    /// Spacing between consecutive same-role messages
    public static let groupedSpacing: CGFloat = 2

    /// Spacing between different-role message groups
    public static let groupBreakSpacing: CGFloat = 12

    /// Spacing for timestamp separators
    public static let timestampSpacing: CGFloat = 24

    // MARK: - Bubble Colors

    /// User bubble background — iOS-style blue
    public static let userBubble = Color(hex: "#0A84FF")

    /// User bubble text — white on blue
    public static let userBubbleText = Color.white

    /// Assistant bubble background (dark mode)
    public static let assistantBubbleDark = Color(hex: "#1C1C1E")

    /// Assistant bubble background (light mode)
    public static let assistantBubbleLight = Color(hex: "#E9E9EB")

    /// System message background
    public static let systemPill = Color(hex: "#2C2C2E")

    /// System message text
    public static let systemPillText = Color(hex: "#8E8E93")

    // MARK: - Session Row

    /// Row height minimum for comfortable touch targets
    public static let sessionRowMinHeight: CGFloat = 72

    /// Avatar circle size
    public static let avatarSize: CGFloat = 48

    /// Avatar corner radius (half of size for circle)
    public static let avatarRadius: CGFloat = 24

    /// Unread badge size
    public static let badgeSize: CGFloat = 20

    // MARK: - Composer

    /// Composer background corner radius (capsule)
    public static let composerRadius: CGFloat = 20

    /// Composer minimum height
    public static let composerMinHeight: CGFloat = 36

    /// Send button size
    public static let sendButtonSize: CGFloat = 30

    // MARK: - Typing Indicator

    /// Dot size for typing indicator
    public static let typingDotSize: CGFloat = 7

    /// Spacing between typing dots
    public static let typingDotSpacing: CGFloat = 4
}
