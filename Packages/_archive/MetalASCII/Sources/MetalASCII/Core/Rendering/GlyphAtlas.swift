// GlyphAtlas.swift
// MetalASCII - GPU-based glyph rendering with texture atlas
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import CoreText

// swiftlint:disable function_body_length

// MARK: - Glyph Atlas

/// GPU glyph atlas for high-performance ASCII rendering.
/// Pre-renders all ASCII characters to a texture atlas for single-draw-call rendering.
public final class GlyphAtlas: @unchecked Sendable {

    // MARK: - Properties

    /// The atlas texture containing all glyphs
    public let texture: MTLTexture

    /// Size of each glyph cell in the atlas
    public let cellSize: CGSize

    /// Number of columns in the atlas
    public let atlasColumns: Int

    /// Number of rows in the atlas
    public let atlasRows: Int

    /// Characters in the atlas (ASCII 32-126)
    public let characters: [Character]

    // MARK: - Initialization

    /// Create a glyph atlas for the given font.
    public init(device: MTLDevice, font: NSFont) throws {
        // ASCII printable range: 32-126 (95 characters)
        let startChar: UInt8 = 32
        let endChar: UInt8 = 126

        // Store characters
        characters = (startChar...endChar).map { Character(UnicodeScalar($0)) }

        // Calculate cell size from font metrics
        let testString = "M" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let charSize = testString.size(withAttributes: attrs)

        // Add padding for anti-aliasing
        let paddedWidth = ceil(charSize.width) + 2
        let paddedHeight = ceil(charSize.height) + 2
        cellSize = CGSize(width: paddedWidth, height: paddedHeight)

        // Calculate atlas dimensions (16x6 = 96 cells, fits 95 chars)
        atlasColumns = 16
        atlasRows = 6

        let atlasWidth = Int(cellSize.width) * atlasColumns
        let atlasHeight = Int(cellSize.height) * atlasRows

        // Create texture
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        textureDesc.usage = [.shaderRead]
        textureDesc.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: textureDesc) else {
            throw GlyphAtlasError.textureCreationFailed
        }
        self.texture = texture

        // Render glyphs to bitmap
        let bytesPerRow = atlasWidth
        var bitmapData = [UInt8](repeating: 0, count: atlasWidth * atlasHeight)

        // Create Core Graphics context
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: &bitmapData,
                width: atlasWidth,
                height: atlasHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            throw GlyphAtlasError.contextCreationFailed
        }

        // Setup context
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)

        // Render each character
        let ctFont = font as CTFont

        for (index, char) in characters.enumerated() {
            let col = index % atlasColumns
            let row = index / atlasColumns

            let x = CGFloat(col) * cellSize.width + 1  // +1 for padding
            let y = CGFloat(atlasRows - 1 - row) * cellSize.height + 1  // Flip Y

            // Create glyph
            var glyph = CTFontGetGlyphWithName(ctFont, String(char) as CFString)
            if glyph == 0 {
                // Fallback: get glyph from character
                var unichars = [UniChar](String(char).utf16)
                var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
                CTFontGetGlyphsForCharacters(ctFont, &unichars, &glyphs, unichars.count)
                glyph = glyphs[0]
            }

            // Get glyph bounding box for centering
            var boundingRect = CGRect.zero
            CTFontGetBoundingRectsForGlyphs(ctFont, .default, [glyph], &boundingRect, 1)

            // Draw glyph
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))

            var position = CGPoint(
                x: x + (cellSize.width - boundingRect.width) / 2 - boundingRect.origin.x,
                y: y + font.descender + (cellSize.height - charSize.height) / 2
            )

            CTFontDrawGlyphs(ctFont, [glyph], &position, 1, context)
        }

        // Upload to texture
        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1)
            ),
            mipmapLevel: 0,
            withBytes: bitmapData,
            bytesPerRow: bytesPerRow
        )
    }

    /// Get the UV coordinates for a character.
    public func uvForCharacter(_ char: Character) -> (u: Float, v: Float, width: Float, height: Float) {
        let ascii = char.asciiValue ?? 32
        let index = Int(ascii) - 32
        let clampedIndex = max(0, min(index, characters.count - 1))

        let col = clampedIndex % atlasColumns
        let row = clampedIndex / atlasColumns

        let u = Float(col) / Float(atlasColumns)
        let v = Float(row) / Float(atlasRows)
        let width = 1.0 / Float(atlasColumns)
        let height = 1.0 / Float(atlasRows)

        return (u, v, width, height)
    }
}

// MARK: - Errors

public enum GlyphAtlasError: Error {
    case textureCreationFailed
    case contextCreationFailed
}

// swiftlint:enable function_body_length

#endif // os(macOS)
