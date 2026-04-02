// CanvasLayout.swift
// Devys - A Visual Canvas for AI-Native Software Development
//
// Copyright © 2026 Devys. All rights reserved.

import CoreGraphics

/// Layout constants for the workflow canvas.
public enum CanvasLayout {
    public static let defaultScale: CGFloat = 1.0
    public static let minScale: CGFloat = 0.1
    public static let maxScale: CGFloat = 3.0
    public static let dotSpacing: CGFloat = 20
    public static let dotRadius: CGFloat = 1.5
    public static let snapThreshold: CGFloat = 8
    public static let defaultNodeSize = CGSize(width: 240, height: 140)
    public static let nodeCornerRadius: CGFloat = 12
}
