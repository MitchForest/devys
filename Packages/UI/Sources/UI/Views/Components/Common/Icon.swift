// Icon.swift
// Devys Design System
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// A styled icon wrapping SF Symbols.
public struct Icon: View {
    private let systemName: String
    private let size: Size
    private let color: Color?

    @Environment(\.theme) private var theme

    public init(
        _ systemName: String,
        size: Size = .md,
        color: Color? = nil
    ) {
        self.systemName = systemName
        self.size = size
        self.color = color
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(size.font)
            .foregroundStyle(color ?? theme.textSecondary)
            .frame(width: size.frame, height: size.frame)
    }
}

// MARK: - Size

public extension Icon {
    enum Size: Sendable {
        case xs
        case sm
        case md
        case lg
        case xl
        case custom(CGFloat)

        var points: CGFloat {
            switch self {
            case .xs: 10
            case .sm: 12
            case .md: 16
            case .lg: 20
            case .xl: 24
            case .custom(let s): s
            }
        }

        var font: Font {
            switch self {
            case .xs:
                Typography.micro.weight(.regular)
            case .sm:
                Typography.label.weight(.regular)
            case .md:
                Font.system(size: 16, weight: .medium, design: .default)
            case .lg:
                Font.system(size: 20, weight: .medium, design: .default)
            case .xl:
                Font.system(size: 24, weight: .medium, design: .default)
            case .custom(let size):
                Font.system(size: size, weight: .medium, design: .default)
            }
        }

        var frame: CGFloat { points + 4 }
    }
}

// MARK: - Previews

#Preview("Icons") {
    HStack(spacing: Spacing.space4) {
        Icon("folder.fill", size: .xs)
        Icon("folder.fill", size: .sm)
        Icon("folder.fill", size: .md)
        Icon("folder.fill", size: .lg)
        Icon("folder.fill", size: .xl)
    }
    .padding()
    .background(Color(hex: "#121110"))
    .environment(\.theme, Theme(isDark: true, accentColor: .graphite))
}
