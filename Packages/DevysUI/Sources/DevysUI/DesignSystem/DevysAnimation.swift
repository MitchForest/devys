// DevysAnimation.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// Animation tokens for Devys.
///
/// Consistent, subtle animations that feel responsive but not distracting.
public enum DevysAnimation {
    // MARK: - Duration
    
    /// Fast (100ms) - Micro-interactions
    public static let fast = Animation.easeOut(duration: 0.1)
    
    /// Default (200ms) - Standard transitions
    public static let `default` = Animation.easeOut(duration: 0.2)
    
    /// Slow (300ms) - Larger movements
    public static let slow = Animation.easeOut(duration: 0.3)
    
    /// Spring - Bouncy feel for emphasis
    public static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
    
    /// Smooth spring - Subtle spring
    public static let smoothSpring = Animation.spring(response: 0.4, dampingFraction: 0.85)
    
    // MARK: - Named Animations
    
    /// Hover state changes
    public static let hover = fast
    
    /// Focus transitions
    public static let focus = Animation.easeOut(duration: 0.15)
    
    /// Sidebar expand/collapse
    public static let sidebar = Animation.easeInOut(duration: 0.25)
    
    /// Panel resize
    public static let resize = Animation.easeOut(duration: 0.2)
    
    /// Modal appear/disappear
    public static let modal = Animation.spring(response: 0.35, dampingFraction: 0.8)
    
    /// Tab switch
    public static let tab = Animation.easeOut(duration: 0.15)
}

// MARK: - Transition Helpers

public extension AnyTransition {
    /// Fade with scale for modals/popovers
    static var fadeScale: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.95))
    }
    
    /// Slide from bottom
    static var slideUp: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity)
    }
    
    /// Slide from right
    static var slideIn: AnyTransition {
        .move(edge: .trailing).combined(with: .opacity)
    }
}
