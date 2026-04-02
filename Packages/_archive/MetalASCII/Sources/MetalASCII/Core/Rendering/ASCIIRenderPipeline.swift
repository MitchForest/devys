// ASCIIRenderPipeline.swift
// DevysUI - Metal pipeline for shape-aware ASCII art rendering
//
// Uses 9-region sampling and 5-weight character matching for high-quality
// ASCII art that preserves edges and directional detail.
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import Foundation
import Metal
import MetalKit
import AppKit
import simd

// swiftlint:disable function_body_length

// MARK: - ASCII Uniforms

/// Uniform structure matching Metal shader
public struct ASCIIUniforms {
    var viewportSize: SIMD2<Float>
    var imageSize: SIMD2<Float>
    var cellSize: SIMD2<Float>
    var foregroundColor: SIMD4<Float>
    var backgroundColor: SIMD4<Float>
    var invertBrightness: UInt32
    var contrastBoost: Float
    var gamma: Float
    var charCount: UInt32

    public init() {
        viewportSize = .zero
        imageSize = .zero
        cellSize = SIMD2<Float>(8, 16)
        foregroundColor = SIMD4<Float>(1, 1, 1, 1)
        backgroundColor = SIMD4<Float>(0.05, 0.05, 0.07, 1)
        invertBrightness = 0
        contrastBoost = 1.2
        gamma = 1.0
        charCount = 95
    }
}

// MARK: - ASCII Render Pipeline

