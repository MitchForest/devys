// ASCIILogo.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - ASCII Logo

/// The Devys ASCII art logo.
/// Displays in monospace font with optional glow effect.
struct ASCIILogo: View {
    @Environment(\.devysTheme) private var theme
    
    let size: Size
    let showGlow: Bool
    
    enum Size {
        case small   // Compact version
        case medium  // Standard version
        case large   // Full banner
    }
    
    init(size: Size = .large, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }
    
    var body: some View {
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
        ██████╗ ███████╗██╗   ██╗██╗   ██╗███████╗
        ██╔══██╗██╔════╝██║   ██║╚██╗ ██╔╝██╔════╝
        ██║  ██║█████╗  ██║   ██║ ╚████╔╝ ███████╗
        ██║  ██║██╔══╝  ╚██╗ ██╔╝  ╚██╔╝  ╚════██║
        ██████╔╝███████╗ ╚████╔╝    ██║   ███████║
        ╚═════╝ ╚══════╝  ╚═══╝     ╚═╝   ╚══════╝
        """
    }
    
    private var mediumLogo: String {
        """
        ╔╦╗╔═╗╦  ╦╦ ╦╔═╗
         ║║║╣ ╚╗╔╝╚╦╝╚═╗
        ═╩╝╚═╝ ╚╝  ╩ ╚═╝
        """
    }
    
    private var smallLogo: String {
        "[ DEVYS ]"
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

/// Complete logo block with tagline for welcome screens.
public struct DevysLogoBlock: View {
    @Environment(\.devysTheme) private var theme
    
    let showTypewriter: Bool
    
    public init(showTypewriter: Bool = true) {
        self.showTypewriter = showTypewriter
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            ASCIILogo(size: .large, showGlow: true)
            
            // Tagline - single line
            HStack(spacing: 0) {
                Text("the artificial intelligence development environment")
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

// MARK: - Animated Logo

/// Logo with subtle animation effects.
struct AnimatedASCIILogo: View {
    @Environment(\.devysTheme) private var theme
    @State private var glowIntensity: Double = 0.4
    
    init() {}
    
    var body: some View {
        ASCIILogo(size: .large, showGlow: false)
            .shadow(color: theme.accent.opacity(glowIntensity), radius: 8, x: 0, y: 0)
            .shadow(color: theme.accent.opacity(glowIntensity * 0.5), radius: 16, x: 0, y: 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2)
                    .repeatForever(autoreverses: true)
                ) {
                    glowIntensity = 0.6
                }
            }
    }
}

// MARK: - Previews

#Preview("ASCII Logos") {
    VStack(spacing: 40) {
        ASCIILogo(size: .large)
        ASCIILogo(size: .medium)
        ASCIILogo(size: .small)
    }
    .padding(40)
    .background(Color.black)
    .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .coral))
}

#Preview("Logo Block") {
    DevysLogoBlock()
        .padding(40)
        .background(Color.black)
        .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .coral))
}

#Preview("Animated Logo") {
    AnimatedASCIILogo()
        .padding(40)
        .background(Color.black)
        .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .cyan))
}
