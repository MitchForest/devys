// TerminalEffects.swift
// MetalASCII - Terminal UI components for ASCII art
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import SwiftUI

// MARK: - Blinking Cursor

/// A terminal-style blinking cursor.
public struct BlinkingCursor: View {
    @State private var isVisible = true

    let color: Color
    let width: CGFloat
    let height: CGFloat

    public init(
        color: Color = .white,
        width: CGFloat = 2,
        height: CGFloat = 16
    ) {
        self.color = color
        self.width = width
        self.height = height
    }

    public var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: height)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                ) {
                    isVisible = false
                }
            }
    }
}

// MARK: - Typewriter Text

/// Text that types out character by character like a terminal.
public struct TypewriterText: View {
    let text: String
    let speed: TimeInterval
    let showCursor: Bool
    let cursorColor: Color

    @State private var displayedText = ""
    @State private var isComplete = false

    public init(
        _ text: String,
        speed: TimeInterval = 0.05,
        showCursor: Bool = true,
        cursorColor: Color = .white
    ) {
        self.text = text
        self.speed = speed
        self.showCursor = showCursor
        self.cursorColor = cursorColor
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(displayedText)
                .font(DevysTypography.base)

            if showCursor {
                BlinkingCursor(
                    color: cursorColor,
                    width: 1,
                    height: 14
                )
                .opacity(isComplete ? 1 : 0)
            }
        }
        .onAppear {
            animateText()
        }
    }

    private func animateText() {
        displayedText = ""
        isComplete = false

        for (index, character) in text.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + speed * Double(index)) {
                displayedText.append(character)

                if displayedText.count == text.count {
                    isComplete = true
                }
            }
        }
    }
}

// MARK: - Terminal Glow

/// Adds a subtle glow effect for terminal-style emphasis.
public struct TerminalGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    public init(color: Color = .white, radius: CGFloat = 4) {
        self.color = color
        self.radius = radius
    }

    public func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.3), radius: radius / 2, x: 0, y: 0)
            .shadow(color: color.opacity(0.15), radius: radius, x: 0, y: 0)
    }
}

public extension View {
    /// Adds a subtle terminal-style glow effect.
    func terminalGlow(color: Color = .white, radius: CGFloat = 4) -> some View {
        modifier(TerminalGlow(color: color, radius: radius))
    }
}

// MARK: - Section Divider

/// A horizontal divider with terminal aesthetic.
public struct TerminalDivider: View {
    @Environment(\.devysTheme) private var theme

    let useDashes: Bool

    public init(useDashes: Bool = false) {
        self.useDashes = useDashes
    }

    public var body: some View {
        if useDashes {
            Text(String(repeating: "─", count: 60))
                .font(DevysTypography.xs)
                .foregroundStyle(theme.borderSubtle)
                .lineLimit(1)
        } else {
            Rectangle()
                .fill(theme.borderSubtle)
                .frame(height: 1)
        }
    }
}

// MARK: - Scanline Overlay

/// Subtle CRT-style scanlines for retro effect.
public struct ScanlineOverlay: View {
    let opacity: Double
    let spacing: CGFloat

    public init(opacity: Double = 0.02, spacing: CGFloat = 2) {
        self.opacity = opacity
        self.spacing = spacing
    }

    public var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                for y in stride(from: 0, to: size.height, by: spacing) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    context.fill(Path(rect), with: .color(.black.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#endif // os(macOS)
