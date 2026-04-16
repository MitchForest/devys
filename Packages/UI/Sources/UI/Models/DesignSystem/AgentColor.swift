// AgentColor.swift
// Devys Design System — Agent identity colors
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Agent identity color.
///
/// Each agent session gets a color from the accent palette (minus Graphite).
/// The color persists for the session's lifetime and appears on the tab stripe,
/// sidebar dot, chat accent, and notifications.
public struct AgentColor: Sendable, Equatable, Hashable {
    /// Full-strength color for stripes, dots, icons
    public let solid: Color

    /// 15% opacity for selection backgrounds, hover highlights
    public let muted: Color

    /// 6% opacity for ambient status glow, background tints
    public let subtle: Color

    /// Legibility-adjusted color for text
    public let text: Color

    /// The hex string for serialization
    public let hex: String

    init(_ hex: String) {
        self.hex = hex
        let base = Color(hex: hex)
        self.solid = base
        self.muted = base.opacity(0.15)
        self.subtle = base.opacity(0.06)
        self.text = base
    }

    // MARK: - Palette (9 colors = accent palette minus Graphite)

    public static let palette: [AgentColor] = [
        AgentColor("#4A7FD4"),  // blue
        AgentColor("#3DBDA7"),  // teal
        AgentColor("#5AAE6B"),  // green
        AgentColor("#8BBD5A"),  // lime
        AgentColor("#D4B44A"),  // yellow
        AgentColor("#D48A4A"),  // orange
        AgentColor("#D45C5C"),  // red
        AgentColor("#D46B96"),  // pink
        AgentColor("#9B7FD4"),  // violet
    ]

    /// Get the agent color for a given index. Wraps around.
    public static func forIndex(_ index: Int) -> AgentColor {
        palette[index % palette.count]
    }

    // MARK: - Display Names

    public var displayName: String {
        switch hex {
        case "#4A7FD4": "Blue"
        case "#3DBDA7": "Teal"
        case "#5AAE6B": "Green"
        case "#8BBD5A": "Lime"
        case "#D4B44A": "Yellow"
        case "#D48A4A": "Orange"
        case "#D45C5C": "Red"
        case "#D46B96": "Pink"
        case "#9B7FD4": "Violet"
        default: "Custom"
        }
    }
}
