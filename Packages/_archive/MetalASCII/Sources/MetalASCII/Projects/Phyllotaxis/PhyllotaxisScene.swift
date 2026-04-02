// PhyllotaxisScene.swift
// MetalASCII - GPU-accelerated Fibonacci/Golden Angle spiral
//
// Inspired by sunflower seed patterns and the golden ratio.
// Points spiral outward at 137.5° (the golden angle) creating
// mesmerizing organic density patterns.
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import simd

// swiftlint:disable function_body_length

// MARK: - Phyllotaxis Scene

/// GPU-accelerated Fibonacci spiral with golden angle distribution.
/// Creates organic, sunflower-like patterns with pulsing animation.
public final class PhyllotaxisScene: ASCIIScene, @unchecked Sendable {

    public let name = "Phyllotaxis"
    public let description = "Golden angle spiral (sunflower pattern)"

    // MARK: - Configuration

    /// Number of points in the spiral
    public var pointCount: Int = 2000 {
        didSet { needsRebuild = true }
    }

    /// Base radius multiplier
    public var radiusScale: Float = 0.4

    /// Point size (affects density)
    public var pointSize: Float = 1.5

    /// Pulse intensity (0-1)
    public var pulseIntensity: Float = 0.3

    /// Rotation speed
    public var rotationSpeed: Float = 0.2

    /// Breathing speed
    public var breathingSpeed: Float = 0.5

    /// Dithering mode
    public var ditherMode: UInt32 = 2

    // MARK: - Constants

    /// The golden angle in radians: 360° / φ² ≈ 137.5°
    private let goldenAngle: Float = .pi * (3.0 - sqrt(5.0))

    private let maxPoints = 10000

    // MARK: - Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var renderPipeline: MTLComputePipelineState?
    private var convertPipeline: MTLComputePipelineState?

    // Buffers
    private var densityBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var cellBuffer: MTLBuffer?

    // MARK: - State

    private var time: Float = 0
    private var viewportSize: CGSize = .zero
    private var cols: Int = 100
    private var rows: Int = 50
    private var needsRebuild: Bool = true

    // MARK: - Output

    public private(set) var asciiOutput: [[Character]] = []
    public private(set) var brightnessOutput: [[Float]] = []

    // MARK: - GPU Structures

    struct PhyllotaxisUniforms {
        var time: Float
        var goldenAngle: Float
        var pointCount: UInt32
        var radiusScale: Float
        var pointSize: Float
        var pulseIntensity: Float
        var rotationSpeed: Float
        var breathingSpeed: Float
        var ditherMode: UInt32
        var padding0: UInt32 = 0
        var gridSize: SIMD2<UInt32>
        var aspectRatio: Float
        var padding1: Float = 0
    }

    struct ASCIICell {
        var character: UInt8
        var brightness: UInt8
    }

    private let characterRamp = " .,:;i1tfLCG08@"

    // MARK: - Initialization

