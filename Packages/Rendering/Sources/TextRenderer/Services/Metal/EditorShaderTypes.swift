// EditorShaderTypes.swift
// DevysTextRenderer - Shared Metal text rendering
//
// Shared structures between Swift and Metal shaders.

import Foundation
import simd

// MARK: - Cell GPU Data

/// Per-character data sent to the GPU for rendering.
public struct EditorCellGPU {
    /// Position in pixels (x, y)
    public var position: SIMD2<Float>
    
    /// Foreground color (RGBA, linear 0-1)
    public var foregroundColor: SIMD4<Float>
    
    /// Background color (RGBA, linear 0-1)
    public var backgroundColor: SIMD4<Float>
    
    /// UV origin in glyph atlas (normalized 0-1)
    public var uvOrigin: SIMD2<Float>
    
    /// UV size in glyph atlas (normalized 0-1)
    public var uvSize: SIMD2<Float>
    
    /// Cell flags (bold, italic, underline, etc.)
    public var flags: UInt32
    
    /// Padding for alignment
    public var padding: UInt32
    
    public init(
        position: SIMD2<Float> = .zero,
        foregroundColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1),
        backgroundColor: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 0),
        uvOrigin: SIMD2<Float> = .zero,
        uvSize: SIMD2<Float> = .zero,
        flags: UInt32 = 0
    ) {
        self.position = position
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.uvOrigin = uvOrigin
        self.uvSize = uvSize
        self.flags = flags
        self.padding = 0
    }
}

// MARK: - Cell Flags

/// Bit flags for cell attributes
public struct EditorCellFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let bold          = EditorCellFlags(rawValue: 1 << 0)
    public static let italic        = EditorCellFlags(rawValue: 1 << 1)
    public static let underline     = EditorCellFlags(rawValue: 1 << 2)
    public static let strikethrough = EditorCellFlags(rawValue: 1 << 3)
    public static let dim           = EditorCellFlags(rawValue: 1 << 4)
    public static let cursor        = EditorCellFlags(rawValue: 1 << 5)
    public static let selection     = EditorCellFlags(rawValue: 1 << 6)
    public static let lineNumber    = EditorCellFlags(rawValue: 1 << 7)
}

// MARK: - Uniforms

/// Per-frame uniforms sent to the GPU.
public struct EditorUniforms {
    /// Viewport size in pixels
    public var viewportSize: SIMD2<Float>
    
    /// Cell size in pixels
    public var cellSize: SIMD2<Float>
    
    /// Glyph atlas size in pixels
    public var atlasSize: SIMD2<Float>
    
    /// Current time for animations
    public var time: Float
    
    /// Cursor blink rate (Hz)
    public var cursorBlinkRate: Float
    
    public init(
        viewportSize: SIMD2<Float> = .zero,
        cellSize: SIMD2<Float> = .zero,
        atlasSize: SIMD2<Float> = .zero,
        time: Float = 0,
        cursorBlinkRate: Float = 2.0
    ) {
        self.viewportSize = viewportSize
        self.cellSize = cellSize
        self.atlasSize = atlasSize
        self.time = time
        self.cursorBlinkRate = cursorBlinkRate
    }
}

// MARK: - Overlay Vertex

/// Vertex data for overlay rendering (cursor, selection)
public struct EditorOverlayVertex {
    /// Position in pixels
    public var position: SIMD2<Float>
    
    /// Color (RGBA, 0-1)
    public var color: SIMD4<Float>
    
    public init(position: SIMD2<Float>, color: SIMD4<Float>) {
        self.position = position
        self.color = color
    }
}

// MARK: - Color Utilities

/// Convert sRGB to linear color space
public func srgbToLinear(_ value: Float) -> Float {
    if value <= 0.04045 {
        return value / 12.92
    }
    return pow((value + 0.055) / 1.055, 2.4)
}

/// Convert hex color to linear SIMD4
public func hexToLinearColor(_ hex: String, alpha: Float = 1.0) -> SIMD4<Float> {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexString = hexString.replacingOccurrences(of: "#", with: "")

    if hexString.count == 3 || hexString.count == 4 {
        let expanded = hexString.map { "\($0)\($0)" }.joined()
        hexString = expanded
    }

    var rgba: UInt64 = 0
    Foundation.Scanner(string: hexString).scanHexInt64(&rgba)

    let hasAlpha = hexString.count == 8
    let r = srgbToLinear(Float((rgba >> (hasAlpha ? 24 : 16)) & 0xFF) / 255.0)
    let g = srgbToLinear(Float((rgba >> (hasAlpha ? 16 : 8)) & 0xFF) / 255.0)
    let b = srgbToLinear(Float((rgba >> (hasAlpha ? 8 : 0)) & 0xFF) / 255.0)
    let a = hasAlpha ? Float(rgba & 0xFF) / 255.0 : alpha

    return SIMD4<Float>(r, g, b, a)
}
