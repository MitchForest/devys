// FlowerScene.swift
// MetalASCII - Animated flower with dithering and wind motion
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import MetalKit
import simd

// swiftlint:disable function_body_length

// MARK: - Flower Scene

/// ASCII art flower with dithering and wind animation.
///
/// Features:
/// - Procedural rose-curve petals
/// - Simplex noise wind displacement
/// - Bayer ordered dithering
/// - 60fps GPU-accelerated rendering
public final class FlowerScene: ASCIIScene, @unchecked Sendable {

    public let name = "Flower"
    public let description = "Animated flower with wind motion and dithering"

    // MARK: - Metal State

    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private var flowerPipeline: MTLRenderPipelineState?
    private var ditherComputePipeline: MTLComputePipelineState?

    // MARK: - Buffers & Textures

    private var quadVertexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var cellBuffer: MTLBuffer?
    private var flowerTexture: MTLTexture?

    // MARK: - Animation State

    private var time: Float = 0
    private var viewportSize: CGSize = .zero

    // MARK: - Configuration

    /// Number of ASCII columns
    public var columns: UInt32 = 120

    /// Number of ASCII rows (calculated from aspect ratio)
    public var rows: UInt32 = 40

    /// Dithering mode: 0=none, 1=bayer4x4, 2=bayer8x8
    public var ditherMode: UInt32 = 2

    /// Wind strength (0-1)
    public var windStrength: Float = 0.4

    /// Wind frequency
    public var windFrequency: Float = 1.0

    /// Wind speed
    public var windSpeed: Float = 0.8

    /// Number of petals
    public var petalCount: UInt32 = 5

    /// Number of petal layers
    public var petalLayers: UInt32 = 3

    /// Petal length (0-1)
    public var petalLength: Float = 0.8

    /// Stem height
    public var stemHeight: Float = 0.3

    // MARK: - ASCII Output

    /// The current ASCII art output (read after each frame)
    public private(set) var asciiOutput: [[Character]] = []

    /// Brightness values for each cell
    public private(set) var brightnessOutput: [[Float]] = []

    // MARK: - Initialization

    public required init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        try setupPipelines()
        setupBuffers()

