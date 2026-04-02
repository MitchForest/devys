// BambooScene.swift
// MetalASCII - GPU-accelerated bamboo forest swaying in the wind
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import MetalKit
import simd

// swiftlint:disable type_body_length function_body_length

// MARK: - Bamboo Scene

/// A serene bamboo forest with stalks swaying in the wind.
///
/// Features:
/// - Multiple bamboo stalks at varying depths
/// - Wind animation with organic noise
/// - Segments/nodes along stalks
/// - Leaves rustling in the breeze
public final class BambooScene: ASCIIScene, @unchecked Sendable {

    public let name = "Bamboo"
    public let description = "Bamboo forest swaying in the wind"

    // MARK: - Configuration

    /// Number of bamboo stalks
    public var stalkCount: Int = 20

    /// Wind strength (0-1)
    public var windStrength: Float = 0.5

    /// Wind speed
    public var windSpeed: Float = 1.0

    /// Leaf density (0-1)
    public var leafDensity: Float = 0.6

    /// Dithering mode
    public var ditherMode: UInt32 = 2

    // MARK: - GPU Resources

    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private var renderPipeline: MTLComputePipelineState?
    private var convertPipeline: MTLComputePipelineState?

    private var densityBuffer: MTLBuffer?
    private var cellBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?

    // MARK: - State

    private var time: Float = 0
    private var gridWidth: UInt32 = 120
    private var gridHeight: UInt32 = 40
    private var viewportSize: CGSize = .zero

    // MARK: - Output

    public private(set) var asciiOutput: [[Character]] = []
    public private(set) var brightnessOutput: [[Float]] = []

    // MARK: - Shader Uniforms

    private struct BambooUniforms {
        var gridSize: SIMD2<UInt32>
        var time: Float
        var aspectRatio: Float
        var stalkCount: UInt32
        var windStrength: Float
        var windSpeed: Float
        var leafDensity: Float
        var ditherMode: UInt32
        var padding: SIMD3<Float> = .zero
    }

    // MARK: - Initialization

    public required init(device: MTLDevice) throws {
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        try createPipelines()
        resize(to: CGSize(width: 1200, height: 800))
    }