/// Metal-based pipeline for rendering images as high-quality ASCII art.
///
/// Uses shape-aware character matching with 5-directional weights:
/// - Samples 9 regions per character cell (3x3 grid)
/// - Computes directional weights (top, bottom, left, right, middle)
/// - Matches to best ASCII character by L1 distance
///
/// Falls back to CPU-based rendering if Metal is unavailable.
public final class ASCIIRenderPipeline: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared: ASCIIRenderPipeline = {
        do {
            return try ASCIIRenderPipeline()
        } catch {
            fatalError("Failed to create ASCIIRenderPipeline: \(error)")
        }
    }()

    // MARK: - Properties

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    private let renderPipelineState: MTLRenderPipelineState
    private let fontTexture: MTLTexture
    private let textureLoader: MTKTextureLoader

    // Character weight buffers
    private let characterWeightsBuffer: MTLBuffer
    private let characterCodesBuffer: MTLBuffer
    private let characterCount: Int

    // MARK: - Errors

    public enum ASCIIPipelineError: Error {
        case noMetalDevice
        case shaderNotFound
        case pipelineCreationFailed(String)
        case fontTextureNotFound
        case textureCreationFailed
        case bufferCreationFailed
    }

    // MARK: - Initialization

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw ASCIIPipelineError.noMetalDevice
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw ASCIIPipelineError.pipelineCreationFailed("Failed to create command queue")
        }
        self.commandQueue = queue
        self.textureLoader = MTKTextureLoader(device: device)

        // Load shaders from embedded source
        let shaderSource = ShaderLoader.getASCIIArtShaderSource()
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            metalASCIILog("Shader compilation error: \(error)")
            throw ASCIIPipelineError.shaderNotFound
        }

        guard let vertexFunction = library.makeFunction(name: "asciiVertexShader"),
              let fragmentFunction = library.makeFunction(name: "asciiArtFragment") else {
            throw ASCIIPipelineError.shaderNotFound
        }

        // Create render pipeline
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb

        do {
            self.renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw ASCIIPipelineError.pipelineCreationFailed(error.localizedDescription)
        }

        // Load or generate font texture (expanded for 95 chars)
        self.fontTexture = try Self.loadOrGenerateFontTexture(device: device, loader: textureLoader)

        // Load character weights
        let weightTable = CharacterWeightGenerator.sharedWeightTable
        self.characterCount = weightTable.characters.count

        // Create weight buffer
        var flatWeights = weightTable.flatWeights
        guard let weightsBuffer = device.makeBuffer(
            bytes: &flatWeights,
            length: flatWeights.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            throw ASCIIPipelineError.bufferCreationFailed
        }
        self.characterWeightsBuffer = weightsBuffer

        // Create codes buffer
        var codes = weightTable.asciiCodes
        guard let codesBuffer = device.makeBuffer(
            bytes: &codes,
            length: codes.count * MemoryLayout<Int32>.stride,
            options: .storageModeShared
        ) else {
            throw ASCIIPipelineError.bufferCreationFailed
        }
        self.characterCodesBuffer = codesBuffer
    }

    // MARK: - Font Texture

    private static func loadOrGenerateFontTexture(device: MTLDevice, loader: MTKTextureLoader) throws -> MTLTexture {
        // Try to load bundled font texture
        if let url = Bundle.module.url(forResource: "ascii-font-texture", withExtension: "png"),
           let texture = try? loader.newTexture(URL: url, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .SRGB: false
           ]) {
            return texture
        }

        // Generate font texture programmatically
        return try generateFontTexture(device: device)
    }

    /// Generate font texture with all 95 printable ASCII characters
    /// Grid: 16 columns × 6 rows, Cell size: 16×24 pixels
    /// Texture size: 256×144 pixels
    private static func generateFontTexture(device: MTLDevice) throws -> MTLTexture {
        let cellWidth = 16
        let cellHeight = 24
        let cols = 16
        let rows = 6
        let textureWidth = cellWidth * cols   // 256
        let textureHeight = cellHeight * rows // 144

        // Create NSImage with font characters
        let image = NSImage(size: NSSize(width: textureWidth, height: textureHeight))
        image.lockFocus()

        // Clear to transparent/black
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

            let col = i % cols
            let row = i / cols

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
            throw ASCIIPipelineError.textureCreationFailed
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: textureWidth,
            height: textureHeight,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderRead

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw ASCIIPipelineError.textureCreationFailed
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
            throw ASCIIPipelineError.textureCreationFailed
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: textureWidth, height: textureHeight))

        texture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                              size: MTLSize(width: textureWidth, height: textureHeight, depth: 1)),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: bytesPerRow
        )

        return texture
    }

    // MARK: - Rendering

    /// Render an image to ASCII art as an NSImage.
    ///
    /// - Parameters:
    ///   - image: Source image to convert
    ///   - size: Output size in points
    ///   - foregroundColor: Color for ASCII characters
    ///   - backgroundColor: Background color
    ///   - invert: Whether to invert brightness
    ///   - contrast: Contrast boost (1.0 = normal)
    ///   - gamma: Gamma correction (1.0 = linear, <1 = brighter, >1 = darker)
    ///   - columns: Number of character columns
    /// - Returns: Rendered ASCII art as NSImage
    public func render(
        image: NSImage,
        size: CGSize,
        foregroundColor: NSColor,
        backgroundColor: NSColor,
        invert: Bool = false,
        contrast: Float = 1.2,
        gamma: Float = 0.9,
        columns: Int? = nil
    ) async throws -> NSImage {
        // Convert NSImage to texture
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ASCIIPipelineError.textureCreationFailed
        }

        let sourceTexture = try await textureLoader.newTexture(cgImage: cgImage, options: [
            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .SRGB: false
        ])

        // Calculate cell size based on columns
        let effectiveColumns = columns ?? Int(size.width / 8)
        let cellWidth = Float(size.width) / Float(effectiveColumns)
        let cellHeight = cellWidth * 2 // Typical monospace aspect ratio

        // Set up uniforms
        var uniforms = ASCIIUniforms()
        uniforms.viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
        uniforms.imageSize = SIMD2<Float>(Float(cgImage.width), Float(cgImage.height))
        uniforms.cellSize = SIMD2<Float>(cellWidth, cellHeight)
        uniforms.invertBrightness = invert ? 1 : 0
        uniforms.contrastBoost = contrast
        uniforms.gamma = gamma
        uniforms.charCount = UInt32(characterCount)

        // Convert colors
        if let fgRGB = foregroundColor.usingColorSpace(.deviceRGB) {
            uniforms.foregroundColor = SIMD4<Float>(
                Float(fgRGB.redComponent),
                Float(fgRGB.greenComponent),
                Float(fgRGB.blueComponent),
                Float(fgRGB.alphaComponent)
            )
        }

        if let bgRGB = backgroundColor.usingColorSpace(.deviceRGB) {
            uniforms.backgroundColor = SIMD4<Float>(
                Float(bgRGB.redComponent),
                Float(bgRGB.greenComponent),
                Float(bgRGB.blueComponent),
                Float(bgRGB.alphaComponent)
            )
        }

        // Create output texture
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: Int(size.width),
            height: Int(size.height),
            mipmapped: false
        )
        outputDescriptor.usage = [.renderTarget, .shaderRead]

        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor) else {
            throw ASCIIPipelineError.textureCreationFailed
        }

        // Render
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw ASCIIPipelineError.pipelineCreationFailed("Failed to create command buffer")
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(uniforms.backgroundColor.x),
            green: Double(uniforms.backgroundColor.y),
            blue: Double(uniforms.backgroundColor.z),
            alpha: 1.0
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw ASCIIPipelineError.pipelineCreationFailed("Failed to create render encoder")
        }

        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentTexture(fontTexture, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ASCIIUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(characterWeightsBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(characterCodesBuffer, offset: 0, index: 2)

        // Draw full-screen quad
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.commit()
        await commandBuffer.completed()

        // Convert texture to NSImage
        return try textureToImage(outputTexture)
    }

    /// Convert MTLTexture to NSImage
    private func textureToImage(_ texture: MTLTexture) throws -> NSImage {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)

        texture.getBytes(
            &pixels,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )

        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ),
        let cgImage = context.makeImage() else {
            throw ASCIIPipelineError.textureCreationFailed
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    // MARK: - CPU Fallback

    /// CPU-based ASCII art rendering fallback with shape-aware matching.
    /// Used when Metal is unavailable.
    public func renderCPU(
        image: NSImage,
        columns: Int = 80,
        foregroundColor: NSColor = .white,
        backgroundColor: NSColor = .black,
        invert: Bool = false
    ) -> NSImage? {
        let generator = ShapeAwareASCIIGenerator()
        generator.invertBrightness = invert

        return generator.renderToImage(
            image: image,
            columns: columns,
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor
        )
    }
}

