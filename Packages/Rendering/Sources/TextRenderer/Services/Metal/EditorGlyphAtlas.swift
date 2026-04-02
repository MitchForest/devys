// EditorGlyphAtlas.swift
// DevysTextRenderer - Shared Metal text rendering
//
// GPU texture atlas containing pre-rendered glyphs.

import Foundation
import OSLog
import Metal
import CoreText

private let logger = Logger(subsystem: "com.devys.textrenderer", category: "EditorGlyphAtlas")
import CoreGraphics

// MARK: - Glyph Atlas Entry

/// Information about a glyph in the atlas
public struct GlyphAtlasEntry: Sendable {
    /// UV origin in atlas (normalized 0-1)
    public let uvOrigin: SIMD2<Float>
    
    /// UV size in atlas (normalized 0-1)
    public let uvSize: SIMD2<Float>
    
    /// Glyph advance width
    public let advance: Float
    
    public init(uvOrigin: SIMD2<Float>, uvSize: SIMD2<Float>, advance: Float) {
        self.uvOrigin = uvOrigin
        self.uvSize = uvSize
        self.advance = advance
    }
    
    /// Empty entry for missing glyphs
    public static let empty = GlyphAtlasEntry(
        uvOrigin: .zero,
        uvSize: .zero,
        advance: 8
    )
}

// MARK: - Glyph Atlas

/// Manages a texture atlas of pre-rendered glyphs for GPU text rendering.
@MainActor
public final class EditorGlyphAtlas {
    
    // MARK: - Properties
    
    private let device: MTLDevice
    
    /// The GPU texture containing all glyphs
    public private(set) var texture: MTLTexture?
    
    /// Atlas dimensions (in pixels)
    public let atlasWidth: Int
    public let atlasHeight: Int
    
    /// Cell dimensions in points
    public let cellWidth: Int
    public let cellHeight: Int
    
    /// Cell dimensions in pixels (scaled for Retina)
    private let cellWidthPixels: Int
    private let cellHeightPixels: Int
    
    /// Scale factor for Retina displays
    public let scaleFactor: CGFloat
    
    /// Font used for rendering
    private let font: CTFont
    
    /// Mapping from character to atlas entry
    private var glyphMap: [Character: GlyphAtlasEntry] = [:]
    
    /// Current packing position (in pixels)
    private var packX: Int = 0
    private var packY: Int = 0
    private var rowHeight: Int = 0
    
    /// Bitmap buffer for CPU-side rendering
    private var bitmapData: [UInt8]
    
    /// Characters to pre-render at startup
    private static let preloadCharacters: [Character] = {
        var chars: [Character] = []
        // Printable ASCII (0x20-0x7E)
        for code in 0x20...0x7E {
            if let scalar = UnicodeScalar(code) {
                chars.append(Character(scalar))
            }
        }
        return chars
    }()
    
    // MARK: - Initialization
    
    /// Create a glyph atlas for the given font
    public init(
        device: MTLDevice,
        fontName: String = "Menlo",
        fontSize: CGFloat = 13,
        scaleFactor: CGFloat = 2.0,
        atlasSize: Int = 2048
    ) {
        self.device = device
        self.scaleFactor = scaleFactor
        self.atlasWidth = atlasSize
        self.atlasHeight = atlasSize
        
        // Create font
        self.font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        
        // Calculate cell size from font metrics
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        
        var glyph: CGGlyph = 0
        let charValue = "M".unicodeScalars.first?.value ?? 77
        var char = UniChar(charValue)
        CTFontGetGlyphsForCharacters(font, &char, &glyph, 1)
        var advance: CGSize = .zero
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        
        self.cellWidth = Int(ceil(advance.width))
        self.cellHeight = Int(ceil(ascent + descent + leading))
        
        self.cellWidthPixels = Int(ceil(CGFloat(cellWidth) * scaleFactor))
        self.cellHeightPixels = Int(ceil(CGFloat(cellHeight) * scaleFactor))
        
        // Allocate bitmap buffer (RGBA)
        self.bitmapData = [UInt8](repeating: 0, count: atlasWidth * atlasHeight * 4)
        
        // Pre-render common characters
        preloadGlyphs()
        
        // Create GPU texture
        createTexture()
    }
    