    private func createPipelines() throws {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct BambooUniforms {
            uint2 gridSize;
            float time;
            float aspectRatio;
            uint stalkCount;
            float windStrength;
            float windSpeed;
            float leafDensity;
            uint ditherMode;
            float3 padding;
        };

        // Noise functions
        float hash(float p) {
            return fract(sin(p * 127.1) * 43758.5453);
        }

        float hash2(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        float noise1D(float p) {
            float i = floor(p);
            float f = fract(p);
            f = f * f * (3.0 - 2.0 * f);
            return mix(hash(i), hash(i + 1.0), f);
        }

        float noise2D(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);

            float a = hash2(i);
            float b = hash2(i + float2(1.0, 0.0));
            float c = hash2(i + float2(0.0, 1.0));
            float d = hash2(i + float2(1.0, 1.0));

            return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
        }

        // Wind displacement based on height and time
        float getWind(float x, float y, float time, float strength, float speed) {
            // Wind varies with height - more at top
            float heightFactor = y * y;  // Quadratic - top sways more

            // Organic wind pattern
            float wind1 = sin(time * speed * 0.7 + x * 2.0) * 0.6;
            float wind2 = sin(time * speed * 1.3 + x * 3.0 + 1.5) * 0.3;
            float wind3 = noise1D(time * speed * 0.5 + x) * 0.4 - 0.2;

            // Gusts
            float gust = sin(time * speed * 0.2) * 0.5 + 0.5;
            gust = gust * gust * gust;  // Make gusts occasional

            return (wind1 + wind2 + wind3 + gust * 0.5) * heightFactor * strength;
        }

        // Draw a bamboo stalk
        float bambooStalk(float2 uv, float stalkX, float stalkHeight, float time,
                         float windStrength, float windSpeed, uint stalkIdx) {
            float brightness = 0.0;
            float seed = float(stalkIdx) * 7.31;

            // Stalk thickness varies slightly
            float thickness = 0.008 + hash(seed + 1.0) * 0.004;

            // Sample multiple points along the stalk
            for (float segY = 0.0; segY < stalkHeight; segY += 0.02) {
                // Normalized height (0 at bottom, 1 at top)
                float normY = segY / stalkHeight;

                // Wind displacement at this height
                float windOffset = getWind(stalkX, normY, time + seed, windStrength, windSpeed);

                // Stalk position with wind
                float2 stalkPos = float2(stalkX + windOffset * 0.15, -1.0 + segY);

                // Distance to this segment
                float dist = abs(uv.x - stalkPos.x);

                // Only draw if we're at the right height
                if (uv.y > stalkPos.y - 0.015 && uv.y < stalkPos.y + 0.015) {
                    // Stalk brightness (brighter at center)
                    float stalkBright = smoothstep(thickness, thickness * 0.3, dist);

                    // Slight variation in brightness along stalk
                    stalkBright *= 0.6 + noise1D(segY * 20.0 + seed) * 0.4;

                    brightness = max(brightness, stalkBright);
                }
            }

            // Add nodes/segments (horizontal lines across stalk)
            float nodeSpacing = 0.12 + hash(seed + 2.0) * 0.08;
            for (float nodeY = nodeSpacing; nodeY < stalkHeight; nodeY += nodeSpacing) {
                float normY = nodeY / stalkHeight;
                float windOffset = getWind(stalkX, normY, time + seed, windStrength, windSpeed);
                float2 nodePos = float2(stalkX + windOffset * 0.15, -1.0 + nodeY);

                // Node is a small horizontal line
                float nodeDist = length(float2((uv.x - nodePos.x) * 4.0, uv.y - nodePos.y));
                float nodeWidth = thickness * 2.5;

                if (abs(uv.x - nodePos.x) < nodeWidth && abs(uv.y - nodePos.y) < 0.008) {
                    float nodeBright = smoothstep(0.015, 0.005, nodeDist) * 0.8;
                    brightness = max(brightness, nodeBright);
                }
            }

            return brightness;
        }

        // Draw leaves
        float bambooLeaves(float2 uv, float stalkX, float stalkHeight, float time,
                          float windStrength, float windSpeed, float leafDensity, uint stalkIdx) {
            float brightness = 0.0;
            float seed = float(stalkIdx) * 13.37;

            // Leaves appear in clusters at nodes
            float nodeSpacing = 0.12 + hash(seed + 2.0) * 0.08;

            for (float nodeY = nodeSpacing * 2.0; nodeY < stalkHeight - 0.1; nodeY += nodeSpacing) {
                float normY = nodeY / stalkHeight;
                float windOffset = getWind(stalkX, normY, time + seed, windStrength, windSpeed);
                float2 nodePos = float2(stalkX + windOffset * 0.15, -1.0 + nodeY);

                // Number of leaves at this node
                uint leafCount = uint(hash(seed + nodeY) * 4.0 * leafDensity) + 1;

                for (uint l = 0; l < leafCount; l++) {
                    float leafSeed = seed + nodeY * 10.0 + float(l) * 3.7;

                    // Leaf direction (left or right, angled up)
                    float side = (hash(leafSeed) > 0.5) ? 1.0 : -1.0;
                    float angle = 0.3 + hash(leafSeed + 1.0) * 0.4;  // 0.3 to 0.7 radians

                    // Leaf sway with wind
                    float leafWind = sin(time * windSpeed * 2.0 + leafSeed) * windStrength * 0.1;
                    angle += leafWind;

                    // Leaf as a short diagonal line
                    float leafLen = 0.03 + hash(leafSeed + 2.0) * 0.04;
                    float2 leafDir = float2(cos(angle) * side, sin(angle));

                    // Check if point is on leaf line
                    float2 toPoint = uv - nodePos;
                    float proj = dot(toPoint, leafDir);

                    if (proj > 0.0 && proj < leafLen) {
                        float2 closestPoint = nodePos + leafDir * proj;
                        float leafDist = length(uv - closestPoint);

                        // Leaf tapers toward tip
                        float taper = 1.0 - proj / leafLen;
                        float leafThickness = 0.006 * taper;

                        float leafBright = smoothstep(leafThickness, leafThickness * 0.3, leafDist);
                        leafBright *= 0.5 + taper * 0.3;  // Brighter at base

                        brightness = max(brightness, leafBright * 0.7);
                    }
                }
            }

            return brightness;
        }

        // Dithering
        constant float bayer8x8[64] = {
            0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
            48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
            12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
            60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
            3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
            51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
            15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
            63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
        };

        float getDither(uint x, uint y, uint mode) {
            if (mode == 0) return 0.0;
            uint idx = (y % 8) * 8 + (x % 8);
            return bayer8x8[idx] - 0.5;
        }

        kernel void renderBamboo(
            device float* density [[buffer(0)]],
            constant BambooUniforms& uniforms [[buffer(1)]],
            uint id [[thread_position_in_grid]]
        ) {
            uint gridTotal = uniforms.gridSize.x * uniforms.gridSize.y;
            if (id >= gridTotal) return;

            uint col = id % uniforms.gridSize.x;
            uint row = id / uniforms.gridSize.x;

            // Normalized coordinates (-1 to 1), Y grows upward
            float2 uv = float2(
                (float(col) / float(uniforms.gridSize.x - 1) - 0.5) * 2.0,
                (float(uniforms.gridSize.y - 1 - row) / float(uniforms.gridSize.y - 1) - 0.5) * 2.0
            );
            uv.x *= uniforms.aspectRatio;

            float t = uniforms.time;
            float totalBrightness = 0.0;

            // ========== BACKGROUND GRADIENT ==========
            // Subtle vertical gradient (darker at bottom, lighter at top)
            float bgGradient = (uv.y + 1.0) * 0.5;  // 0 at bottom, 1 at top
            bgGradient = bgGradient * 0.15 + 0.02;  // Very subtle 0.02 to 0.17
            totalBrightness = bgGradient;

            // ========== BAMBOO STALKS ==========
            for (uint i = 0; i < uniforms.stalkCount; i++) {
                float fi = float(i);
                float seed = fi * 7.31;

                // Stalk X position (spread across screen)
                float stalkX = (hash(seed) - 0.5) * 2.0 * uniforms.aspectRatio;

                // Stalk height (varies from 60% to 100% of screen)
                float stalkHeight = 1.2 + hash(seed + 1.0) * 0.8;  // 1.2 to 2.0

                // Draw stalk
                float stalk = bambooStalk(uv, stalkX, stalkHeight, t,
                                         uniforms.windStrength, uniforms.windSpeed, i);

                // Draw leaves
                float leaves = bambooLeaves(uv, stalkX, stalkHeight, t,
                                           uniforms.windStrength, uniforms.windSpeed,
                                           uniforms.leafDensity, i);

                totalBrightness = max(totalBrightness, stalk);
                totalBrightness = max(totalBrightness, leaves);
            }

            // ========== SUBTLE ATMOSPHERE ==========
            // Occasional floating particles (dust/pollen)
            for (uint p = 0; p < 15; p++) {
                float pSeed = float(p) * 17.3;

                float2 particlePos = float2(
                    (hash(pSeed) - 0.5) * 2.0 * uniforms.aspectRatio,
                    (hash(pSeed + 1.0) - 0.5) * 2.0
                );

                // Drift with wind
                particlePos.x += sin(t * 0.3 + pSeed) * 0.2;
                particlePos.y += t * 0.05;  // Slow rise

                // Wrap vertically
                particlePos.y = fmod(particlePos.y + 1.0, 2.0) - 1.0;

                float dist = length(uv - particlePos);
                float particle = smoothstep(0.015, 0.005, dist) * 0.2;
                totalBrightness = max(totalBrightness, particle);
            }

            density[id] = clamp(totalBrightness, 0.0f, 1.0f);
        }

        // Character ramp as ASCII codes: " .:-=+*#%@"
        constant uint charRamp[10] = { 32, 46, 58, 45, 61, 43, 42, 35, 37, 64 };

        kernel void convertToASCII(
            device float* density [[buffer(0)]],
            device uint* cells [[buffer(1)]],
            constant BambooUniforms& uniforms [[buffer(2)]],
            uint id [[thread_position_in_grid]]
        ) {
            uint gridTotal = uniforms.gridSize.x * uniforms.gridSize.y;
            if (id >= gridTotal) return;

            uint col = id % uniforms.gridSize.x;
            uint row = id / uniforms.gridSize.x;

            float brightness = density[id];

            // Apply dithering
            float dither = getDither(col, row, uniforms.ditherMode) * 0.12;
            brightness = clamp(brightness + dither, 0.0f, 1.0f);

            // Map to character ramp
            uint charIdx = uint(brightness * 9.0);
            charIdx = min(charIdx, 9u);

            cells[id] = charRamp[charIdx];
        }
        """

        let library = try device.makeLibrary(source: shaderSource, options: nil)

        guard let renderFunc = library.makeFunction(name: "renderBamboo"),
              let convertFunc = library.makeFunction(name: "convertToASCII") else {
            throw BambooError.pipelineCreationFailed
        }

        renderPipeline = try device.makeComputePipelineState(function: renderFunc)
        convertPipeline = try device.makeComputePipelineState(function: convertFunc)
    }

    // MARK: - ASCIIScene Protocol

    public func resize(to size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        viewportSize = size

        // Calculate grid size
        let charAspect: Float = 0.5
        let viewAspect = Float(size.height / size.width)
        gridWidth = 120
        gridHeight = max(20, UInt32(Float(gridWidth) * viewAspect * charAspect))

        let gridTotal = Int(gridWidth * gridHeight)

        // Create buffers
        densityBuffer = device.makeBuffer(length: gridTotal * MemoryLayout<Float>.stride, options: .storageModeShared)
        cellBuffer = device.makeBuffer(length: gridTotal * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        uniformBuffer = device.makeBuffer(length: MemoryLayout<BambooUniforms>.stride, options: .storageModeShared)

        // Initialize output arrays
        asciiOutput = Array(repeating: Array(repeating: " ", count: Int(gridWidth)), count: Int(gridHeight))
        brightnessOutput = Array(repeating: Array(repeating: 0, count: Int(gridWidth)), count: Int(gridHeight))
    }

    public func update(deltaTime: Float) {
        time += deltaTime

        guard let commandQueue = commandQueue,
              let densityBuffer = densityBuffer,
              let cellBuffer = cellBuffer,
              let uniformBuffer = uniformBuffer,
              let renderPipeline = renderPipeline,
              let convertPipeline = convertPipeline,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Update uniforms
        var uniforms = BambooUniforms(
            gridSize: SIMD2(gridWidth, gridHeight),
            time: time,
            aspectRatio: Float(viewportSize.width / viewportSize.height),
            stalkCount: UInt32(stalkCount),
            windStrength: windStrength,
            windSpeed: windSpeed,
            leafDensity: leafDensity,
            ditherMode: ditherMode
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<BambooUniforms>.stride)

        let gridTotal = Int(gridWidth * gridHeight)
        let threadsPerGroup = MTLSize(width: 256, height: 1, depth: 1)
        let threadGroups = MTLSize(width: (gridTotal + 255) / 256, height: 1, depth: 1)

        // Render bamboo
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(renderPipeline)
            encoder.setBuffer(densityBuffer, offset: 0, index: 0)
            encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        // Convert to ASCII
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(convertPipeline)
            encoder.setBuffer(densityBuffer, offset: 0, index: 0)
            encoder.setBuffer(cellBuffer, offset: 0, index: 1)
            encoder.setBuffer(uniformBuffer, offset: 0, index: 2)
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        // Async read back
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.readBackResults()
            }
        }

        commandBuffer.commit()
    }

    private func readBackResults() {
        guard let densityBuffer = densityBuffer,
              let cellBuffer = cellBuffer else { return }

        let densityPtr = densityBuffer.contents().bindMemory(to: Float.self, capacity: Int(gridWidth * gridHeight))
        let cellPtr = cellBuffer.contents().bindMemory(to: UInt32.self, capacity: Int(gridWidth * gridHeight))

        for row in 0..<Int(gridHeight) {
            for col in 0..<Int(gridWidth) {
                let idx = row * Int(gridWidth) + col
                brightnessOutput[row][col] = densityPtr[idx]
                asciiOutput[row][col] = UnicodeScalar(cellPtr[idx]).map(Character.init) ?? " "
            }
        }
    }

    public func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor) {
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }

    public func getASCIIString() -> String {
        return asciiOutput.map { String($0) }.joined(separator: "\n")
    }
}

// MARK: - Error Types

enum BambooError: Error {
    case pipelineCreationFailed
}

// swiftlint:enable type_body_length function_body_length

#endif // os(macOS)
