// CosmicScene.swift
// MetalASCII - 3D orbital tori and spheres projected to ASCII
//
// Inspired by SamuelYAN's generative 3D orbital artwork.
// Features rotating rings and spheres in layered 3D space,
// projected with depth-based brightness.
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import simd

// swiftlint:disable type_body_length function_body_length

// MARK: - Cosmic Scene

/// GPU-accelerated 3D orbital shapes projected to ASCII art.
/// Creates ethereal rings and spheres rotating in deep space.
public final class CosmicScene: ASCIIScene, @unchecked Sendable {

    public let name = "Cosmic"
    public let description = "3D orbital rings and spheres"

    // MARK: - Configuration

    /// Number of orbital rings
    public var ringCount: Int = 8 {
        didSet { needsRebuild = true }
    }

    /// Number of orbiting spheres
    public var sphereCount: Int = 12 {
        didSet { needsRebuild = true }
    }

    /// Rotation speed
    public var rotationSpeed: Float = 0.3

    /// Orbit radius
    public var orbitRadius: Float = 0.6

    /// Depth intensity (how much Z affects brightness)
    public var depthIntensity: Float = 0.8

    /// Dithering mode
    public var ditherMode: UInt32 = 2

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

    struct CosmicUniforms {
        var time: Float
        var rotationSpeed: Float
        var orbitRadius: Float
        var depthIntensity: Float
        var ringCount: UInt32
        var sphereCount: UInt32
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
            throw CosmicError.metalInitFailed("Failed to create command queue")
        }
        self.commandQueue = queue

