// FontAtlas.swift
// MetalASCII - Character texture atlas and weight management
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import Foundation
import AppKit
import Metal
import MetalKit

// swiftlint:disable function_body_length

// MARK: - ASCII Character Set

/// Standard ASCII character ramps for different density mappings.
public enum ASCIICharacterRamp {
    /// 10 characters - simple gradient
    public static let simple = " .:-=+*#%@"

    /// 16 characters - extended gradient
    public static let standard = " .,:;=+*xoO#%@MW"

    /// 70 characters - full gradient
    public static let extended = " .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$"

    /// Characters sorted by visual density (for brightness mapping)
    public static func characterForBrightness(_ brightness: Float, ramp: String = standard) -> Character {
        let index = Int(brightness * Float(ramp.count - 1))
        let clampedIndex = max(0, min(ramp.count - 1, index))
        return ramp[ramp.index(ramp.startIndex, offsetBy: clampedIndex)]
    }
}

// MARK: - Font Atlas

/// Manages a texture atlas of ASCII characters for GPU rendering.
///
/// The atlas contains all 95 printable ASCII characters (32-126)
/// arranged in a 16x6 grid.
public final class FontAtlas: @unchecked Sendable {

    // MARK: - Configuration

    /// Cell dimensions in the texture
    public let cellWidth: Int = 16
    public let cellHeight: Int = 24

    /// Grid dimensions
    public let columns: Int = 16
    public let rows: Int = 6

    /// Total texture dimensions
    public var textureWidth: Int { cellWidth * columns }   // 256
    public var textureHeight: Int { cellHeight * rows }     // 144

    // MARK: - Properties

    private var texture: MTLTexture?
    private var weightTable: CharacterWeightTable?
    private var weightsBuffer: MTLBuffer?
    private var codesBuffer: MTLBuffer?

    // MARK: - Singleton

    public static let shared = FontAtlas()

    private init() {}

    // MARK: - Texture Access

    /// Get or create the font texture for a Metal device.
    public func getTexture(device: MTLDevice) throws -> MTLTexture {
        if let existing = texture {
            return existing
        }

        let newTexture = try generateTexture(device: device)
        texture = newTexture
        return newTexture
    }

    /// Get the character weight table.
    public func getWeightTable() -> CharacterWeightTable {
        if let existing = weightTable {
            return existing
        }

        let table = CharacterWeightGenerator.sharedWeightTable
        weightTable = table
        return table
    }

    /// Get the character weights buffer for GPU use.
    public func getWeightsBuffer(device: MTLDevice) -> MTLBuffer? {
        if let existing = weightsBuffer {
            return existing
        }

        let table = getWeightTable()
        var flatWeights = table.flatWeights
        weightsBuffer = device.makeBuffer(
            bytes: &flatWeights,
            length: flatWeights.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        return weightsBuffer
    }

    /// Get the ASCII codes buffer for GPU use.
    public func getCodesBuffer(device: MTLDevice) -> MTLBuffer? {
        if let existing = codesBuffer {
            return existing
        }

        let table = getWeightTable()
        var codes = table.asciiCodes
        codesBuffer = device.makeBuffer(
            bytes: &codes,
            length: codes.count * MemoryLayout<Int32>.stride,
            options: .storageModeShared
        )
        return codesBuffer
    }

    // MARK: - Texture Generation

    /// Generate the font texture programmatically.
    private func generateTexture(device: MTLDevice) throws -> MTLTexture {
        // Create NSImage with font characters
        let image = NSImage(size: NSSize(width: textureWidth, height: textureHeight))
        image.lockFocus()

        // Clear to black
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: textureWidth, height: textureHeight).fill()

        // Draw characters
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        // ASCII printable characters (32-126 = 95 characters)
        for i in 0..<95 {
            guard let scalar = UnicodeScalar(32 + i) else { continue }
            let char = Character(scalar)
            let string = String(char)

            let col = i % columns
            let row = i / columns

            // Calculate position (flip Y for texture coordinates)
            let attrString = NSAttributedString(string: string, attributes: attributes)
            let stringSize = attrString.size()

            let cellX = CGFloat(col * cellWidth)
            let cellY = CGFloat(textureHeight - (row + 1) * cellHeight)

            // Center character in cell
            let x = cellX + (CGFloat(cellWidth) - stringSize.width) / 2
            let y = cellY + (CGFloat(cellHeight) - stringSize.height) / 2

            attrString.draw(at: NSPoint(x: x, y: y))
        }

        image.unlockFocus()

        // Convert to texture
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw FontAtlasError.textureCreationFailed
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw FontAtlasError.textureCreationFailed
        }

        // Extract grayscale data from image
        let bytesPerRow = textureWidth
        var pixelData = [UInt8](repeating: 0, count: textureWidth * textureHeight)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixelData,
            width: textureWidth,
            height: textureHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw FontAtlasError.textureCreationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: textureWidth, height: textureHeight))

        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: textureWidth, height: textureHeight, depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    // MARK: - Character Lookup

    /// Get texture coordinates for an ASCII character.
    ///
    /// - Parameter ascii: ASCII code (32-126)
    /// - Returns: UV coordinates (minU, minV, maxU, maxV)
    public func textureCoordinates(for ascii: Int) -> (Float, Float, Float, Float) {
        let charIndex = max(0, min(94, ascii - 32))
        let col = charIndex % columns
        let row = charIndex / columns

        let minU = Float(col) / Float(columns)
        let maxU = Float(col + 1) / Float(columns)
        let minV = Float(row) / Float(rows)
        let maxV = Float(row + 1) / Float(rows)

        return (minU, minV, maxU, maxV)
    }
}

// MARK: - Errors

public enum FontAtlasError: Error, LocalizedError {
    case textureCreationFailed
    case bufferCreationFailed

    public var errorDescription: String? {
        switch self {
        case .textureCreationFailed:
            return "Failed to create font texture"
        case .bufferCreationFailed:
            return "Failed to create character buffer"
        }
    }
}

// swiftlint:enable function_body_length

#endif // os(macOS)
