// MetalASCIIRenderer.swift
// MetalASCII - GPU-accelerated ASCII art renderer using MTKView
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import MetalKit
import simd

// swiftlint:disable function_body_length

// MARK: - Metal ASCII Renderer

/// High-performance GPU-based ASCII renderer using MTKView.
/// Renders entire ASCII grid in a single draw call using instanced rendering.
public final class MetalASCIIRenderer: NSObject, MTKViewDelegate {

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let glyphAtlas: GlyphAtlas
    private var renderPipeline: MTLRenderPipelineState?

    // Buffers
    private var vertexBuffer: MTLBuffer?
    private var instanceBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    // Grid state
    private var gridCols: Int = 120
    private var gridRows: Int = 40
    private var maxInstances: Int = 0

    // Scene data (updated each frame)
    private var asciiData: [[Character]] = []
    private var brightnessData: [[Float]] = []

    // Colors
    public var foregroundColor: SIMD4<Float> = SIMD4(0.0, 1.0, 0.5, 1.0)  // Green
    public var backgroundColor: SIMD4<Float> = SIMD4(0.02, 0.02, 0.03, 1.0)

    // Callback for frame updates
    public var onFrameUpdate: ((Float) -> Void)?

    // FPS tracking
    private var lastFrameTime: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsUpdateTime: CFTimeInterval = 0
    public private(set) var fps: Double = 0

    // MARK: - GPU Structures

    /// Per-instance data for each ASCII cell
    struct GlyphInstance {
        var position: SIMD2<Float>      // Screen position
        var uvOffset: SIMD2<Float>      // UV offset in atlas
        var uvSize: SIMD2<Float>        // UV size in atlas
        var brightness: Float           // Brightness multiplier
        var padding: Float = 0
    }

    /// Uniform data
    struct Uniforms {
        var viewportSize: SIMD2<Float>
        var cellSize: SIMD2<Float>
        var foregroundColor: SIMD4<Float>
        var backgroundColor: SIMD4<Float>
    }

    // MARK: - Initialization

