// ASCIIEngine.swift
// MetalASCII - Unified ASCII art rendering engine
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import Foundation
import Metal
import MetalKit
import AppKit
import simd

// MARK: - ASCII Engine Configuration

/// Configuration for ASCII rendering.
public struct ASCIIEngineConfig: Sendable {
    /// Number of character columns
    public var columns: Int

    /// Dithering mode
    public var ditherMode: DitherMode

    /// Foreground color (for characters)
    public var foregroundColor: SIMD4<Float>

    /// Background color
    public var backgroundColor: SIMD4<Float>

    /// Whether to invert brightness
    public var invertBrightness: Bool

    /// Contrast boost (1.0 = normal)
    public var contrastBoost: Float

    /// Gamma correction (1.0 = linear)
    public var gamma: Float

    public init(
        columns: Int = 120,
        ditherMode: DitherMode = .bayer8x8,
        foregroundColor: SIMD4<Float> = SIMD4(1, 1, 1, 1),
        backgroundColor: SIMD4<Float> = SIMD4(0.02, 0.02, 0.03, 1),
        invertBrightness: Bool = false,
        contrastBoost: Float = 1.2,
        gamma: Float = 0.9
    ) {
        self.columns = columns
        self.ditherMode = ditherMode
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.invertBrightness = invertBrightness
        self.contrastBoost = contrastBoost
        self.gamma = gamma
    }

    /// Create config from NSColors
    public static func config(
        columns: Int = 120,
        ditherMode: DitherMode = .bayer8x8,
        foreground: NSColor,
        background: NSColor,
        invertBrightness: Bool = false
    ) -> ASCIIEngineConfig {
        var config = ASCIIEngineConfig()
        config.columns = columns
        config.ditherMode = ditherMode
        config.invertBrightness = invertBrightness

        if let fg = foreground.usingColorSpace(.deviceRGB) {
            config.foregroundColor = SIMD4<Float>(
                Float(fg.redComponent),
                Float(fg.greenComponent),
                Float(fg.blueComponent),
                Float(fg.alphaComponent)
            )
        }

        if let bg = background.usingColorSpace(.deviceRGB) {
            config.backgroundColor = SIMD4<Float>(
                Float(bg.redComponent),
                Float(bg.greenComponent),
                Float(bg.blueComponent),
                Float(bg.alphaComponent)
            )
        }

        return config
    }
}

// MARK: - ASCII Cell

/// Represents a single ASCII cell with character and brightness.
public struct ASCIICell: Sendable {
    public var character: Character
    public var brightness: Float

    public init(character: Character = " ", brightness: Float = 0) {
        self.character = character
        self.brightness = brightness
    }
}

// MARK: - ASCII Frame

/// A complete frame of ASCII art.
public struct ASCIIFrame: Sendable {
    public let columns: Int
    public let rows: Int
    public var cells: [[ASCIICell]]

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        self.cells = Array(
            repeating: Array(repeating: ASCIICell(), count: columns),
            count: rows
        )
    }

    /// Get the frame as a string.
    public func toString() -> String {
        cells.map { row in
            String(row.map { $0.character })
        }.joined(separator: "\n")
    }

    /// Get character grid.
    public var characters: [[Character]] {
        cells.map { $0.map { $0.character } }
    }

    /// Get brightness grid.
    public var brightness: [[Float]] {
        cells.map { $0.map { $0.brightness } }
    }
}

// MARK: - ASCII Engine

/// Main engine for ASCII art rendering.
///
/// The ASCII engine provides:
/// - Brightness-to-character mapping
/// - Dithering application
/// - Both GPU and CPU rendering paths
public final class ASCIIEngine: @unchecked Sendable {

    // MARK: - Properties

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public var config: ASCIIEngineConfig

    private let fontAtlas: FontAtlas
    private let ditherEngine: DitherEngine

    // MARK: - Initialization

    public init(device: MTLDevice? = nil, config: ASCIIEngineConfig = ASCIIEngineConfig()) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw ASCIIEngineError.noMetalDevice
        }

        guard let queue = device.makeCommandQueue() else {
            throw ASCIIEngineError.commandQueueFailed
        }

        self.device = device
        self.commandQueue = queue
        self.config = config
        self.fontAtlas = FontAtlas.shared
        self.ditherEngine = DitherEngine.shared
    }

    // MARK: - Brightness to ASCII

    /// Convert a 2D brightness grid to ASCII characters.
    ///
    /// - Parameters:
    ///   - brightness: 2D array of brightness values (0-1)
    ///   - applyDithering: Whether to apply dithering
    /// - Returns: ASCII frame with characters and brightness
    public func brightnessToASCII(
        _ brightness: [[Float]],
        applyDithering: Bool = true
    ) -> ASCIIFrame {
        guard !brightness.isEmpty else {
            return ASCIIFrame(columns: 0, rows: 0)
        }

        let rows = brightness.count
        let columns = brightness[0].count
        var frame = ASCIIFrame(columns: columns, rows: rows)

        let characterRamp = ASCIICharacterRamp.standard
        let rampCount = characterRamp.count

        for row in 0..<rows {
            for col in 0..<brightness[row].count {
                var value = brightness[row][col]

                // Apply dithering
                if applyDithering {
                    value = ditherEngine.applyDither(
                        brightness: value,
                        x: col,
                        y: row,
                        mode: config.ditherMode
                    )
                }

                // Clamp
                value = max(0, min(1, value))

                // Map to character
                let charIndex = Int(value * Float(rampCount - 1))
                let clampedIndex = max(0, min(rampCount - 1, charIndex))
                let character = characterRamp[characterRamp.index(characterRamp.startIndex, offsetBy: clampedIndex)]

                frame.cells[row][col] = ASCIICell(character: character, brightness: value)
            }
        }

        return frame
    }

    /// Convert a single brightness value to an ASCII character.
    public func brightnessToCharacter(_ brightness: Float, ramp: String = ASCIICharacterRamp.standard) -> Character {
        let clamped = max(0, min(1, brightness))
        let index = Int(clamped * Float(ramp.count - 1))
        let clampedIndex = max(0, min(ramp.count - 1, index))
        return ramp[ramp.index(ramp.startIndex, offsetBy: clampedIndex)]
    }

    // MARK: - Resource Access

    /// Get the font texture for GPU rendering.
    public func getFontTexture() throws -> MTLTexture {
        try fontAtlas.getTexture(device: device)
    }

    /// Get the character weights buffer for GPU rendering.
    public func getWeightsBuffer() -> MTLBuffer? {
        fontAtlas.getWeightsBuffer(device: device)
    }

    /// Get the character codes buffer for GPU rendering.
    public func getCodesBuffer() -> MTLBuffer? {
        fontAtlas.getCodesBuffer(device: device)
    }

    /// Get the weight table for CPU rendering.
    public func getWeightTable() -> CharacterWeightTable {
        fontAtlas.getWeightTable()
    }
}

// MARK: - Errors

public enum ASCIIEngineError: Error, LocalizedError {
    case noMetalDevice
    case commandQueueFailed
    case renderFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal device available"
        case .commandQueueFailed:
            return "Failed to create command queue"
        case .renderFailed(let message):
            return "Render failed: \(message)"
        }
    }
}

#endif // os(macOS)
