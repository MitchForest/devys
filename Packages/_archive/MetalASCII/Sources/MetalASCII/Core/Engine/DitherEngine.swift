// DitherEngine.swift
// MetalASCII - Unified dithering infrastructure
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import Foundation
import Metal
import simd

// MARK: - Dither Mode

/// Available dithering algorithms.
public enum DitherMode: String, CaseIterable, Sendable, Identifiable {
    case none = "None"
    case bayer4x4 = "Bayer 4x4"
    case bayer8x8 = "Bayer 8x8"
    case floydSteinberg = "Floyd-Steinberg"
    case blueNoise = "Blue Noise"

    public var id: String { rawValue }

    /// Shader index for this dither mode.
    public var shaderIndex: UInt32 {
        switch self {
        case .none: return 0
        case .bayer4x4: return 1
        case .bayer8x8: return 2
        case .floydSteinberg: return 3
        case .blueNoise: return 4
        }
    }

    /// Description for UI.
    public var description: String {
        switch self {
        case .none: return "No dithering - raw brightness mapping"
        case .bayer4x4: return "4x4 ordered dithering - subtle, fast"
        case .bayer8x8: return "8x8 ordered dithering - smooth gradients"
        case .floydSteinberg: return "Error diffusion - natural look"
        case .blueNoise: return "Blue noise - organic feel"
        }
    }
}

// MARK: - Dither Engine

/// Provides dithering functionality for ASCII art rendering.
///
/// The dither engine manages dither matrices and provides both GPU
/// (via Metal buffers) and CPU implementations.
public final class DitherEngine: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = DitherEngine()

    // MARK: - Bayer Matrices

    /// 4x4 Bayer dithering matrix (normalized 0-1).
    public static let bayer4x4: [Float] = [
        0.0 / 16.0, 8.0 / 16.0, 2.0 / 16.0, 10.0 / 16.0,
        12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0, 6.0 / 16.0,
        3.0 / 16.0, 11.0 / 16.0, 1.0 / 16.0, 9.0 / 16.0,
        15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0, 5.0 / 16.0
    ]

    /// 8x8 Bayer dithering matrix (normalized 0-1).
    public static let bayer8x8: [Float] = [
        0.0 / 64.0, 32.0 / 64.0, 8.0 / 64.0, 40.0 / 64.0, 2.0 / 64.0, 34.0 / 64.0, 10.0 / 64.0, 42.0 / 64.0,
        48.0 / 64.0, 16.0 / 64.0, 56.0 / 64.0, 24.0 / 64.0, 50.0 / 64.0, 18.0 / 64.0, 58.0 / 64.0, 26.0 / 64.0,
        12.0 / 64.0, 44.0 / 64.0, 4.0 / 64.0, 36.0 / 64.0, 14.0 / 64.0, 46.0 / 64.0, 6.0 / 64.0, 38.0 / 64.0,
        60.0 / 64.0, 28.0 / 64.0, 52.0 / 64.0, 20.0 / 64.0, 62.0 / 64.0, 30.0 / 64.0, 54.0 / 64.0, 22.0 / 64.0,
        3.0 / 64.0, 35.0 / 64.0, 11.0 / 64.0, 43.0 / 64.0, 1.0 / 64.0, 33.0 / 64.0, 9.0 / 64.0, 41.0 / 64.0,
        51.0 / 64.0, 19.0 / 64.0, 59.0 / 64.0, 27.0 / 64.0, 49.0 / 64.0, 17.0 / 64.0, 57.0 / 64.0, 25.0 / 64.0,
        15.0 / 64.0, 47.0 / 64.0, 7.0 / 64.0, 39.0 / 64.0, 13.0 / 64.0, 45.0 / 64.0, 5.0 / 64.0, 37.0 / 64.0,
        63.0 / 64.0, 31.0 / 64.0, 55.0 / 64.0, 23.0 / 64.0, 61.0 / 64.0, 29.0 / 64.0, 53.0 / 64.0, 21.0 / 64.0
    ]

    // MARK: - Metal Buffers

    private var bayer4x4Buffer: MTLBuffer?
    private var bayer8x8Buffer: MTLBuffer?

    // MARK: - Initialization

    private init() {}

    // MARK: - GPU Buffers

    /// Get or create the Bayer 4x4 matrix buffer for GPU use.
    public func getBayer4x4Buffer(device: MTLDevice) -> MTLBuffer? {
        if let buffer = bayer4x4Buffer {
            return buffer
        }

        var matrix = Self.bayer4x4
        bayer4x4Buffer = device.makeBuffer(
            bytes: &matrix,
            length: MemoryLayout<Float>.stride * matrix.count,
            options: .storageModeShared
        )
        return bayer4x4Buffer
    }

    /// Get or create the Bayer 8x8 matrix buffer for GPU use.
    public func getBayer8x8Buffer(device: MTLDevice) -> MTLBuffer? {
        if let buffer = bayer8x8Buffer {
            return buffer
        }

        var matrix = Self.bayer8x8
        bayer8x8Buffer = device.makeBuffer(
            bytes: &matrix,
            length: MemoryLayout<Float>.stride * matrix.count,
            options: .storageModeShared
        )
        return bayer8x8Buffer
    }

    // MARK: - CPU Dithering

    /// Apply dithering to a brightness value (CPU implementation).
    ///
    /// - Parameters:
    ///   - brightness: Input brightness (0-1)
    ///   - x: X coordinate for pattern lookup
    ///   - y: Y coordinate for pattern lookup
    ///   - mode: Dithering mode to apply
    /// - Returns: Dithered brightness value (0-1)
    public func applyDither(
        brightness: Float,
        x: Int,
        y: Int,
        mode: DitherMode
    ) -> Float {
        switch mode {
        case .none:
            return brightness

        case .bayer4x4:
            let threshold = Self.bayer4x4[(y % 4) * 4 + (x % 4)]
            return brightness + (threshold - 0.5) * 0.15

        case .bayer8x8:
            let threshold = Self.bayer8x8[(y % 8) * 8 + (x % 8)]
            return brightness + (threshold - 0.5) * 0.12

        case .floydSteinberg, .blueNoise:
            // These require error propagation - fall back to Bayer 8x8
            let threshold = Self.bayer8x8[(y % 8) * 8 + (x % 8)]
            return brightness + (threshold - 0.5) * 0.12
        }
    }

    /// Apply dithering to an entire grid of brightness values.
    ///
    /// - Parameters:
    ///   - brightness: 2D array of brightness values (0-1)
    ///   - mode: Dithering mode to apply
    /// - Returns: Dithered brightness array
    public func applyDither(
        brightness: [[Float]],
        mode: DitherMode
    ) -> [[Float]] {
        guard mode != .none else { return brightness }

        var result = brightness
        for y in 0..<brightness.count {
            for x in 0..<brightness[y].count {
                result[y][x] = applyDither(
                    brightness: brightness[y][x],
                    x: x,
                    y: y,
                    mode: mode
                )
            }
        }
        return result
    }
}

// MARK: - Dither Strength Presets

public extension DitherMode {
    /// Recommended dither strength for this mode.
    var recommendedStrength: Float {
        switch self {
        case .none: return 0
        case .bayer4x4: return 0.15
        case .bayer8x8: return 0.12
        case .floydSteinberg: return 0.1
        case .blueNoise: return 0.1
        }
    }
}

#endif // os(macOS)
