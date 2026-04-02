// DevysButton.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A terminal-styled button component for Devys.
/// Displays as `> action_name` with monospace font.
struct DevysButton: View {
    @Environment(\.devysTheme) private var theme
    
    // MARK: - Properties
    
    private let title: String
    private let icon: String?
    private let style: Style
    private let size: Size
    private let isLoading: Bool
    private let action: () -> Void
    
    @State private var isHovered = false
    
    // MARK: - Initialization
    
    init(
        _ title: String,
        icon: String? = nil,
        style: Style = .secondary,
        size: Size = .medium,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }
    
    // MARK: - Body
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Terminal prompt
                Text(">")
                    .foregroundStyle(promptColor)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(.circular)
                } else {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: size.iconSize))
                    }
                    
                    // Convert to terminal-style naming
                    Text(title.lowercased().replacingOccurrences(of: " ", with: "_"))
                }
            }
            .font(size.font)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering in
            withAnimation(DevysAnimation.hover) {
                isHovered = hovering
            }
        }
    }
    
    // MARK: - Styling
    
    private var promptColor: Color {
        switch style {
        case .primary:
            return theme.accent
        case .secondary:
            return theme.textSecondary
        case .ghost:
            return theme.textTertiary
        case .danger:
            return DevysColors.error
        }
    }
    
    private var backgroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? theme.elevated : theme.surface
        case .secondary:
            return isHovered ? theme.elevated : theme.surface
        case .ghost:
            return isHovered ? theme.elevated : .clear
        case .danger:
            return isHovered ? DevysColors.error.opacity(0.15) : .clear
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? theme.text : theme.textSecondary
        case .secondary:
            return isHovered ? theme.text : theme.textSecondary
        case .ghost:
            return theme.textSecondary
        case .danger:
            return DevysColors.error
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .primary:
            return isHovered ? theme.accent : theme.border
        case .secondary:
            return isHovered ? theme.borderStrong : theme.border
        case .ghost:
            return .clear
        case .danger:
            return DevysColors.error.opacity(0.5)
        }
    }
}

// MARK: - Style

extension DevysButton {
    enum Style: Sendable {
        case primary   // Accent-colored prompt
        case secondary // Neutral prompt
        case ghost     // Minimal, no border
        case danger    // Red for destructive actions
    }
}

// MARK: - Size

extension DevysButton {
    enum Size: Sendable {
        case small
        case medium
        case large
    }
}

extension DevysButton.Size {
    var font: Font {
        // All buttons use monospace
        switch self {
        case .small: return DevysTypography.sm
        case .medium: return DevysTypography.base
        case .large: return DevysTypography.md
        }
    }
    
    var iconSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 12
        case .large: return 14
        }
    }
    
    var horizontalPadding: CGFloat {
        switch self {
        case .small: return DevysSpacing.space2
        case .medium: return DevysSpacing.space3
        case .large: return DevysSpacing.space4
        }
    }
    
    var verticalPadding: CGFloat {
        switch self {
        case .small: return DevysSpacing.space1
        case .medium: return DevysSpacing.space2
        case .large: return DevysSpacing.space3
        }
    }
}

// MARK: - Previews

#Preview("Button Styles") {
    VStack(spacing: DevysSpacing.space4) {
        DevysButton("Open Folder", icon: "folder", style: .primary) {}
        DevysButton("New File", icon: "doc", style: .secondary) {}
        DevysButton("Cancel", icon: "xmark", style: .ghost) {}
        DevysButton("Delete", icon: "trash", style: .danger) {}
        DevysButton("Loading", style: .primary, isLoading: true) {}
    }
    .padding(24)
    .background(Color.black)
    .environment(\.devysTheme, DevysTheme(isDark: true, accentColor: .coral))
}
