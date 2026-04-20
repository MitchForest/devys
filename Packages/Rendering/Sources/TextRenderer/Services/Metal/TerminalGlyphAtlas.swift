import CoreGraphics
import CoreText
import Foundation
import Metal
import OSLog

private let terminalGlyphLogger = Logger(
    subsystem: "com.devys.textrenderer",
    category: "TerminalGlyphAtlas"
)

public struct TerminalGlyphAtlasEntry: Sendable, Equatable {
    public let uvOrigin: SIMD2<Float>
    public let uvSize: SIMD2<Float>

    public init(uvOrigin: SIMD2<Float>, uvSize: SIMD2<Float>) {
        self.uvOrigin = uvOrigin
        self.uvSize = uvSize
    }

    public static let empty = TerminalGlyphAtlasEntry(uvOrigin: .zero, uvSize: .zero)
}

public struct TerminalGlyphRequest: Sendable, Equatable {
    public let grapheme: String
    public let cellSpan: Int

    public init(grapheme: String, cellSpan: Int) {
        self.grapheme = grapheme
        self.cellSpan = max(cellSpan, 1)
    }
}

@MainActor
public final class TerminalGlyphAtlas {
    private struct GlyphKey: Hashable {
        let grapheme: String
        let cellSpan: Int
    }

    private struct RenderedGlyph {
        let bitmap: [UInt8]
        let width: Int
        let height: Int
    }

    private struct AtlasUploadBounds {
        var minX: Int
        var minY: Int
        var maxX: Int
        var maxY: Int

        init(x: Int, y: Int, width: Int, height: Int) {
            self.minX = x
            self.minY = y
            self.maxX = x + width
            self.maxY = y + height
        }

        mutating func formUnion(with other: AtlasUploadBounds) {
            minX = min(minX, other.minX)
            minY = min(minY, other.minY)
            maxX = max(maxX, other.maxX)
            maxY = max(maxY, other.maxY)
        }

        var width: Int { max(0, maxX - minX) }
        var height: Int { max(0, maxY - minY) }
    }

    private let device: MTLDevice
    private let font: CTFont
    private let cellWidthPixels: Int
    private let cellHeightPixels: Int
    private let scaleFactor: CGFloat
    private let onAtlasMutation: () -> Void

    public let atlasWidth: Int
    public let atlasHeight: Int
    public private(set) var texture: MTLTexture?

    private var glyphMap: [GlyphKey: TerminalGlyphAtlasEntry] = [:]
    private var packX = 0
    private var packY = 0
    private var rowHeight = 0
    private var bitmapData: [UInt8]
    private(set) var fullTextureUploadCount = 0
    private(set) var partialTextureUploadCount = 0
    public private(set) var runtimeMutationCount = 0

    private static let preloadRequests: [TerminalGlyphRequest] = {
        var requests = [
            TerminalGlyphRequest(grapheme: " ", cellSpan: 1),
            TerminalGlyphRequest(grapheme: "?", cellSpan: 1),
        ]
        for code in 0x20...0x7E {
            if let scalar = UnicodeScalar(code) {
                requests.append(
                    TerminalGlyphRequest(
                        grapheme: String(Character(scalar)),
                        cellSpan: 1
                    )
                )
            }
        }
        for code in 0x2580...0x259F {
            if let scalar = UnicodeScalar(code) {
                requests.append(
                    TerminalGlyphRequest(
                        grapheme: String(Character(scalar)),
                        cellSpan: 1
                    )
                )
            }
        }
        return requests
    }()

    public init(
        device: MTLDevice,
        fontName: String,
        fontSize: CGFloat,
        cellWidth: Int,
        cellHeight: Int,
        scaleFactor: CGFloat = 2,
        atlasSize: Int = 4096,
        onAtlasMutation: @escaping () -> Void = {}
    ) {
        self.device = device
        self.font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        self.cellWidthPixels = Int(ceil(CGFloat(cellWidth) * scaleFactor))
        self.cellHeightPixels = Int(ceil(CGFloat(cellHeight) * scaleFactor))
        self.scaleFactor = scaleFactor
        self.onAtlasMutation = onAtlasMutation
        self.atlasWidth = atlasSize
        self.atlasHeight = atlasSize
        self.bitmapData = [UInt8](repeating: 0, count: atlasSize * atlasSize * 4)
        preloadGlyphs()
        createTexture()
    }

    public func entry(for grapheme: String, cellSpan: Int) -> TerminalGlyphAtlasEntry {
        let normalizedGrapheme = grapheme.isEmpty ? " " : grapheme
        let key = GlyphKey(grapheme: normalizedGrapheme, cellSpan: max(cellSpan, 1))

        if let entry = glyphMap[key] {
            return entry
        }

        prepareGlyphs(for: [TerminalGlyphRequest(grapheme: normalizedGrapheme, cellSpan: key.cellSpan)])
        guard let entry = glyphMap[key] else {
            terminalGlyphLogger.error("Missing glyph atlas entry for '\(normalizedGrapheme, privacy: .public)'")
            return glyphMap[GlyphKey(grapheme: "?", cellSpan: 1)] ?? .empty
        }
        return entry
    }

