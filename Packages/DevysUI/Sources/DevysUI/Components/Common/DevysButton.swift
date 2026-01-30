// DevysButton.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A styled button component for Devys.
public struct DevysButton: View {
    // MARK: - Properties
    
    private let title: String
    private let icon: String?
    private let style: Style
    private let size: Size
    private let isLoading: Bool
    private let action: () -> Void
    
    @State private var isHovered = false
    
    // MARK: - Initialization
    
    public init(
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
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: DevysSpacing.space1) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .progressViewStyle(.circular)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .medium))
                }
                
                Text(title)
                    .font(size.font)
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DevysSpacing.radiusSm))
            .overlay(
                RoundedRectangle(cornerRadius: DevysSpacing.radiusSm)
                    .strokeBorder(borderColor, lineWidth: DevysSpacing.borderWidth)
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
    
    private var backgroundColor: Color {
        switch style {
        case .primary:
            return isHovered ? DevysColors.accentHover : DevysColors.accent
        case .secondary:
            return isHovered ? DevysColors.bg3 : DevysColors.bg2
        case .ghost:
            return isHovered ? DevysColors.bg3 : .clear
        case .danger:
            return isHovered ? DevysColors.error.opacity(0.9) : DevysColors.error
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary, .danger:
            return .white
        case .secondary:
            return DevysColors.text
        case .ghost:
            return DevysColors.textSecondary
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .primary, .danger, .ghost:
            return .clear
        case .secondary:
            return DevysColors.border
        }
    }
}

// MARK: - Style

extension DevysButton {
    public enum Style: Sendable {
        case primary
        case secondary
        case ghost
        case danger
    }
}

// MARK: - Size

extension DevysButton {
    public enum Size: Sendable {
        case small
        case medium
        case large
        
        var font: Font {
            switch self {
            case .small: return DevysTypography.sm
            case .medium: return DevysTypography.label
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
            case .large: return DevysSpacing.space2
            }
        }
    }
}

// MARK: - Previews

#Preview("Button Styles") {
    VStack(spacing: DevysSpacing.space4) {
        DevysButton("Primary", icon: "plus", style: .primary) {}
        DevysButton("Secondary", icon: "doc", style: .secondary) {}
        DevysButton("Ghost", icon: "xmark", style: .ghost) {}
        DevysButton("Danger", icon: "trash", style: .danger) {}
        DevysButton("Loading", style: .primary, isLoading: true) {}
    }
    .padding()
    .background(DevysColors.bg0)
}
