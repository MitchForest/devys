// DevysIcon.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A styled icon component for Devys.
struct DevysIcon: View {
    // MARK: - Properties
    
    private let systemName: String
    private let size: Size
    private let color: Color
    
    // MARK: - Initialization
    
    init(
        _ systemName: String,
        size: Size = .md,
        color: Color = DevysColors.textSecondary
    ) {
        self.systemName = systemName
        self.size = size
        self.color = color
    }
    
    // MARK: - Body
    
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size.points, weight: size.weight))
            .foregroundStyle(color)
            .frame(width: size.frameSize, height: size.frameSize)
    }
}

// MARK: - Size

extension DevysIcon {
    enum Size: Sendable {
        case xs      // 10pt
        case sm      // 12pt
        case md      // 16pt
        case lg      // 20pt
        case xl      // 24pt
        case custom(CGFloat)
    }
}

extension DevysIcon.Size {
    var points: CGFloat {
        switch self {
        case .xs: return DevysSpacing.iconSm - 2
        case .sm: return DevysSpacing.iconSm
        case .md: return DevysSpacing.iconMd
        case .lg: return DevysSpacing.iconLg
        case .xl: return DevysSpacing.iconXl
        case .custom(let size): return size
        }
    }
    
    var weight: Font.Weight {
        switch self {
        case .xs, .sm: return .regular
        case .md, .lg: return .medium
        case .xl: return .medium
        case .custom: return .medium
        }
    }
    
    var frameSize: CGFloat {
        points + 4
    }
}

// MARK: - Previews

#Preview("Icon Sizes") {
    HStack(spacing: DevysSpacing.space4) {
        DevysIcon("folder.fill", size: .xs, color: DevysColors.text)
        DevysIcon("folder.fill", size: .sm, color: DevysColors.text)
        DevysIcon("folder.fill", size: .md, color: DevysColors.text)
        DevysIcon("folder.fill", size: .lg, color: DevysColors.text)
        DevysIcon("folder.fill", size: .xl, color: DevysColors.text)
    }
    .padding()
    .background(DevysColors.bg0)
}
