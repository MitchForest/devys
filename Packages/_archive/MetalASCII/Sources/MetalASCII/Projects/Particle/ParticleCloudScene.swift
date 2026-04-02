// ParticleCloudScene.swift
// MetalASCII - GPU-accelerated particle cloud with compute shaders
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import simd

// swiftlint:disable type_body_length function_body_length

// MARK: - Scene Error

enum ParticleSceneError: Error {
    case metalInitFailed(String)
    case pipelineCreationFailed
}

// MARK: - Particle Cloud Scene

/// GPU-accelerated ethereal particle cloud.
/// All physics and density calculations run on Metal compute shaders.
public final class ParticleCloudScene: ASCIIScene, @unchecked Sendable {

    public let name = "Particle"
    public let description = "GPU-accelerated particle cloud with flow field"

    // MARK: - Configuration

    public var particleCount: Int = 30000 {
        didSet {
            particleCount = min(particleCount, maxParticles)
            if particleCount != oldValue { needsRebuild = true }
        }
    }

    public var turbulence: Float = 1.2
    public var speed: Float = 1.0
    public var spawnRadius: Float = 0.15
    public var trailPersistence: Float = 0.85
    public var ditherMode: UInt32 = 2

    // MARK: - Constants

    private let maxParticles = 100000

    // MARK: - Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var updatePipeline: MTLComputePipelineState?
    private var densityPipeline: MTLComputePipelineState?
    private var clearPipeline: MTLComputePipelineState?
    private var convertPipeline: MTLComputePipelineState?

    // Buffers
    private var particleBuffer: MTLBuffer?
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

    struct Particle {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var life: Float
        var brightness: Float
        var padding: SIMD2<Float> = .zero
    }

    struct ParticleUniforms {
        var time: Float
        var deltaTime: Float
        var turbulence: Float
        var speed: Float
        var spawnRadius: Float
        var trailPersistence: Float
        var particleCount: UInt32
        var ditherMode: UInt32
        var gridSize: SIMD2<UInt32>
        var viewportSize: SIMD2<Float>
    }

    struct ASCIICell {
        var character: UInt8
        var brightness: UInt8
    }

    // Character ramp
    private let characterRamp = " .,:;i1tfLCG08@"

    // MARK: - Initialization

