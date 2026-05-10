// Animations.swift
// Devys Design System — Dia-modeled
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Animation tokens.
///
/// One spring for structural transitions. One timing for micro-interactions.
/// Status animations are the only exceptions.
public enum Animations {

    // MARK: - The Spring

    /// The one spring for all structural transitions.
    /// Confident, settled, not bouncy.
    /// Used for: command palette, splits, sidebar, modals, tab reorder,
    /// popovers, segmented control, FAB menu, pane resize.
    public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.86)

    // MARK: - Micro Timing

    /// 120ms ease-out for all micro-interactions.
    /// Used for: hover backgrounds, press scale, focus rings,
    /// close button fade-in, action button reveal, tooltip appear.
    public static let micro = Animation.easeOut(duration: 0.12)

    // MARK: - Status Animations

    /// Agent running heartbeat: opacity 0.6 → 1.0, 2s cycle
    public static let heartbeat = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)

    /// Completion glow: 300ms then fade
    public static let glow = Animation.easeOut(duration: 0.3)

    /// Error shake: 300ms
    public static let shake = Animation.easeInOut(duration: 0.3)

    /// Progress sweep: continuous left-to-right
    public static let sweep = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

}

// MARK: - Animation Convenience

public extension Animation {
    /// The Devys signature spring.
    static let designSpring = Animation.spring(response: 0.35, dampingFraction: 0.86)
}