    // MARK: - Glyph Lookup
    
    /// Get atlas entry for a character
    public func entry(for char: Character) -> GlyphAtlasEntry {
        if let entry = glyphMap[char] {
            return entry
        }
        
        // Character not in atlas - try to add it
        if addGlyph(char) {
            updateTexture()
            return glyphMap[char] ?? .empty
        }
        
        // Failed to add - return space as fallback
        return glyphMap[" "] ?? .empty
    }
    
    // MARK: - Glyph Rendering
    
    private func preloadGlyphs() {
        for char in Self.preloadCharacters {
            _ = addGlyph(char)
        }
    }
    
    @discardableResult
    private func addGlyph(_ char: Character) -> Bool {
        if glyphMap[char] != nil {
            return true
        }
        
        if packY + cellHeightPixels > atlasHeight {
            return false
        }
        
        guard let glyphInfo = renderGlyph(char) else {
            return false
        }
        
        if packX + cellWidthPixels > atlasWidth {
            packX = 0
            packY += rowHeight
            rowHeight = 0
            
            if packY + cellHeightPixels > atlasHeight {
                return false
            }
        }
        
        // Copy glyph bitmap to atlas
        for y in 0..<glyphInfo.height {
            for x in 0..<glyphInfo.width {
                let srcIdx = (y * glyphInfo.width + x) * 4
                let dstX = packX + x
                let dstY = packY + y
                let dstIdx = (dstY * atlasWidth + dstX) * 4
                
                if srcIdx + 3 < glyphInfo.bitmap.count && dstIdx + 3 < bitmapData.count {
                    bitmapData[dstIdx + 0] = glyphInfo.bitmap[srcIdx + 0]
                    bitmapData[dstIdx + 1] = glyphInfo.bitmap[srcIdx + 1]
                    bitmapData[dstIdx + 2] = glyphInfo.bitmap[srcIdx + 2]
                    bitmapData[dstIdx + 3] = glyphInfo.bitmap[srcIdx + 3]
                }
            }
        }
        
        let uvOrigin = SIMD2<Float>(
            Float(packX) / Float(atlasWidth),
            Float(packY) / Float(atlasHeight)
        )
        let uvSize = SIMD2<Float>(
            Float(glyphInfo.width) / Float(atlasWidth),
            Float(glyphInfo.height) / Float(atlasHeight)
        )
        
        glyphMap[char] = GlyphAtlasEntry(
            uvOrigin: uvOrigin,
            uvSize: uvSize,
            advance: Float(glyphInfo.advance)
        )
        
        packX += cellWidthPixels
        rowHeight = max(rowHeight, cellHeightPixels)
        
        return true
    }
    
    private struct RenderedGlyph {
        let bitmap: [UInt8]
        let width: Int
        let height: Int
        let advance: Int
    }
    
    private func renderGlyph(_ char: Character) -> RenderedGlyph? {
        let string = String(char)
        let width = cellWidthPixels
        let height = cellHeightPixels
        
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        context.scaleBy(x: scaleFactor, y: scaleFactor)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        
        let attributes: [CFString: Any] = [kCTFontAttributeName: font]
        guard let attrString = CFAttributedStringCreate(
            nil,
            string as CFString,
            attributes as CFDictionary
        ) else {
            return nil
        }
        let line = CTLineCreateWithAttributedString(attrString)
        
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        
        context.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, context)
        
        return RenderedGlyph(
            bitmap: pixels,
            width: width,
            height: height,
            advance: Int(ceil(lineWidth))
        )
    }
    
    // MARK: - Texture Management
    
    private func createTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.storageMode = .managed
        descriptor.usage = .shaderRead
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            logger.error("Failed to create texture")
            return
        }
        
        self.texture = texture
        updateTexture()
    }
    
    private func updateTexture() {
        guard let texture = texture else { return }
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: atlasWidth, height: atlasHeight, depth: 1)
        )
        
        bitmapData.withUnsafeBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: baseAddress,
                bytesPerRow: atlasWidth * 4
            )
        }
    }
    
    // MARK: - Statistics
    
    public var glyphCount: Int { glyphMap.count }
    
    public func hasGlyph(_ char: Character) -> Bool {
        glyphMap[char] != nil
    }
}
