// TerminalEffects.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

// MARK: - Blinking Cursor

/// A terminal-style blinking cursor.
/// Use after text inputs or to indicate active state.
struct BlinkingCursor: View {
    @State private var isVisible = true
    
    let color: Color
    let width: CGFloat
    let height: CGFloat
    
    init(
        color: Color = .white,
        width: CGFloat = 2,
        height: CGFloat = 16
    ) {
        self.color = color
        self.width = width
        self.height = height
    }
    
    var body: some View {
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
struct TypewriterText: View {
    let text: String
    let speed: TimeInterval
    let showCursor: Bool
    let cursorColor: Color
    
    @State private var displayedText = ""
    @State private var isComplete = false
    
    init(
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
    
    var body: some View {
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

// MARK: - Command Button Style

/// A button that looks like a terminal command.
/// Example: > open_folder
public struct TerminalCommandButton: View {
    @Environment(\.devysTheme) private var theme
    
    let label: String
    let icon: String?
    let isAccent: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    public init(
        _ label: String,
        icon: String? = nil,
        isAccent: Bool = true,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.isAccent = isAccent
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(">")
                    .foregroundStyle(isAccent ? theme.accent : theme.textSecondary)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                
                Text(label.lowercased().replacingOccurrences(of: " ", with: "_"))
            }
            .font(DevysTypography.base)
            .foregroundStyle(isHovered ? theme.text : theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .fill(isHovered ? theme.elevated : theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .strokeBorder(isHovered ? theme.border : theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Keyboard Shortcut Badge

/// Displays a keyboard shortcut in terminal style: [CMD+O]
public struct KeyboardShortcutBadge: View {
    @Environment(\.devysTheme) private var theme
    
    let shortcut: String
    
    public init(_ shortcut: String) {
        self.shortcut = shortcut
    }
    
    public var body: some View {
        Text("[\(shortcut)]")
            .font(DevysTypography.xs)
            .foregroundStyle(theme.textTertiary)
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

// MARK: - Previews

#Preview("Blinking Cursor") {
    HStack {
        Text("Hello World")
            .font(DevysTypography.base)
        BlinkingCursor(color: .white)
    }
    .padding()
    .background(Color.black)
}

#Preview("Typewriter Text") {
    TypewriterText("the artificial intelligence development environment")
        .padding()
        .background(Color.black)
}

#Preview("Terminal Commands") {
    VStack(alignment: .leading, spacing: 12) {
        TerminalCommandButton("add repository", icon: "folder") {}
        TerminalCommandButton("new chat", icon: "plus.message", isAccent: false) {}
        
        HStack {
            TerminalCommandButton("save", icon: "square.and.arrow.down") {}
            KeyboardShortcutBadge("CMD+S")
        }
        
        TerminalDivider(useDashes: true)
    }
    .padding()
    .background(Color.black)
    .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .coral))
}