// MARK: - Shape-Aware ASCII Generator (CPU Fallback)

/// CPU-based ASCII art generator with shape-aware character matching.
public final class ShapeAwareASCIIGenerator: @unchecked Sendable {

    private let weightTable: CharacterWeightTable

    public var invertBrightness: Bool = false
    public var contrastBoost: Float = 1.2
    public var gamma: Float = 0.9

    public init() {
        self.weightTable = CharacterWeightGenerator.sharedWeightTable
    }

    /// Convert image to ASCII text using shape-aware matching
    public func convert(image: NSImage, columns: Int = 80, aspectRatio: Double = 0.5) -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        let width = cgImage.width
        let height = cgImage.height

        // Calculate sampling dimensions
        let cellWidth = max(1, width / columns)
        let rows = Int(Double(height) / Double(cellWidth) * aspectRatio)
        let cellHeight = max(1, height / rows)

        // Create bitmap context for pixel access
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return ""
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return ""
        }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var result = ""

        for row in 0..<rows {
            for col in 0..<columns {
                let cellX = col * cellWidth
                let cellY = row * cellHeight

                // Sample 9 regions within the cell
                let weights = sampleCellWeights(
                    pixels: pixels,
                    width: width,
                    cellX: cellX,
                    cellY: cellY,
                    cellWidth: min(cellWidth, width - cellX),
                    cellHeight: min(cellHeight, height - cellY)
                )

                // Find best matching character
                let bestChar = findBestCharacter(weights: weights)
                result.append(bestChar)
            }
            result.append("\n")
        }

        return result
    }

    /// Sample 9 regions in a cell and return 5 directional weights
    private func sampleCellWeights(
        pixels: UnsafePointer<UInt8>,
        width: Int,
        cellX: Int,
        cellY: Int,
        cellWidth: Int,
        cellHeight: Int
    ) -> [Float] {
        // Calculate region dimensions
        let regionWidth = max(1, cellWidth / 3)
        let regionHeight = max(1, cellHeight / 3)

        var regions = [Float](repeating: 0, count: 9)

        for ry in 0..<3 {
            for rx in 0..<3 {
                let startX = cellX + rx * regionWidth
                let startY = cellY + ry * regionHeight
                let endX = min(startX + regionWidth, cellX + cellWidth)
                let endY = min(startY + regionHeight, cellY + cellHeight)

                var total: Float = 0
                var count = 0

                for y in startY..<endY {
                    for x in startX..<endX {
                        let pixelIndex = (y * width + x) * 4
                        let r = Float(pixels[pixelIndex])
                        let g = Float(pixels[pixelIndex + 1])
                        let b = Float(pixels[pixelIndex + 2])

                        // Luminance formula
                        var brightness = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0

                        // Apply gamma
                        brightness = pow(brightness, gamma)

                        // Apply inversion
                        if invertBrightness {
                            brightness = 1.0 - brightness
                        }

                        // Apply contrast
                        brightness = (brightness - 0.5) * contrastBoost + 0.5
                        brightness = max(0, min(1, brightness))

                        total += brightness
                        count += 1
                    }
                }

                regions[ry * 3 + rx] = count > 0 ? total / Float(count) : 0
            }
        }

        // Convert 9 regions to 5 weights
        let tl = regions[0], t = regions[1], tr = regions[2]
        let l = regions[3], m = regions[4], r = regions[5]
        let bl = regions[6], b = regions[7], br = regions[8]

        return [
            (tl + t + tr) / 3.0,   // top
            (bl + b + br) / 3.0,   // bottom
            (tl + l + bl) / 3.0,   // left
            (tr + r + br) / 3.0,   // right
            m                       // middle
        ]
    }

    /// Find best matching character using L1 distance
    private func findBestCharacter(weights: [Float]) -> Character {
        var bestChar: Character = " "
        var bestDistance = Float.greatestFiniteMagnitude

        for charWeight in weightTable.characters {
            var distance: Float = 0
            for i in 0..<5 {
                distance += abs(weights[i] - charWeight.weights[i])
            }

            if distance < bestDistance {
                bestDistance = distance
                bestChar = Character(charWeight.character)
            }
        }

        return bestChar
    }

    /// Render to NSImage
    public func renderToImage(
        image: NSImage,
        columns: Int = 60,
        foregroundColor: NSColor = .white,
        backgroundColor: NSColor = .clear,
        fontSize: CGFloat = 8
    ) -> NSImage? {
        let asciiText = convert(image: image, columns: columns)

        guard !asciiText.isEmpty else { return nil }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: foregroundColor
        ]

        let attributedString = NSAttributedString(string: asciiText, attributes: attributes)
        let size = attributedString.size()

        let resultImage = NSImage(size: size, flipped: false) { rect in
            if backgroundColor != .clear {
                backgroundColor.setFill()
                rect.fill()
            }
            attributedString.draw(at: .zero)
            return true
        }

        return resultImage
    }
}

// swiftlint:enable function_body_length

#endif // os(macOS)
