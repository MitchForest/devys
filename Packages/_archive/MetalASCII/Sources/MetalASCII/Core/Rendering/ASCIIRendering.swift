// ASCIIRendering.swift
// DevysUI - Public API for ASCII art rendering
//
// Re-exports all ASCII rendering components for easy import.
//
// Copyright © 2026 Devys. All rights reserved.

// MARK: - ASCII Rendering Module
//
// This module provides GPU-accelerated ASCII art rendering using Metal shaders.
//
// ## Components
//
// - `ASCIIFilter`: Core Image filter for ASCII conversion
// - `MetalASCIIRenderer`: Direct Metal renderer for high performance
// - `ASCIIImageView`: SwiftUI view for displaying ASCII art
// - `ASCIIWelcomeView`: Welcome screen with animated ASCII logo
// - `ASCIIWelcomeScreen`: Complete welcome screen with actions
//
// ## Usage
//
// ### Converting an Image to ASCII Art
// ```swift
// // Using CIImage extension
// let asciiImage = myImage.toASCII(foregroundColor: .coral)
//
// // Using ASCIIFilter directly
// let filter = ASCIIFilter()
// filter.inputImage = myCIImage
// filter.foregroundColor = CIVector(x: 1, y: 0.4, z: 0.4)
// let output = filter.outputImage
// ```
//
// ### Displaying ASCII Art in SwiftUI
// ```swift
// ASCIIImageView(image: myNSImage, accentColored: true)
//     .frame(width: 200, height: 200)
// ```
//
// ### Using the Welcome Screen
// ```swift
// ASCIIWelcomeScreen(
//     onOpenFolder: { /* handle */ },
//     onNewChat: { /* handle */ }
// )
// ```
//
// ## Performance
//
// All rendering uses GPU-accelerated Metal shaders for real-time performance.
// The filter can process video-sized images at 60fps on modern hardware.
//
// ## Theme Integration
//
// Components automatically use the current `DevysTheme` accent color when
// initialized with `accentColored: true`.

// Note: All types are defined in their respective files and are public.
// This file serves as documentation for the ASCII rendering module.