        try setupPipelines()
        resize(to: CGSize(width: 1200, height: 800))
    }

    private func setupPipelines() throws {
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

        guard let renderFunc = library.makeFunction(name: "renderCosmic"),
              let convertFunc = library.makeFunction(name: "convertToASCII") else {
            throw CosmicError.pipelineCreationFailed
        }

        renderPipeline = try device.makeComputePipelineState(function: renderFunc)
        convertPipeline = try device.makeComputePipelineState(function: convertFunc)
    }

    private func setupBuffers() {
        let gridSize = cols * rows

        densityBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * gridSize,
            options: .storageModeShared
        )

        cellBuffer = device.makeBuffer(
            length: MemoryLayout<ASCIICell>.stride * gridSize,
            options: .storageModeShared
        )

        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<CosmicUniforms>.stride,
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

        let aspectRatio = Float(cols) / Float(rows) * 0.5
        var uniforms = CosmicUniforms(
            time: time,
            rotationSpeed: rotationSpeed,
            orbitRadius: orbitRadius,
            depthIntensity: depthIntensity,
            ringCount: UInt32(ringCount),
            sphereCount: UInt32(sphereCount),
            ditherMode: ditherMode,
            gridSize: SIMD2(UInt32(cols), UInt32(rows)),
            aspectRatio: aspectRatio
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<CosmicUniforms>.stride)

        let gridSize = cols * rows

        if let encoder = commandBuffer.makeComputeCommandEncoder() {

            // Render cosmic shapes
            if let pipeline = renderPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(densityBuffer, offset: 0, index: 0)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 1)

                let threads = MTLSize(width: gridSize, height: 1, depth: 1)
                let threadgroups = MTLSize(width: min(256, gridSize), height: 1, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroups)
            }

            // Convert to ASCII
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

    struct CosmicUniforms {
        float time;
        float rotationSpeed;
        float orbitRadius;
        float depthIntensity;
        uint ringCount;
        uint sphereCount;
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

    // 3D rotation matrices
    float3x3 rotateX(float angle) {
        float c = cos(angle);
        float s = sin(angle);
        return float3x3(
            float3(1, 0, 0),
            float3(0, c, -s),
            float3(0, s, c)
        );
    }

    float3x3 rotateY(float angle) {
        float c = cos(angle);
        float s = sin(angle);
        return float3x3(
            float3(c, 0, s),
            float3(0, 1, 0),
            float3(-s, 0, c)
        );
    }

    float3x3 rotateZ(float angle) {
        float c = cos(angle);
        float s = sin(angle);
        return float3x3(
            float3(c, -s, 0),
            float3(s, c, 0),
            float3(0, 0, 1)
        );
    }

    // Hash for pseudo-random
    float hash(float n) {
        return fract(sin(n) * 43758.5453);
    }

    // Distance to a ring (torus cross-section) - renders as ellipse outline
    float ringBrightness(float2 p, float3 ringCenter, float radius, float thickness,
                         float3x3 rot, float aspectRatio) {
        float totalBrightness = 0.0;

        // Sample many points around the ring to draw it as a line
        for (int i = 0; i < 64; i++) {
            float angle = float(i) / 64.0 * 6.28318;

            // Point on the ring circle in 3D (ring lies in XY plane initially)
            float3 ringPoint = float3(
                cos(angle) * radius,
                sin(angle) * radius,
                0.0
            );

            // Apply rotation and translate to ring center
            float3 worldPoint = rot * ringPoint + rot * ringCenter;

            // Project to 2D
            float2 projected = float2(worldPoint.x * aspectRatio, worldPoint.y);

            // Distance from current pixel to this ring point
            float dist = length(p - projected);

            // Depth-based brightness (front = brighter)
            float depth = (worldPoint.z + 1.5) / 3.0;
            depth = clamp(depth, 0.2, 1.0);

            // Draw as a soft line
            float lineBrightness = smoothstep(thickness * 1.5, thickness * 0.3, dist);
            lineBrightness *= depth;

            totalBrightness = max(totalBrightness, lineBrightness);
        }

        return totalBrightness;
    }

    // Sphere - renders as filled circle with depth shading
    float sphereBrightness(float2 p, float3 sphereCenter, float radius,
                           float3x3 rot, float aspectRatio) {
        float3 worldPos = rot * sphereCenter;
        float2 projected = float2(worldPos.x * aspectRatio, worldPos.y);

        float dist = length(p - projected);
        float depth = (worldPos.z + 1.5) / 3.0;
        depth = clamp(depth, 0.3, 1.0);

        // Sphere with soft edge
        float brightness = smoothstep(radius, radius * 0.3, dist);
        brightness *= depth;

        return brightness;
    }

    kernel void renderCosmic(
        device float* density [[buffer(0)]],
        constant CosmicUniforms& uniforms [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint gridTotal = uniforms.gridSize.x * uniforms.gridSize.y;
        if (id >= gridTotal) return;

        uint col = id % uniforms.gridSize.x;
        uint row = id / uniforms.gridSize.x;

        // Normalized coordinates centered at origin (-1 to 1)
        float2 uv = float2(
            (float(col) / float(uniforms.gridSize.x - 1) - 0.5) * 2.0,
            (float(row) / float(uniforms.gridSize.y - 1) - 0.5) * 2.0
        );
        uv.x *= uniforms.aspectRatio;

        float t = uniforms.time * uniforms.rotationSpeed;
        float totalBrightness = 0.0;

        // ========== LARGE RINGS (TORI) ==========
        // Each ring has OPPOSITE directions and CONTRASTING orientations
        for (uint i = 0; i < uniforms.ringCount; i++) {
            float fi = float(i);
            float seed = fi * 7.31;

            // Direction multipliers: -1 or +1 for each axis (creates opposite rotations)
            float dirX = (hash(seed + 10.0) > 0.5) ? 1.0 : -1.0;
            float dirY = (hash(seed + 11.0) > 0.5) ? 1.0 : -1.0;
            float dirZ = (hash(seed + 12.0) > 0.5) ? 1.0 : -1.0;

            // Speed variation per ring
            float speedX = 0.3 + hash(seed + 20.0) * 0.4;
            float speedY = 0.2 + hash(seed + 21.0) * 0.5;
            float speedZ = 0.15 + hash(seed + 22.0) * 0.3;

            // Each ring has its own tumbling rotation with VARIED directions
            float3x3 ringRot = rotateX(t * speedX * dirX + hash(seed) * 6.28) *
                               rotateY(t * speedY * dirY + hash(seed + 1.0) * 6.28) *
                               rotateZ(t * speedZ * dirZ + hash(seed + 2.0) * 6.28);

            // Ring position - some orbit, some stay more centered
            float orbitSpeed = (hash(seed + 30.0) > 0.5) ? 0.15 : -0.1;  // Opposite orbit directions
            float orbitAngle = fi / float(uniforms.ringCount) * 6.28318 + t * orbitSpeed;
            float orbitDist = 0.1 + hash(seed + 3.0) * 0.25;
            float3 ringCenter = float3(
                cos(orbitAngle) * orbitDist,
                sin(orbitAngle) * orbitDist * 0.7,
                sin(t * 0.2 * dirZ + fi) * 0.25
            );

            // Ring size - varied sizes for visual contrast
            float ringRadius = 0.25 + hash(seed + 4.0) * 0.5;  // 0.25 to 0.75
            float ringThickness = 0.012 + hash(seed + 5.0) * 0.008;

            float ring = ringBrightness(uv, ringCenter, ringRadius, ringThickness,
                                        ringRot, uniforms.aspectRatio);
            totalBrightness = max(totalBrightness, ring * 0.95);

            // ========== PARTICLES TRAILING OFF THIS RING ==========
            // Each ring emits particles along its path
            for (int p = 0; p < 8; p++) {
                float pf = float(p);
                float particleSeed = seed + pf * 3.7;

                // Particle position on the ring with offset
                float particleAngle = pf / 8.0 * 6.28318 + t * speedX * dirX * 0.5;
                float3 particleOnRing = float3(
                    cos(particleAngle) * ringRadius,
                    sin(particleAngle) * ringRadius,
                    0.0
                );

                // Offset outward from ring (trailing effect)
                float trailOffset = 0.02 + hash(particleSeed) * 0.04;
                float trailAngle = particleAngle + hash(particleSeed + 1.0) * 0.5;
                particleOnRing.x += cos(trailAngle) * trailOffset;
                particleOnRing.y += sin(trailAngle) * trailOffset;
                particleOnRing.z += (hash(particleSeed + 2.0) - 0.5) * 0.05;

                // Apply ring rotation and center
                float3 worldParticle = ringRot * particleOnRing + ringRot * ringCenter;
                float2 projParticle = float2(worldParticle.x * uniforms.aspectRatio, worldParticle.y);

                float dist = length(uv - projParticle);
                float depth = (worldParticle.z + 1.5) / 3.0;

                // Small faint particle
                float particleBrightness = smoothstep(0.015, 0.003, dist) * depth * 0.4;
                totalBrightness = max(totalBrightness, particleBrightness);
            }
        }

        // ========== ORBITING SPHERES ==========
        // Spheres with contrasting orbit directions
        for (uint i = 0; i < uniforms.sphereCount; i++) {
            float fi = float(i);
            float seed = fi * 13.37;

            // Alternating orbit directions
            float orbitDir = (i % 2 == 0) ? 1.0 : -1.0;
            float orbitSpeed = 0.2 + hash(seed) * 0.3;

            // Orbital position
            float orbitAngle = fi / float(uniforms.sphereCount) * 6.28318;
            float orbitPhase = orbitAngle + t * orbitSpeed * orbitDir;

            // Create orbital plane with varied tilts
            float tiltX = hash(seed + 1.0) * 3.14159 - 1.57;  // -90 to +90 degrees
            float tiltZ = hash(seed + 2.0) * 6.28318;
            float3x3 orbitRot = rotateX(tiltX) * rotateZ(tiltZ);

            // Position on orbit
            float orbitRadius = uniforms.orbitRadius * (0.4 + hash(seed + 3.0) * 0.6);
            float3 spherePos = float3(
                cos(orbitPhase) * orbitRadius,
                sin(orbitPhase) * orbitRadius,
                0.0
            );

            // Random Z wobble
            spherePos.z += sin(t * 0.5 * orbitDir + fi * 0.7) * 0.15;

            // Apply rotation
            float3 worldSphere = orbitRot * spherePos;
            float2 projSphere = float2(worldSphere.x * uniforms.aspectRatio, worldSphere.y);

            float dist = length(uv - projSphere);
            float depth = (worldSphere.z + 1.5) / 3.0;
            depth = clamp(depth, 0.3, 1.0);

            // Sphere size
            float sphereRadius = 0.03 + hash(seed + 6.0) * 0.05;
            float sphere = smoothstep(sphereRadius, sphereRadius * 0.4, dist) * depth;
            totalBrightness = max(totalBrightness, sphere * 0.85);
        }

        // ========== AMBIENT DUST PARTICLES ==========
        for (uint i = 0; i < 40; i++) {
            float fi = float(i);
            float seed = fi * 17.71;

            float3 particlePos = float3(
                (hash(seed) - 0.5) * 2.5,
                (hash(seed + 1.0) - 0.5) * 2.5,
                (hash(seed + 2.0) - 0.5) * 2.0
            );

            // Very gentle drift with varied directions
            float driftDir = (hash(seed + 3.0) > 0.5) ? 1.0 : -1.0;
            particlePos.x += sin(t * 0.08 * driftDir + fi * 0.3) * 0.15;
            particlePos.y += cos(t * 0.1 * driftDir + fi * 0.2) * 0.15;
            particlePos.z += sin(t * 0.05 + fi) * 0.1;

            // Simple rotation for dust
            float3x3 dustRot = rotateY(t * 0.1) * rotateX(t * 0.05);
            float3 rotated = dustRot * particlePos;
            float2 projected = float2(rotated.x * uniforms.aspectRatio, rotated.y);

            float dist = length(uv - projected);
            float depth = (rotated.z + 1.5) / 3.0;
            float brightness = smoothstep(0.015, 0.003, dist) * depth * 0.25;
            totalBrightness = max(totalBrightness, brightness);
        }

        density[id] = clamp(totalBrightness, 0.0f, 1.0f);
    }

    // Bayer dithering
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

    kernel void convertToASCII(
        device float* density [[buffer(0)]],
        device ASCIICell* cells [[buffer(1)]],
        constant CosmicUniforms& uniforms [[buffer(2)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint gridSize = uniforms.gridSize.x * uniforms.gridSize.y;
        if (id >= gridSize) return;

        float brightness = density[id];

        if (uniforms.ditherMode > 0) {
            uint col = id % uniforms.gridSize.x;
            uint row = id / uniforms.gridSize.x;
            uint x = col % 8;
            uint y = row % 8;
            float threshold = bayerMatrix8x8[y * 8 + x];
            brightness += (threshold - 0.5) * 0.1;
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

enum CosmicError: Error {
    case metalInitFailed(String)
    case pipelineCreationFailed
}

// swiftlint:enable type_body_length function_body_length

#endif // os(macOS)
