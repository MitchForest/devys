// Density.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Density modes.
///
/// Comfortable is the default — generous padding, everything breathes.
/// Compact is for professionals who want maximum information density.
public enum Density: String, Sendable, CaseIterable, Codable {
    case comfortable
    case compact
}

/// Density-aware layout values.
public struct DensityLayout: Sendable {
    public let density: Density

    public init(_ density: Density = .comfortable) {
        self.density = density
    }

    // MARK: - Heights

    public var tabHeight: CGFloat { density == .compact ? 28 : 36 }
    public var buttonHeight: CGFloat { density == .compact ? 30 : 36 }
    public var sidebarRowHeight: CGFloat { density == .compact ? 24 : 32 }
    public var listRowHeight: CGFloat { density == .compact ? 24 : 32 }
    public var toolbarHeight: CGFloat { density == .compact ? 36 : 44 }
    public var statusBarHeight: CGFloat { density == .compact ? 20 : 24 }

    // MARK: - Padding

    public var sectionPadding: CGFloat { density == .compact ? 12 : 16 }
    public var itemPaddingH: CGFloat { density == .compact ? 6 : 8 }
    public var itemPaddingV: CGFloat { density == .compact ? 4 : 6 }

    // MARK: - Icon Size

    public var iconSize: CGFloat { density == .compact ? 14 : 16 }

    // MARK: - Rail

    public var repoRailWidth: CGFloat { density == .compact ? 40 : 48 }
    public var repoItemSize: CGFloat { density == .compact ? 28 : 34 }
    public var worktreeItemHeight: CGFloat { density == .compact ? 22 : 26 }

    // MARK: - Pane Gap

    public var paneGap: CGFloat { density == .compact ? 4 : 6 }

    // MARK: - Capsule

    public var capsulePaddingH: CGFloat { density == .compact ? 8 : 10 }
    public var capsulePaddingV: CGFloat { density == .compact ? 5 : 6 }

    // MARK: - Font Size Offset

    public var fontSizeOffset: CGFloat { density == .compact ? -1 : 0 }
}

// MARK: - Environment Keys

private struct DensityKey: EnvironmentKey {
    static let defaultValue = Density.comfortable
}

private struct DensityLayoutKey: EnvironmentKey {
    static let defaultValue = DensityLayout(.comfortable)
}

public extension EnvironmentValues {
    var density: Density {
        get { self[DensityKey.self] }
        set { self[DensityKey.self] = newValue }
    }

    var densityLayout: DensityLayout {
        get { self[DensityLayoutKey.self] }
        set { self[DensityLayoutKey.self] = newValue }
    }
}