    public init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueueFailed
        }
        self.commandQueue = queue

        // Create glyph atlas
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        self.glyphAtlas = try GlyphAtlas(device: device, font: font)

        super.init()

        try setupPipeline()
        setupBuffers()
    }

    private func setupPipeline() throws {
        let shaderSource = Self.glyphShaderSource

        let library = try device.makeLibrary(source: shaderSource, options: nil)

        guard let vertexFunc = library.makeFunction(name: "glyphVertex"),
              let fragmentFunc = library.makeFunction(name: "glyphFragment") else {
            throw RendererError.shaderCompilationFailed
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFunc
        pipelineDesc.fragmentFunction = fragmentFunc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending
        pipelineDesc.colorAttachments[0].isBlendingEnabled = true
        pipelineDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        pipelineDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        renderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)
    }

    private func setupBuffers() {
        // Quad vertices (2 triangles)
        let vertices: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1),
            SIMD2(0, 1), SIMD2(1, 0), SIMD2(1, 1)
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<SIMD2<Float>>.stride * vertices.count,
            options: .storageModeShared
        )

        // Uniform buffer
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared
        )

        // Instance buffer (will be resized as needed)
        resizeInstanceBuffer(cols: gridCols, rows: gridRows)
    }

    private func resizeInstanceBuffer(cols: Int, rows: Int) {
        gridCols = cols
        gridRows = rows
        maxInstances = cols * rows

        instanceBuffer = device.makeBuffer(
            length: MemoryLayout<GlyphInstance>.stride * maxInstances,
            options: .storageModeShared
        )
    }

    // MARK: - Public API

    /// Update the ASCII grid data
    public func updateGrid(ascii: [[Character]], brightness: [[Float]]) {
        asciiData = ascii
        brightnessData = brightness

        // Resize if needed
        let newRows = ascii.count
        let newCols = ascii.first?.count ?? 0

        if newRows != gridRows || newCols != gridCols {
            resizeInstanceBuffer(cols: newCols, rows: newRows)
        }
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // View resized - handled in draw
    }

    public func draw(in view: MTKView) {
        // Calculate delta time
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastFrameTime == 0 ? 0.016 : Float(currentTime - lastFrameTime)
        lastFrameTime = currentTime

        // Update FPS
        frameCount += 1
        if currentTime - fpsUpdateTime >= 1.0 {
            fps = Double(frameCount) / (currentTime - fpsUpdateTime)
            frameCount = 0
            fpsUpdateTime = currentTime
        }

        // Call frame update callback (scene updates)
        onFrameUpdate?(deltaTime)

        // Render
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let pipeline = renderPipeline,
              let instanceBuffer = instanceBuffer,
              let uniformBuffer = uniformBuffer,
              let vertexBuffer = vertexBuffer else {
            return
        }

        // Update uniforms
        let viewportSize = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let cellWidth = viewportSize.x / Float(gridCols)
        let cellHeight = viewportSize.y / Float(gridRows)

        var uniforms = Uniforms(
            viewportSize: viewportSize,
            cellSize: SIMD2(cellWidth, cellHeight),
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Update instance buffer
        let instanceCount = updateInstances(
            buffer: instanceBuffer,
            cellSize: SIMD2(cellWidth, cellHeight)
        )

        // Clear color
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: 1.0
        )

        // Encode render commands
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            return
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 2)
        encoder.setFragmentTexture(glyphAtlas.texture, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        // Draw all instances in one call
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: 6,
            instanceCount: instanceCount
        )

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateInstances(
        buffer: MTLBuffer,
        cellSize: SIMD2<Float>
    ) -> Int {
        guard !asciiData.isEmpty else { return 0 }

        let instances = buffer.contents().bindMemory(to: GlyphInstance.self, capacity: maxInstances)
        var count = 0

        let rows = asciiData.count
        let cols = asciiData.first?.count ?? 0

        for row in 0..<rows {
            for col in 0..<cols {
                guard col < asciiData[row].count else { continue }

                let char = asciiData[row][col]

                // Skip spaces for performance
                if char == " " { continue }

                let brightness: Float
                if row < brightnessData.count && col < brightnessData[row].count {
                    brightness = brightnessData[row][col]
                } else {
                    brightness = 1.0
                }

                // Screen position (top-left of cell, in pixels)
                let x = Float(col) * cellSize.x
                let y = Float(row) * cellSize.y  // Top-down

                // Get UV from atlas
                let uv = glyphAtlas.uvForCharacter(char)

                instances[count] = GlyphInstance(
                    position: SIMD2(x, y),
                    uvOffset: SIMD2(uv.u, uv.v),
                    uvSize: SIMD2(uv.width, uv.height),
                    brightness: brightness
                )

                count += 1
                if count >= maxInstances { break }
            }
            if count >= maxInstances { break }
        }

        return count
    }

    // MARK: - Shader Source

    private static let glyphShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct GlyphInstance {
        float2 position;
        float2 uvOffset;
        float2 uvSize;
        float brightness;
        float _pad;
    };

    struct Uniforms {
        float2 viewportSize;
        float2 cellSize;
        float4 foregroundColor;
        float4 backgroundColor;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
        float brightness;
    };

    vertex VertexOut glyphVertex(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant float2* vertices [[buffer(0)]],
        constant GlyphInstance* instances [[buffer(1)]],
        constant Uniforms& uniforms [[buffer(2)]]
    ) {
        GlyphInstance inst = instances[instanceID];
        float2 localPos = vertices[vertexID];

        // Scale to cell size and translate to instance position
        float2 pixelPos = inst.position + localPos * uniforms.cellSize;

        // Convert to NDC (-1 to 1)
        float2 ndc = (pixelPos / uniforms.viewportSize) * 2.0 - 1.0;
        ndc.y = -ndc.y;  // Flip Y for top-down

        VertexOut out;
        out.position = float4(ndc, 0.0, 1.0);

        // Calculate texture coordinate within the glyph cell
        out.texCoord = inst.uvOffset + localPos * inst.uvSize;
        out.brightness = inst.brightness;

        return out;
    }

    fragment float4 glyphFragment(
        VertexOut in [[stage_in]],
        texture2d<float, access::sample> glyphAtlas [[texture(0)]],
        constant Uniforms& uniforms [[buffer(0)]]
    ) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);

        float alpha = glyphAtlas.sample(s, in.texCoord).r;

        // Apply brightness to foreground color
        float4 color = uniforms.foregroundColor;
        color.rgb *= in.brightness;
        color.a = alpha;

        return color;
    }
    """
}

// MARK: - Errors

public enum RendererError: Error {
    case commandQueueFailed
    case shaderCompilationFailed
}

// swiftlint:enable function_body_length

#endif // os(macOS)
