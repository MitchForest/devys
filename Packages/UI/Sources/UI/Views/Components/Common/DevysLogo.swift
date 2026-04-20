// DevysLogo.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// The Devys ASCII banner, rendered in monospace using theme text colors.
///
/// Used on the welcome screen and other hero surfaces. Stateless and
/// theme-driven — no glow, no color, monochrome by default.
public struct DevysLogo: View {
    @Environment(\.theme) private var theme

    public enum Size: Sendable {
        case small
        case medium
        case large
    }

    private let size: Size
    private let tagline: String?

    public init(size: Size = .large, tagline: String? = nil) {
        self.size = size
        self.tagline = tagline
    }

    public var body: some View {
        VStack(spacing: Spacing.space4) {
            Text(logoText)
                .font(.system(size: glyphSize, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: true, vertical: true)
                .tracking(0.5)

            if let tagline {
                Text(tagline)
                    .font(Typography.caption)
                    .foregroundStyle(theme.textTertiary)
                    .textCase(.lowercase)
                    .tracking(Typography.headerTracking)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var logoText: String {
        switch size {
        case .small: Self.smallBanner
        case .medium: Self.mediumBanner
        case .large: Self.largeBanner
        }
    }

    private var glyphSize: CGFloat {
        switch size {
        case .small: 10
        case .medium: 12
        case .large: 14
        }
    }

    private var accessibilityLabel: String {
        tagline.map { "Devys. \($0)" } ?? "Devys"
    }

    private static let largeBanner = """
    ██████╗ ███████╗██╗   ██╗██╗   ██╗███████╗
    ██╔══██╗██╔════╝██║   ██║╚██╗ ██╔╝██╔════╝
    ██║  ██║█████╗  ██║   ██║ ╚████╔╝ ███████╗
    ██║  ██║██╔══╝  ╚██╗ ██╔╝  ╚██╔╝  ╚════██║
    ██████╔╝███████╗ ╚████╔╝    ██║   ███████║
    ╚═════╝ ╚══════╝  ╚═══╝     ╚═╝   ╚══════╝
    """

    private static let mediumBanner = """
    ╔╦╗╔═╗╦  ╦╦ ╦╔═╗
     ║║║╣ ╚╗╔╝╚╦╝╚═╗
    ═╩╝╚═╝ ╚╝  ╩ ╚═╝
    """

    private static let smallBanner = "[ DEVYS ]"
}

// MARK: - Previews

#Preview("Logo Sizes") {
    VStack(spacing: Spacing.space8) {
        DevysLogo(size: .large, tagline: "the ai-native development environment")
        DevysLogo(size: .medium)
        DevysLogo(size: .small)
    }
    .padding(Spacing.space8)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
