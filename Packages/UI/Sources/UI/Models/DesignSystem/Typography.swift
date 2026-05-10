// Typography.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Typography tokens.
///
/// Two font families:
/// - **UI chrome**: SF Pro (proportional) — tabs, labels, menus, buttons, headers
/// - **Code**: SF Mono (monospace) — editor, terminal, inline code, diffs
///
/// Seven UI sizes. Four code sizes. Four chat sizes.
/// Never use a size between these stops.
public enum Typography {

    // MARK: - UI Chrome (Proportional)

    /// 24pt bold — welcome screen hero, empty state titles
    public static let display = Font.system(size: 24, weight: .bold, design: .default)

    /// 18pt semibold — page titles, modal titles, settings headers
    public static let title = Font.system(size: 18, weight: .semibold, design: .default)

    /// 14pt semibold — section headers, sidebar section titles, panel titles
    public static let heading = Font.system(size: 14, weight: .semibold, design: .default)

    /// 13pt regular — primary UI text, menus, descriptions, file names
    public static let body = Font.system(size: 13, weight: .regular, design: .default)

    /// 12pt medium — button labels, tab titles, chip text, nav items
    public static let label = Font.system(size: 12, weight: .medium, design: .default)

    /// 11pt regular — timestamps, metadata, secondary descriptions
    public static let caption = Font.system(size: 11, weight: .regular, design: .default)

    /// 10pt medium — badge counts, keyboard shortcut text
    public static let micro = Font.system(size: 10, weight: .medium, design: .default)

    // MARK: - Code (Monospace)

    public enum Code {
        /// 13pt — default editor text
        public static let base = Font.system(size: 13, weight: .regular, design: .monospaced)

        /// 12pt — inline code in chat, terminal compact
        public static let sm = Font.system(size: 12, weight: .regular, design: .monospaced)

        /// 14pt — focused reading mode
        public static let lg = Font.system(size: 14, weight: .regular, design: .monospaced)

        /// 11pt — line numbers, gutter annotations
        public static let gutter = Font.system(size: 11, weight: .regular, design: .monospaced)
    }

    // MARK: - Chat (Proportional, Slightly Larger)

    public enum Chat {
        /// 15pt — message body text
        public static let body = Font.system(size: 15, weight: .regular, design: .default)

        /// 17pt semibold — message section headers
        public static let heading = Font.system(size: 17, weight: .semibold, design: .default)

        /// 12pt — timestamps, metadata
        public static let caption = Font.system(size: 12, weight: .regular, design: .default)

        /// 14pt mono — code blocks in chat
        public static let code = Font.system(size: 14, weight: .regular, design: .monospaced)
    }

    // MARK: - Line Heights

    public static let lineHeight: CGFloat = 1.5
    public static let lineHeightTight: CGFloat = 1.25
    public static let lineHeightRelaxed: CGFloat = 1.75

    // MARK: - Letter Spacing

    public static let headerTracking: CGFloat = 0.3
    public static let normalTracking: CGFloat = 0
}
