// DevysUI.swift
// DevysUI - Shared UI components for Devys
//
// Copyright © 2026 Devys. All rights reserved.

import SwiftUI

/// DevysUI provides the design system and reusable UI components for Devys.
///
/// ## Overview
/// This package contains:
/// - **DesignSystem**: Colors, typography, spacing tokens
/// - **Components**: Reusable UI components (buttons, icons, etc.)
/// - **Extensions**: SwiftUI view modifiers and helpers
///
/// ## Usage
/// ```swift
/// import DevysUI
///
/// struct MyView: View {
///     var body: some View {
///         Text("Hello")
///             .foregroundColor(DevysColors.textPrimary)
///             .font(DevysTypography.body)
///     }
/// }
/// ```
public enum DevysUI {
    /// Current version of the DevysUI package.
    public static let version = "1.0.0"
}

// Re-export design system for convenience
public typealias Colors = DevysColors
public typealias Typography = DevysTypography
public typealias Spacing = DevysSpacing
public typealias Anim = DevysAnimation