    public func prepareGlyphs(for requests: [TerminalGlyphRequest]) {
        var uploadBounds: AtlasUploadBounds?

        for request in requests {
            let normalizedGrapheme = request.grapheme.isEmpty ? " " : request.grapheme
            let key = GlyphKey(grapheme: normalizedGrapheme, cellSpan: max(request.cellSpan, 1))
            guard glyphMap[key] == nil else { continue }
            guard let mutationBounds = addGlyph(for: key) else { continue }
            updateLocalUploadBounds(&uploadBounds, with: mutationBounds)
        }

        guard let uploadBounds else { return }
        runtimeMutationCount += 1
        onAtlasMutation()
        updateTexture(uploadBounds: uploadBounds)
    }

    private func preloadGlyphs() {
        for request in Self.preloadRequests {
            let key = GlyphKey(grapheme: request.grapheme, cellSpan: request.cellSpan)
            _ = addGlyph(for: key)
        }
    }

    private func updateLocalUploadBounds(
        _ uploadBounds: inout AtlasUploadBounds?,
        with mutationBounds: AtlasUploadBounds
    ) {
        if var existingBounds = uploadBounds {
            existingBounds.formUnion(with: mutationBounds)
            uploadBounds = existingBounds
        } else {
            uploadBounds = mutationBounds
        }
    }

    private func addGlyph(for key: GlyphKey) -> AtlasUploadBounds? {
        guard glyphMap[key] == nil else { return nil }
        guard let rendered = renderGlyph(grapheme: key.grapheme, cellSpan: key.cellSpan) else { return nil }

        if packX + rendered.width > atlasWidth {
            packX = 0
            packY += rowHeight
            rowHeight = 0
        }

        guard packY + rendered.height <= atlasHeight else { return nil }

        for y in 0..<rendered.height {
            for x in 0..<rendered.width {
                let srcIdx = (y * rendered.width + x) * 4
                let dstX = packX + x
                let dstY = packY + y
                let dstIdx = (dstY * atlasWidth + dstX) * 4
                bitmapData[dstIdx + 0] = rendered.bitmap[srcIdx + 0]
                bitmapData[dstIdx + 1] = rendered.bitmap[srcIdx + 1]
                bitmapData[dstIdx + 2] = rendered.bitmap[srcIdx + 2]
                bitmapData[dstIdx + 3] = rendered.bitmap[srcIdx + 3]
            }
        }

        glyphMap[key] = TerminalGlyphAtlasEntry(
            uvOrigin: SIMD2(
                Float(packX) / Float(atlasWidth),
                Float(packY) / Float(atlasHeight)
            ),
            uvSize: SIMD2(
                Float(rendered.width) / Float(atlasWidth),
                Float(rendered.height) / Float(atlasHeight)
            )
        )

        packX += rendered.width
        rowHeight = max(rowHeight, rendered.height)
        return AtlasUploadBounds(
            x: packX - rendered.width,
            y: packY,
            width: rendered.width,
            height: rendered.height
        )
    }

    private func renderGlyph(
        grapheme: String,
        cellSpan: Int
    ) -> RenderedGlyph? {
        let width = max(cellWidthPixels * max(cellSpan, 1), 1)
        let height = max(cellHeightPixels, 1)

        if let specialGlyph = TerminalSpecialGlyphRasterizer.bitmap(
            for: grapheme,
            cellWidth: width,
            cellHeight: height
        ) {
            return RenderedGlyph(
                bitmap: specialGlyph.rgba,
                width: specialGlyph.width,
                height: specialGlyph.height
            )
        }

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
            grapheme as CFString,
            attributes as CFDictionary
        ) else {
            return nil
        }

        let line = CTLineCreateWithAttributedString(attrString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        context.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, context)

        return RenderedGlyph(bitmap: pixels, width: width, height: height)
    }

    private func createTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        #if os(macOS)
        descriptor.storageMode = .managed
        #else
        descriptor.storageMode = .shared
        #endif
        descriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        self.texture = texture
        updateTexture(uploadBounds: nil)
    }

    private func updateTexture(uploadBounds: AtlasUploadBounds?) {
        guard let texture else { return }

        let bounds = uploadBounds
        let region = MTLRegion(
            origin: MTLOrigin(x: bounds?.minX ?? 0, y: bounds?.minY ?? 0, z: 0),
            size: MTLSize(
                width: bounds?.width ?? atlasWidth,
                height: bounds?.height ?? atlasHeight,
                depth: 1
            )
        )
        let bytesPerRow = atlasWidth * 4
        bitmapData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            let offset = ((bounds?.minY ?? 0) * atlasWidth + (bounds?.minX ?? 0)) * 4
            texture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: baseAddress.advanced(by: offset),
                bytesPerRow: bytesPerRow
            )
        }

        if bounds == nil {
            fullTextureUploadCount += 1
        } else {
            partialTextureUploadCount += 1
        }
    }
}