    public required init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw PhyllotaxisError.metalInitFailed("Failed to create command queue")
        }
        self.commandQueue = queue

        try setupPipelines()
        resize(to: CGSize(width: 1200, height: 800))
    }

    private func setupPipelines() throws {
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

        guard let renderFunc = library.makeFunction(name: "renderPhyllotaxis"),
              let convertFunc = library.makeFunction(name: "convertToASCII") else {
            throw PhyllotaxisError.pipelineCreationFailed
        }

        renderPipeline = try device.makeComputePipelineState(function: renderFunc)
        convertPipeline = try device.makeComputePipelineState(function: convertFunc)
    }

    private func setupBuffers() {
        let gridSize = cols * rows

        // Density buffer
        densityBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * gridSize,
            options: .storageModeShared
        )

        // Cell buffer
        cellBuffer = device.makeBuffer(
            length: MemoryLayout<ASCIICell>.stride * gridSize,
            options: .storageModeShared
        )

        // Uniform buffer
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<PhyllotaxisUniforms>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - ASCIIScene Protocol

    public func resize(to size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }

        viewportSize = size
        let cellWidth: CGFloat = 7
        let cellHeight: CGFloat = 14
        cols = max(1, Int(size.width / cellWidth))
        rows = max(1, Int(size.height / cellHeight))

        asciiOutput = Array(repeating: Array(repeating: " ", count: cols), count: rows)
        brightnessOutput = Array(repeating: Array(repeating: 0, count: cols), count: rows)

        needsRebuild = true
    }

    public func update(deltaTime: Float) {
        if needsRebuild {
            setupBuffers()
            needsRebuild = false
        }

        time += deltaTime

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let densityBuffer = densityBuffer,
              let cellBuffer = cellBuffer,
              let uniformBuffer = uniformBuffer else {
            return
        }

        // Update uniforms
        let aspectRatio = Float(cols) / Float(rows) * 0.5  // Account for char aspect
        var uniforms = PhyllotaxisUniforms(
            time: time,
            goldenAngle: goldenAngle,
            pointCount: UInt32(min(pointCount, maxPoints)),
            radiusScale: radiusScale,
            pointSize: pointSize,
            pulseIntensity: pulseIntensity,
            rotationSpeed: rotationSpeed,
            breathingSpeed: breathingSpeed,
            ditherMode: ditherMode,
            gridSize: SIMD2(UInt32(cols), UInt32(rows)),
            aspectRatio: aspectRatio
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<PhyllotaxisUniforms>.stride)

        let gridSize = cols * rows

        // Encode compute passes
        if let encoder = commandBuffer.makeComputeCommandEncoder() {

            // 1. Render phyllotaxis to density buffer
            if let pipeline = renderPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(densityBuffer, offset: 0, index: 0)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 1)

                // One thread per grid cell
                let threads = MTLSize(width: gridSize, height: 1, depth: 1)
                let threadgroups = MTLSize(width: min(256, gridSize), height: 1, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroups)
            }

            // 2. Convert to ASCII
            if let pipeline = convertPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(densityBuffer, offset: 0, index: 0)
                encoder.setBuffer(cellBuffer, offset: 0, index: 1)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 2)

                let threads = MTLSize(width: gridSize, height: 1, depth: 1)
                let threadgroups = MTLSize(width: min(256, gridSize), height: 1, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroups)
            }

            encoder.endEncoding()
        }

        // Read back asynchronously
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.readBackASCII()
            }
        }

        commandBuffer.commit()
    }

    public func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }

    private func readBackASCII() {
        guard let cellBuffer = cellBuffer else { return }

        let cells = cellBuffer.contents().bindMemory(to: ASCIICell.self, capacity: cols * rows)
        let rampCount = characterRamp.count

        for row in 0..<rows {
            for col in 0..<cols {
                let idx = row * cols + col
                let cell = cells[idx]

                let charIdx = min(Int(cell.character), rampCount - 1)
                let charIndex = characterRamp.index(characterRamp.startIndex, offsetBy: charIdx)
                asciiOutput[row][col] = characterRamp[charIndex]
                brightnessOutput[row][col] = Float(cell.brightness) / 255.0
            }
        }
    }

    // MARK: - Shader Source

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct PhyllotaxisUniforms {
        float time;
        float goldenAngle;
        uint pointCount;
        float radiusScale;
        float pointSize;
        float pulseIntensity;
        float rotationSpeed;
        float breathingSpeed;
        uint ditherMode;
        uint _pad;
        uint2 gridSize;
        float aspectRatio;
        float _pad2;
    };

    struct ASCIICell {
        uchar character;
        uchar brightness;
    };

    // Render phyllotaxis pattern to density buffer
    kernel void renderPhyllotaxis(
        device float* density [[buffer(0)]],
        constant PhyllotaxisUniforms& uniforms [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint gridTotal = uniforms.gridSize.x * uniforms.gridSize.y;
        if (id >= gridTotal) return;

        // Get grid coordinates
        uint col = id % uniforms.gridSize.x;
        uint row = id / uniforms.gridSize.x;

        // Normalized coordinates (0-1) with aspect correction
        float2 uv = float2(
            float(col) / float(uniforms.gridSize.x - 1),
            float(row) / float(uniforms.gridSize.y - 1)
        );

        // Center and apply aspect ratio
        float2 centered = (uv - 0.5) * 2.0;
        centered.x *= uniforms.aspectRatio;

        // Breathing effect
        float breathing = 1.0 + sin(uniforms.time * uniforms.breathingSpeed) * uniforms.pulseIntensity * 0.2;

        // Accumulate density from all points
        float totalDensity = 0.0;

        for (uint i = 0; i < uniforms.pointCount; i++) {
            // Golden angle position
            float angle = float(i) * uniforms.goldenAngle + uniforms.time * uniforms.rotationSpeed;
            float radius = sqrt(float(i)) * uniforms.radiusScale * 0.02 * breathing;

            // Point position
            float2 pointPos = float2(cos(angle), sin(angle)) * radius;

            // Distance to this point
            float dist = length(centered - pointPos);

            // Point brightness based on index (outer = dimmer)
            float pointBrightness = 1.0 - float(i) / float(uniforms.pointCount) * 0.5;

            // Pulse each point slightly
            float pulse = sin(uniforms.time * 2.0 + float(i) * 0.1) * uniforms.pulseIntensity;
            float size = uniforms.pointSize * 0.015 * (1.0 + pulse * 0.3);

            // Soft falloff
            float contribution = smoothstep(size, size * 0.3, dist) * pointBrightness;
            totalDensity += contribution;
        }

        // Clamp density
        density[id] = clamp(totalDensity, 0.0f, 1.0f);
    }

    // Bayer dithering matrix
    constant float bayerMatrix8x8[64] = {
         0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
        48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
        12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
        60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
         3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
        51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
        15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
        63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
    };

    // Convert density to ASCII
    kernel void convertToASCII(
        device float* density [[buffer(0)]],
        device ASCIICell* cells [[buffer(1)]],
        constant PhyllotaxisUniforms& uniforms [[buffer(2)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint gridSize = uniforms.gridSize.x * uniforms.gridSize.y;
        if (id >= gridSize) return;

        float brightness = density[id];

        // Apply dithering
        if (uniforms.ditherMode > 0) {
            uint col = id % uniforms.gridSize.x;
            uint row = id / uniforms.gridSize.x;
            uint x = col % 8;
            uint y = row % 8;
            float threshold = bayerMatrix8x8[y * 8 + x];
            brightness += (threshold - 0.5) * 0.12;
        }

        brightness = clamp(brightness, 0.0f, 1.0f);

        uint charIndex = uint(brightness * 15.0);
        charIndex = min(charIndex, 15u);

        cells[id].character = uchar(charIndex);
        cells[id].brightness = uchar(brightness * 255.0);
    }
    """
}

// MARK: - Errors

enum PhyllotaxisError: Error {
    case metalInitFailed(String)
    case pipelineCreationFailed
}

// swiftlint:enable function_body_length

#endif // os(macOS)
