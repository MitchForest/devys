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
        let fontIdentifier: String
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
    private let fontStack: TerminalFontStack
    private let primaryFontIdentifier: String
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
        let fontStack = TerminalFontStack(primaryFontName: fontName, fontSize: fontSize)
        self.fontStack = fontStack
        self.primaryFontIdentifier = CTFontCopyPostScriptName(fontStack.primaryFont) as String
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
        let resolved = fontStack.resolve(grapheme: normalizedGrapheme)
        let key = GlyphKey(
            grapheme: resolved.grapheme,
            cellSpan: max(cellSpan, 1),
            fontIdentifier: resolved.fontIdentifier
        )

        if let entry = glyphMap[key] {
            return entry
        }

        prepareGlyphs(for: [TerminalGlyphRequest(grapheme: normalizedGrapheme, cellSpan: key.cellSpan)])
        guard let entry = glyphMap[key] else {
            terminalGlyphLogger.error("Missing glyph atlas entry for '\(normalizedGrapheme, privacy: .public)'")
            let fallback = fontStack.resolve(grapheme: "?")
            return glyphMap[
                GlyphKey(
                    grapheme: fallback.grapheme,
                    cellSpan: 1,
                    fontIdentifier: fallback.fontIdentifier
                )
            ] ?? .empty
        }
        return entry
    }

    public func prepareGlyphs(for requests: [TerminalGlyphRequest]) {
        var uploadBounds: AtlasUploadBounds?

        for request in requests {
            let normalizedGrapheme = request.grapheme.isEmpty ? " " : request.grapheme
            let resolved = fontStack.resolve(grapheme: normalizedGrapheme)
            let key = GlyphKey(
                grapheme: resolved.grapheme,
                cellSpan: max(request.cellSpan, 1),
                fontIdentifier: resolved.fontIdentifier
            )
            guard glyphMap[key] == nil else { continue }
            guard let mutationBounds = addGlyph(for: key, resolved: resolved) else { continue }
            updateLocalUploadBounds(&uploadBounds, with: mutationBounds)
        }

        guard let uploadBounds else { return }
        runtimeMutationCount += 1
        onAtlasMutation()
        updateTexture(uploadBounds: uploadBounds)
    }

    private func preloadGlyphs() {
        for request in Self.preloadRequests {
            let resolved = fontStack.resolve(grapheme: request.grapheme)
            let key = GlyphKey(
                grapheme: resolved.grapheme,
                cellSpan: request.cellSpan,
                fontIdentifier: resolved.fontIdentifier
            )
            _ = addGlyph(for: key, resolved: resolved)
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

    private func addGlyph(for key: GlyphKey, resolved: TerminalResolvedGlyph) -> AtlasUploadBounds? {
        guard glyphMap[key] == nil else { return nil }
        guard let rendered = renderGlyph(resolved: resolved, cellSpan: key.cellSpan) else { return nil }

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
        resolved: TerminalResolvedGlyph,
        cellSpan: Int
    ) -> RenderedGlyph? {
        let width = max(cellWidthPixels * max(cellSpan, 1), 1)
        let height = max(cellHeightPixels, 1)

        if resolved.fontIdentifier == TerminalFontStack.specialRasterizerFontIdentifier,
           let specialGlyph = TerminalSpecialGlyphRasterizer.bitmap(
               for: resolved.grapheme,
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

        let drawableGrapheme = resolved.isMissing ? "?" : resolved.grapheme
        let attributes: [CFString: Any] = [kCTFontAttributeName: resolved.font]
        guard let attrString = CFAttributedStringCreate(
            nil,
            drawableGrapheme as CFString,
            attributes as CFDictionary
        ) else {
            return nil
        }

        let line = CTLineCreateWithAttributedString(attrString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let glyphBounds = lineGlyphBounds(line: line, ascent: ascent, descent: descent)
        let cellWidthPoints = CGFloat(width) / scaleFactor
        let cellHeightPoints = CGFloat(height) / scaleFactor
        let shouldFitAsSymbol = resolved.fontIdentifier != primaryFontIdentifier &&
            glyphBoundsExceedCell(glyphBounds, cellWidth: cellWidthPoints, cellHeight: cellHeightPoints)

        let horizontalScale: CGFloat
        let verticalScale: CGFloat
        let baselineX: CGFloat
        let baselineY: CGFloat

        if shouldFitAsSymbol {
            horizontalScale = min(1, cellWidthPoints / max(glyphBounds.width, 1))
            verticalScale = min(1, cellHeightPoints / max(glyphBounds.height, 1))
            baselineX = ((cellWidthPoints - glyphBounds.width * horizontalScale) / 2) -
                glyphBounds.minX * horizontalScale
            baselineY = ((cellHeightPoints - glyphBounds.height * verticalScale) / 2) -
                glyphBounds.minY * verticalScale
        } else {
            horizontalScale = 1
            verticalScale = 1
            baselineX = max(0, (cellWidthPoints - lineWidth) / 2)
            baselineY = descent
        }

        context.saveGState()
        context.translateBy(x: baselineX, y: baselineY)
        context.scaleBy(x: horizontalScale, y: verticalScale)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()

        return RenderedGlyph(bitmap: pixels, width: width, height: height)
    }

    private func glyphBoundsExceedCell(
        _ bounds: CGRect,
        cellWidth: CGFloat,
        cellHeight: CGFloat
    ) -> Bool {
        bounds.minX < 0 ||
            bounds.minY < 0 ||
            bounds.maxX > cellWidth ||
            bounds.maxY > cellHeight
    }

    private func lineGlyphBounds(
        line: CTLine,
        ascent: CGFloat,
        descent: CGFloat
    ) -> CGRect {
        let pathBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        if pathBounds.isNull || pathBounds.isEmpty {
            let typographicWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            return CGRect(
                x: 0,
                y: -descent,
                width: typographicWidth,
                height: ascent + descent
            )
        }
        return pathBounds
    }

    func renderedBitmapForTesting(grapheme: String, cellSpan: Int) -> [UInt8]? {
        let resolved = fontStack.resolve(grapheme: grapheme.isEmpty ? " " : grapheme)
        return renderGlyph(resolved: resolved, cellSpan: max(cellSpan, 1))?.bitmap
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
