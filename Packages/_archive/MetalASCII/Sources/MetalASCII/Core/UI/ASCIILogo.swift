// ASCIILogo.swift
// MetalASCII - ASCII text logos
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import SwiftUI

// MARK: - ASCII Logo

/// ASCII art logo display.
public struct ASCIILogo: View {
    @Environment(\.devysTheme) private var theme

    let size: Size
    let showGlow: Bool

    public enum Size {
        case small   // Compact version
        case medium  // Standard version
        case large   // Full banner
    }

    public init(size: Size = .large, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }

    public var body: some View {
        Text(logoText)
            .font(fontSize)
            .fontDesign(.monospaced)
            .foregroundStyle(theme.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: true, vertical: true)
            .modifier(ConditionalGlow(isEnabled: showGlow, color: theme.accent))
    }

    private var logoText: String {
        switch size {
        case .small:
            return smallLogo
        case .medium:
            return mediumLogo
        case .large:
            return largeLogo
        }
    }

    private var fontSize: Font {
        switch size {
        case .small:
            return .system(size: 10, design: .monospaced)
        case .medium:
            return .system(size: 12, design: .monospaced)
        case .large:
            return .system(size: 14, design: .monospaced)
        }
    }

    // MARK: - Logo Variants

    private var largeLogo: String {
        """
        ███╗   ███╗███████╗████████╗ █████╗ ██╗
        ████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██║
        ██╔████╔██║█████╗     ██║   ███████║██║
        ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║
        ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗
        ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝
                    █████╗ ███████╗ ██████╗██╗██╗
                   ██╔══██╗██╔════╝██╔════╝██║██║
                   ███████║███████╗██║     ██║██║
                   ██╔══██║╚════██║██║     ██║██║
                   ██║  ██║███████║╚██████╗██║██║
                   ╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝╚═╝
        """
    }

    private var mediumLogo: String {
        """
        ╔╦╗╔═╗╔╦╗╔═╗╦    ╔═╗╔═╗╔═╗╦╦
        ║║║║╣  ║ ╠═╣║    ╠═╣╚═╗║  ║║
        ╩ ╩╚═╝ ╩ ╩ ╩╩═╝  ╩ ╩╚═╝╚═╝╩╩
        """
    }

    private var smallLogo: String {
        "[ METAL ASCII ]"
    }
}

// MARK: - Conditional Glow Modifier

private struct ConditionalGlow: ViewModifier {
    let isEnabled: Bool
    let color: Color

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 0)
                .shadow(color: color.opacity(0.2), radius: 16, x: 0, y: 0)
        } else {
            content
        }
    }
}

// MARK: - Logo with Tagline

/// Complete logo block with tagline.
public struct ASCIILogoBlock: View {
    @Environment(\.devysTheme) private var theme

    let showTypewriter: Bool

    public init(showTypewriter: Bool = true) {
        self.showTypewriter = showTypewriter
    }

    public var body: some View {
        VStack(spacing: 16) {
            ASCIILogo(size: .large, showGlow: true)

            HStack(spacing: 0) {
                Text("gpu-accelerated ascii art with dithering")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()

                if showTypewriter {
                    BlinkingCursor(
                        color: theme.accent,
                        width: 1,
                        height: 10
                    )
                    .padding(.leading, 2)
                }
            }
        }
    }
}

#endif // os(macOS)