        // Initialize with a default size
        resize(to: CGSize(width: 1200, height: 800))
    }

    private func setupPipelines() throws {
        // Compile shader from embedded source
        let shaderSource = ShaderLoader.getFlowerShaderSource()

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            metalASCIILog("Error compiling shaders: \(error)")
            return
        }

        // Flower render pipeline
        guard let vertexFunc = library.makeFunction(name: "flowerVertex"),
              let fragmentFunc = library.makeFunction(name: "flowerFragment") else {
            metalASCIILog("Error: Could not find flower vertex/fragment functions")
            return
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .r32Float

        flowerPipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)

        // Dither compute pipeline
        guard let computeFunc = library.makeFunction(name: "ditherAndConvert") else {
            metalASCIILog("Error: Could not find ditherAndConvert function")
            return
        }

        ditherComputePipeline = try device.makeComputePipelineState(function: computeFunc)
    }

    private func setupBuffers() {
        // Fullscreen quad vertices
        let quadVertices: [SIMD2<Float>] = [
            SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1),
            SIMD2(-1, 1), SIMD2(1, -1), SIMD2(1, 1)
        ]
        quadVertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: MemoryLayout<SIMD2<Float>>.stride * quadVertices.count,
            options: .storageModeShared
        )

        // Uniform buffer
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<FlowerUniformsGPU>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - ASCIIScene Protocol

    public func resize(to size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        viewportSize = size

        // Calculate rows based on aspect ratio (characters are ~2:1 aspect)
        let charAspect: Float = 0.5  // Height/width of a character
        let viewAspect = Float(size.height / size.width)
        rows = UInt32(Float(columns) * viewAspect * charAspect)
        rows = max(rows, 20)

        // Recreate textures
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: Int(columns) * 8,  // Higher res for sampling
            height: Int(rows) * 8,
            mipmapped: false
        )
        textureDesc.usage = [.renderTarget, .shaderRead]
        textureDesc.storageMode = .private
        flowerTexture = device.makeTexture(descriptor: textureDesc)

        // Recreate cell buffer
        let cellCount = Int(columns * rows)
        cellBuffer = device.makeBuffer(
            length: MemoryLayout<ASCIICellGPU>.stride * cellCount,
            options: .storageModeShared
        )

        // Initialize output arrays
        asciiOutput = Array(repeating: Array(repeating: " ", count: Int(columns)), count: Int(rows))
        brightnessOutput = Array(repeating: Array(repeating: 0, count: Int(columns)), count: Int(rows))
    }

    public func update(deltaTime: Float) {
        time += deltaTime

        // Update uniforms
        guard let uniformBuffer = uniformBuffer,
              let commandQueue = commandQueue else { return }

        var uniforms = FlowerUniformsGPU(
            time: time,
            windStrength: windStrength,
            windFrequency: windFrequency,
            windSpeed: windSpeed,
            ditherMode: ditherMode,
            columns: columns,
            rows: rows,
            viewportSize: SIMD2<Float>(Float(viewportSize.width), Float(viewportSize.height)),
            petalCount: petalCount,
            petalLayers: petalLayers,
            petalLength: petalLength,
            stemHeight: stemHeight,
            bloomPhase: 1.0
        )

        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<FlowerUniformsGPU>.stride)

        // Execute GPU rendering
        guard let flowerTexture = flowerTexture,
              let cellBuffer = cellBuffer,
              let quadVertexBuffer = quadVertexBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Step 1: Render flower to texture
        if let flowerPipeline = flowerPipeline {
            let flowerPassDesc = MTLRenderPassDescriptor()
            flowerPassDesc.colorAttachments[0].texture = flowerTexture
            flowerPassDesc.colorAttachments[0].loadAction = .clear
            flowerPassDesc.colorAttachments[0].storeAction = .store
            flowerPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: flowerPassDesc) {
                encoder.setRenderPipelineState(flowerPipeline)
                encoder.setVertexBuffer(quadVertexBuffer, offset: 0, index: 0)
                encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
                encoder.endEncoding()
            }
        }

        // Step 2: Dither and convert to ASCII (compute)
        if let ditherPipeline = ditherComputePipeline {
            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(ditherPipeline)
                encoder.setTexture(flowerTexture, index: 0)
                encoder.setBuffer(cellBuffer, offset: 0, index: 0)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 1)

                let threadsPerGrid = MTLSize(width: Int(columns), height: Int(rows), depth: 1)
                let threadsPerGroup = MTLSize(
                    width: min(16, Int(columns)),
                    height: min(16, Int(rows)),
                    depth: 1
                )

                encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
                encoder.endEncoding()
            }
        }

        // Use completion handler instead of blocking
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.readBackASCII()
            }
        }

        commandBuffer.commit()
    }

    public func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        // GPU work is now done in update() - just clear the render pass
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }

    private func readBackASCII() {
        guard let cellBuffer = cellBuffer else { return }

        let cellCount = Int(columns * rows)
        let cells = cellBuffer.contents().bindMemory(to: ASCIICellGPU.self, capacity: cellCount)

        for row in 0..<Int(rows) {
            for col in 0..<Int(columns) {
                let index = row * Int(columns) + col
                let cell = cells[index]
                asciiOutput[row][col] = Character(UnicodeScalar(cell.character))
                brightnessOutput[row][col] = Float(cell.brightness) / 255.0
            }
        }
    }

    /// Get the current frame as an ASCII string
    public func getASCIIString() -> String {
        return asciiOutput.map { String($0) }.joined(separator: "\n")
    }

    /// Print the current frame to console
    public func printFrame() {
        metalASCIILog("\u{1B}[2J\u{1B}[H")  // Clear screen and move cursor to top
        metalASCIILog(getASCIIString())
    }
}

// MARK: - GPU Structures

/// Matches FlowerUniforms in shader
struct FlowerUniformsGPU {
    var time: Float
    var windStrength: Float
    var windFrequency: Float
    var windSpeed: Float
    var ditherMode: UInt32
    var columns: UInt32
    var rows: UInt32
    var padding0: UInt32 = 0  // Padding for alignment
    var viewportSize: SIMD2<Float>
    var petalCount: UInt32
    var petalLayers: UInt32
    var petalLength: Float
    var stemHeight: Float
    var bloomPhase: Float
    var padding1: Float = 0
    var padding2: Float = 0
    var padding3: Float = 0
}

/// Matches ASCIICell in shader
struct ASCIICellGPU {
    var character: UInt8
    var brightness: UInt8
}

// DitherMode is now defined in Core/Engine/DitherEngine.swift

// swiftlint:enable function_body_length

#endif // os(macOS)
