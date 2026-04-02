// MetalASCII.swift
// MetalASCII - GPU-accelerated ASCII art rendering with dithering and animation
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

/// MetalASCII provides GPU-accelerated ASCII art rendering infrastructure.
///
/// ## Overview
/// This package contains:
/// - **Core/Scene**: Scene protocol and hosting infrastructure
/// - **Core/Rendering**: ASCII rendering pipelines and Metal integration
/// - **Core/Shaders**: Metal shaders for dithering and character mapping
/// - **Projects**: Individual art projects (Flower, etc.)
///
/// ## Usage
/// Run the standalone executable:
/// ```bash
/// swift run ascii-runner
/// ```
///
/// ## Available Scenes
/// - **FlowerScene**: Procedural rose-curve flower with wind animation and dithering
/// - More coming soon...
public enum MetalASCII {
    /// Current version of the MetalASCII package.
    public static let version = "1.0.0"
}

// MARK: - Re-exports

// Core exports are handled by each file's public declarations