    public required init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw ParticleSceneError.metalInitFailed("Failed to create command queue")
        }
        self.commandQueue = queue

        try setupPipelines()
        resize(to: CGSize(width: 1200, height: 800))
    }

    private func setupPipelines() throws {
        let library = try device.makeLibrary(source: Self.shaderSource, options: nil)

        guard let updateFunc = library.makeFunction(name: "updateParticles"),
              let densityFunc = library.makeFunction(name: "accumulateDensity"),
              let clearFunc = library.makeFunction(name: "clearDensity"),
              let convertFunc = library.makeFunction(name: "convertToASCII") else {
            throw ParticleSceneError.pipelineCreationFailed
        }

        updatePipeline = try device.makeComputePipelineState(function: updateFunc)
        densityPipeline = try device.makeComputePipelineState(function: densityFunc)
        clearPipeline = try device.makeComputePipelineState(function: clearFunc)
        convertPipeline = try device.makeComputePipelineState(function: convertFunc)
    }

    private func setupBuffers() {
        // Particle buffer
        particleBuffer = device.makeBuffer(
            length: MemoryLayout<Particle>.stride * maxParticles,
            options: .storageModeShared
        )

        // Initialize particles
        if let buffer = particleBuffer {
            let particles = buffer.contents().bindMemory(to: Particle.self, capacity: maxParticles)
            for i in 0..<particleCount {
                let angle = Float(i) / Float(particleCount) * .pi * 2
                let r = Float.random(in: 0...spawnRadius)
                particles[i] = Particle(
                    position: SIMD2(0.5 + cos(angle) * r, 0.5 + sin(angle) * r),
                    velocity: .zero,
                    life: Float.random(in: 0.5...1.0),
                    brightness: Float.random(in: 0.5...1.0)
                )
            }
        }

        // Density buffer (for trail accumulation)
        let gridSize = cols * rows
        densityBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * gridSize,
            options: .storageModeShared
        )

        // Clear density buffer
        if let buffer = densityBuffer {
            memset(buffer.contents(), 0, MemoryLayout<Float>.stride * gridSize)
        }

        // Cell buffer for ASCII output
        cellBuffer = device.makeBuffer(
            length: MemoryLayout<ASCIICell>.stride * gridSize,
            options: .storageModeShared
        )

        // Uniform buffer
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<ParticleUniforms>.stride,
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

        time += deltaTime * speed

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let particleBuffer = particleBuffer,
              let densityBuffer = densityBuffer,
              let cellBuffer = cellBuffer,
              let uniformBuffer = uniformBuffer else {
            return
        }

        // Update uniforms
        var uniforms = ParticleUniforms(
            time: time,
            deltaTime: deltaTime,
            turbulence: turbulence,
            speed: speed,
            spawnRadius: spawnRadius,
            trailPersistence: trailPersistence,
            particleCount: UInt32(particleCount),
            ditherMode: ditherMode,
            gridSize: SIMD2(UInt32(cols), UInt32(rows)),
            viewportSize: SIMD2(Float(viewportSize.width), Float(viewportSize.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<ParticleUniforms>.stride)

        // Encode compute passes
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            let gridSize = cols * rows

            // 1. Clear/fade density
            if let pipeline = clearPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(densityBuffer, offset: 0, index: 0)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 1)

                let threads = MTLSize(width: gridSize, height: 1, depth: 1)
                let threadgroups = MTLSize(width: min(256, gridSize), height: 1, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroups)
            }

            // 2. Update particles
            if let pipeline = updatePipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(particleBuffer, offset: 0, index: 0)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 1)

                let threads = MTLSize(width: particleCount, height: 1, depth: 1)
                let threadgroups = MTLSize(width: min(256, particleCount), height: 1, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroups)
            }

            // 3. Accumulate density
            if let pipeline = densityPipeline {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(particleBuffer, offset: 0, index: 0)
                encoder.setBuffer(densityBuffer, offset: 0, index: 1)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 2)

                let threads = MTLSize(width: particleCount, height: 1, depth: 1)
                let threadgroups = MTLSize(width: min(256, particleCount), height: 1, depth: 1)
                encoder.dispatchThreads(threads, threadsPerThreadgroup: threadgroups)
            }

            // 4. Convert to ASCII
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

        // Read back results asynchronously
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.readBackASCII()
            }
        }

        commandBuffer.commit()
    }

    public func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        // All work done in compute shaders during update()
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

                // Map character index to ramp
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

    struct Particle {
        float2 position;
        float2 velocity;
        float life;
        float brightness;
        float2 _pad;
    };

    struct ParticleUniforms {
        float time;
        float deltaTime;
        float turbulence;
        float speed;
        float spawnRadius;
        float trailPersistence;
        uint particleCount;
        uint ditherMode;
        uint2 gridSize;
        float2 viewportSize;
    };

    struct ASCIICell {
        uchar character;
        uchar brightness;
    };

    // Noise functions
    float hash(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    float noise2D(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);

        float a = hash(i);
        float b = hash(i + float2(1.0, 0.0));
        float c = hash(i + float2(0.0, 1.0));
        float d = hash(i + float2(1.0, 1.0));

        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    float fbm(float2 p, float time) {
        float value = 0.0;
        float amplitude = 0.5;
        float2 shift = float2(time * 0.1, 0.0);

        for (int i = 0; i < 4; i++) {
            value += amplitude * noise2D(p + shift);
            p *= 2.0;
            amplitude *= 0.5;
        }
        return value;
    }

    float2 curlNoise(float2 p, float time) {
        float eps = 0.01;
        float n1 = fbm(p + float2(0, eps), time);
        float n2 = fbm(p - float2(0, eps), time);
        float n3 = fbm(p + float2(eps, 0), time);
        float n4 = fbm(p - float2(eps, 0), time);

        float dx = (n1 - n2) / (2.0 * eps);
        float dy = (n3 - n4) / (2.0 * eps);

        return float2(dy, -dx);
    }

    // Random number generator
    float rand(uint seed) {
        seed = seed * 747796405u + 2891336453u;
        uint result = ((seed >> ((seed >> 28u) + 4u)) ^ seed) * 277803737u;
        return float((result >> 22u) ^ result) / 4294967295.0;
    }

    // Update particles kernel
    kernel void updateParticles(
        device Particle* particles [[buffer(0)]],
        constant ParticleUniforms& uniforms [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        if (id >= uniforms.particleCount) return;

        Particle p = particles[id];
        float dt = uniforms.deltaTime * uniforms.speed;

        // Age particle
        p.life -= dt * 0.15;

        // Respawn if dead
        if (p.life <= 0.0) {
            float angle = rand(id + uint(uniforms.time * 1000)) * 6.28318;
            float r = rand(id + uint(uniforms.time * 1000) + 1) * uniforms.spawnRadius;
            p.position = float2(0.5 + cos(angle) * r, 0.5 + sin(angle) * r);
            p.velocity = float2(0);
            p.life = 0.7 + rand(id + uint(uniforms.time * 1000) + 2) * 0.3;
            p.brightness = 0.4 + rand(id + uint(uniforms.time * 1000) + 3) * 0.6;
        }

        // Get flow field velocity
        float scale = 3.0 * uniforms.turbulence;
        float2 flow = curlNoise(p.position * scale, uniforms.time);

        // Add spiral motion
        float2 toCenter = float2(0.5) - p.position;
        float dist = length(toCenter) + 0.001;
        float2 radial = toCenter / dist;
        float2 tangent = float2(-radial.y, radial.x);

        float spiralStrength = 0.3 * (1.0 - min(dist * 2.0, 1.0));
        float flowStrength = 0.5;

        float2 accel = flow * flowStrength + tangent * spiralStrength + radial * spiralStrength * 0.3;

        // Update velocity with damping
        p.velocity = p.velocity * 0.95 + accel * dt * 2.0;

        // Limit speed
        float speed = length(p.velocity);
        if (speed > 0.03) {
            p.velocity = p.velocity / speed * 0.03;
        }

        // Update position
        p.position += p.velocity;

        // Wrap around
        if (p.position.x < 0) p.position.x += 1;
        if (p.position.x > 1) p.position.x -= 1;
        if (p.position.y < 0) p.position.y += 1;
        if (p.position.y > 1) p.position.y -= 1;

        particles[id] = p;
    }

    // Clear/fade density kernel
    kernel void clearDensity(
        device float* density [[buffer(0)]],
        constant ParticleUniforms& uniforms [[buffer(1)]],
        uint id [[thread_position_in_grid]]
    ) {
        uint gridSize = uniforms.gridSize.x * uniforms.gridSize.y;
        if (id >= gridSize) return;

        density[id] *= uniforms.trailPersistence;
    }

    // Accumulate density kernel
    kernel void accumulateDensity(
        device Particle* particles [[buffer(0)]],
        device atomic_float* density [[buffer(1)]],
        constant ParticleUniforms& uniforms [[buffer(2)]],
        uint id [[thread_position_in_grid]]
    ) {
        if (id >= uniforms.particleCount) return;

        Particle p = particles[id];
        if (p.life <= 0) return;

        uint col = uint(p.position.x * float(uniforms.gridSize.x));
        uint row = uint((1.0 - p.position.y) * float(uniforms.gridSize.y));

        if (col < uniforms.gridSize.x && row < uniforms.gridSize.y) {
            uint idx = row * uniforms.gridSize.x + col;
            float contribution = p.brightness * p.life * 0.15;
            atomic_fetch_add_explicit(&density[idx], contribution, memory_order_relaxed);
        }
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

    // Convert to ASCII kernel
    kernel void convertToASCII(
        device float* density [[buffer(0)]],
        device ASCIICell* cells [[buffer(1)]],
        constant ParticleUniforms& uniforms [[buffer(2)]],
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
            brightness += (threshold - 0.5) * 0.1;
        }

        brightness = clamp(brightness, 0.0f, 1.0f);

        // Map to character (0-15 for our ramp)
        uint charIndex = uint(brightness * 15.0);
        charIndex = min(charIndex, 15u);

        cells[id].character = uchar(charIndex);
        cells[id].brightness = uchar(brightness * 255.0);
    }
    """
}

// swiftlint:enable type_body_length function_body_length

#endif // os(macOS)
