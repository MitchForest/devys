// GradientScene.swift
// MetalASCII - Interactive GPU-accelerated gradient with mouse effects
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import Metal
import MetalKit
import simd

// swiftlint:disable type_body_length function_body_length

// MARK: - Gradient Scene

/// Interactive GPU-accelerated gradient scene with mouse effects.
///
/// Features:
/// - Full-screen radial gradient with light/shadow aesthetic
/// - Mouse hover gravity lens effect
/// - Click shockwave ripples
/// - Organic flow animation
public final class GradientScene: ASCIIScene, @unchecked Sendable {

    public let name = "Gradient"
    public let description = "Interactive gradient with mouse effects"

    // MARK: - Configuration

    /// Gradient type
    public enum GradientType: Int, CaseIterable, Sendable {
        case horizontal = 0
        case vertical = 1
        case radial = 2
        case diagonal = 3
        case wave = 4
    }

    public var gradientType: GradientType = .radial

    /// Mouse position in normalized coordinates (-1 to 1)
    public var mousePosition: SIMD2<Float> = .zero

    /// Hover effect intensity (0-1)
    public var hoverIntensity: Float = 0.6

    /// Click shockwaves - up to 8 active
    public var clickPoints: [ClickPoint] = []

    /// Organic flow speed
    public var flowSpeed: Float = 0.3

    /// Wave amplitude for additional modulation
    public var waveAmplitude: Float = 0.15

    /// Dithering mode
    public var ditherMode: UInt32 = 2

    // MARK: - Click Point

    public struct ClickPoint {
        public var position: SIMD2<Float>
        public var startTime: Float
        public var intensity: Float

        public init(position: SIMD2<Float>, startTime: Float, intensity: Float = 1.0) {
            self.position = position
            self.startTime = startTime
            self.intensity = intensity
        }
    }

    // MARK: - GPU Resources

    private let device: MTLDevice
    private var commandQueue: MTLCommandQueue?
    private var renderPipeline: MTLComputePipelineState?
    private var convertPipeline: MTLComputePipelineState?

    private var densityBuffer: MTLBuffer?
    private var cellBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var clickBuffer: MTLBuffer?

    // MARK: - State

    private var time: Float = 0
    private var gridWidth: UInt32 = 120
    private var gridHeight: UInt32 = 40
    private var viewportSize: CGSize = .zero

    // MARK: - Output

    public private(set) var asciiOutput: [[Character]] = []
    public private(set) var brightnessOutput: [[Float]] = []

    // MARK: - Shader Uniforms

    private struct GradientUniforms {
        var gridSize: SIMD2<UInt32>
        var time: Float
        var aspectRatio: Float
        var gradientType: UInt32
        var ditherMode: UInt32
        var mousePos: SIMD2<Float>
        var hoverIntensity: Float
        var flowSpeed: Float
        var waveAmplitude: Float
        var clickCount: UInt32
        var padding: SIMD2<Float> = .zero
    }

    private struct GPUClickPoint {
        var position: SIMD2<Float>
        var age: Float  // time since click
        var intensity: Float
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

        struct GradientUniforms {
            uint2 gridSize;
            float time;
            float aspectRatio;
            uint gradientType;
            uint ditherMode;
            float2 mousePos;
            float hoverIntensity;
            float flowSpeed;
            float waveAmplitude;
            uint clickCount;
            float2 padding;
        };

        struct ClickPoint {
            float2 position;
            float age;
            float intensity;
        };

        // Noise functions for organic flow
        float hash(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }

        float noise2D(float2 p) {
            float2 i = floor(p);
            float2 f = fract(p);
            f = f * f * (3.0 - 2.0 * f);

            float a = hash(i);
            float b = hash(i + float2(1.0, 0.0));
            float c = hash(i + float2(0.0, 1.0));
            float d = hash(i + float2(1.0, 1.0));

            return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
        }

        float fbm(float2 p, float time) {
            float value = 0.0;
            float amplitude = 0.5;
            float2 shift = float2(time * 0.1, time * 0.15);

            for (int i = 0; i < 4; i++) {
                value += amplitude * noise2D(p + shift);
                p *= 2.0;
                amplitude *= 0.5;
                shift *= 1.2;
            }
            return value;
        }

        // Dithering
        constant float bayer4x4[16] = {
            0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
            12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
            3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
            15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0
        };

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
            if (mode == 1) {
                uint idx = (y % 4) * 4 + (x % 4);
                return bayer4x4[idx] - 0.5;
            }
            uint idx = (y % 8) * 8 + (x % 8);
            return bayer8x8[idx] - 0.5;
        }

        // Shockwave function
        float shockwave(float2 uv, float2 center, float age, float intensity) {
            float dist = length(uv - center);

            // Ring expands over time
            float ringRadius = age * 1.2;  // expansion speed
            float ringWidth = 0.08;

            // Ring brightness - peaks at the ring edge, fades with age
            float ring = 1.0 - abs(dist - ringRadius) / ringWidth;
            ring = max(0.0, ring);
            ring *= ring;  // sharpen

            // Fade out over time
            float fade = 1.0 - smoothstep(0.0, 2.0, age);

            return ring * intensity * fade * 0.8;
        }

        // Subtle distortion effect - warps the UV coordinates near mouse
        float2 distortUV(float2 uv, float2 mousePos, float intensity) {
            float2 toMouse = mousePos - uv;
            float dist = length(toMouse);

            // Gentle pull toward mouse - creates subtle warping
            float influence = exp(-dist * dist * 2.0) * intensity * 0.15;

            return uv + toMouse * influence;
        }

        // Very subtle brightness modulation near mouse
        float subtleHover(float2 uv, float2 mousePos, float intensity) {
            float dist = length(mousePos - uv);

            // Extremely subtle glow - just a hint
            float glow = exp(-dist * dist * 4.0) * intensity * 0.08;

            // Subtle ripple pattern around mouse
            float ripple = sin(dist * 15.0 - 1.0) * exp(-dist * 3.0) * intensity * 0.03;

            return glow + ripple;
        }

        kernel void renderGradient(
            device float* density [[buffer(0)]],
            constant GradientUniforms& uniforms [[buffer(1)]],
            constant ClickPoint* clicks [[buffer(2)]],
            uint id [[thread_position_in_grid]]
        ) {
            uint gridTotal = uniforms.gridSize.x * uniforms.gridSize.y;
            if (id >= gridTotal) return;

            uint col = id % uniforms.gridSize.x;
            uint row = id / uniforms.gridSize.x;

            // Normalized coordinates (-1 to 1)
            float2 uv = float2(
                (float(col) / float(uniforms.gridSize.x - 1) - 0.5) * 2.0,
                (float(row) / float(uniforms.gridSize.y - 1) - 0.5) * 2.0
            );
            uv.x *= uniforms.aspectRatio;

            float t = uniforms.time;
            float brightness = 0.0;

            // ========== BASE GRADIENT ==========
            switch (uniforms.gradientType) {
                case 0: // Horizontal
                    brightness = (uv.x / uniforms.aspectRatio + 1.0) * 0.5;
                    break;
                case 1: // Vertical
                    brightness = (uv.y + 1.0) * 0.5;
                    break;
                case 2: // Radial (bright center, dark edges)
                    {
                        float dist = length(uv);
                        brightness = 1.0 - smoothstep(0.0, 1.2, dist);
                        // Add soft glow at center
                        brightness += exp(-dist * dist * 2.0) * 0.3;
                    }
                    break;
                case 3: // Diagonal
                    brightness = ((uv.x / uniforms.aspectRatio) + uv.y + 2.0) * 0.25;
                    break;
                case 4: // Wave
                    {
                        float wave1 = sin(uv.x * 3.0 + t) * 0.5 + 0.5;
                        float wave2 = sin(uv.y * 3.0 + t * 0.7) * 0.5 + 0.5;
                        brightness = (wave1 + wave2) * 0.5;
                    }
                    break;
            }

            // ========== ORGANIC FLOW ==========
            float2 flowUV = uv * 2.0;
            float flow = fbm(flowUV, t * uniforms.flowSpeed) - 0.5;
            brightness += flow * uniforms.waveAmplitude;

            // ========== SUBTLE MOUSE DISTORTION ==========
            if (uniforms.hoverIntensity > 0.01) {
                // Warp the UV slightly toward the mouse for gradient distortion
                float2 distortedUV = distortUV(uv, uniforms.mousePos, uniforms.hoverIntensity);

                // Recalculate brightness with distorted coordinates for subtle warping
                if (uniforms.gradientType == 2) {  // Radial
                    float distortedDist = length(distortedUV);
                    float distortedBrightness = 1.0 - smoothstep(0.0, 1.2, distortedDist);
                    distortedBrightness += exp(-distortedDist * distortedDist * 2.0) * 0.3;
                    // Blend between original and distorted
                    brightness = mix(brightness, distortedBrightness, uniforms.hoverIntensity * 0.4);
                }

                // Add very subtle hover glow/ripple
                brightness += subtleHover(uv, uniforms.mousePos, uniforms.hoverIntensity);
            }

            // ========== CLICK SHOCKWAVES ==========
            for (uint i = 0; i < uniforms.clickCount; i++) {
                ClickPoint click = clicks[i];
                float wave = shockwave(uv, click.position, click.age, click.intensity);
                brightness += wave;
            }

            // ========== SUBTLE EDGE VIGNETTE ==========
            float vignette = 1.0 - length(uv) * 0.3;
            brightness *= max(0.5, vignette);

            density[id] = clamp(brightness, 0.0f, 1.0f);
        }

        // Character ramp as ASCII codes: " .:-=+*#%@"
        constant uint charRamp[10] = { 32, 46, 58, 45, 61, 43, 42, 35, 37, 64 };

        kernel void convertToASCII(
            device float* density [[buffer(0)]],
            device uint* cells [[buffer(1)]],
            constant GradientUniforms& uniforms [[buffer(2)]],
            uint id [[thread_position_in_grid]]
        ) {
            uint gridTotal = uniforms.gridSize.x * uniforms.gridSize.y;
            if (id >= gridTotal) return;

            uint col = id % uniforms.gridSize.x;
            uint row = id / uniforms.gridSize.x;

            float brightness = density[id];

            // Apply dithering
            float dither = getDither(col, row, uniforms.ditherMode) * 0.15;
            brightness = clamp(brightness + dither, 0.0f, 1.0f);

            // Map to character ramp (10 levels)
            uint charIdx = uint(brightness * 9.0);
            charIdx = min(charIdx, 9u);

            cells[id] = charRamp[charIdx];
        }
        """

        let library = try device.makeLibrary(source: shaderSource, options: nil)

        guard let renderFunc = library.makeFunction(name: "renderGradient"),
              let convertFunc = library.makeFunction(name: "convertToASCII") else {
            throw GradientError.pipelineCreationFailed
        }

        renderPipeline = try device.makeComputePipelineState(function: renderFunc)
        convertPipeline = try device.makeComputePipelineState(function: convertFunc)
    }

    // MARK: - ASCIIScene Protocol

    public func resize(to size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        viewportSize = size

        // Calculate grid size based on viewport
        let charAspect: Float = 0.5
        let viewAspect = Float(size.height / size.width)
        gridWidth = 120
        gridHeight = max(20, UInt32(Float(gridWidth) * viewAspect * charAspect))

        let gridTotal = Int(gridWidth * gridHeight)

        // Create/resize buffers
        densityBuffer = device.makeBuffer(length: gridTotal * MemoryLayout<Float>.stride, options: .storageModeShared)
        cellBuffer = device.makeBuffer(length: gridTotal * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        uniformBuffer = device.makeBuffer(length: MemoryLayout<GradientUniforms>.stride, options: .storageModeShared)
        clickBuffer = device.makeBuffer(length: 8 * MemoryLayout<GPUClickPoint>.stride, options: .storageModeShared)

        // Initialize output arrays
        asciiOutput = Array(repeating: Array(repeating: " ", count: Int(gridWidth)), count: Int(gridHeight))
        brightnessOutput = Array(repeating: Array(repeating: 0, count: Int(gridWidth)), count: Int(gridHeight))
    }

    public func update(deltaTime: Float) {
        time += deltaTime

        // Age and remove old clicks
        clickPoints = clickPoints.compactMap { click in
            let age = time - click.startTime
            return age < 2.5 ? click : nil  // Remove after 2.5 seconds
        }

        // Limit to 8 active clicks
        if clickPoints.count > 8 {
            clickPoints = Array(clickPoints.suffix(8))
        }

        guard let commandQueue = commandQueue,
              let densityBuffer = densityBuffer,
              let cellBuffer = cellBuffer,
              let uniformBuffer = uniformBuffer,
              let clickBuffer = clickBuffer,
              let renderPipeline = renderPipeline,
              let convertPipeline = convertPipeline,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Update uniforms
        var uniforms = GradientUniforms(
            gridSize: SIMD2(gridWidth, gridHeight),
            time: time,
            aspectRatio: Float(viewportSize.width / viewportSize.height),
            gradientType: UInt32(gradientType.rawValue),
            ditherMode: ditherMode,
            mousePos: mousePosition,
            hoverIntensity: hoverIntensity,
            flowSpeed: flowSpeed,
            waveAmplitude: waveAmplitude,
            clickCount: UInt32(clickPoints.count)
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<GradientUniforms>.stride)

        // Update click points
        var gpuClicks: [GPUClickPoint] = clickPoints.map { click in
            GPUClickPoint(
                position: click.position,
                age: time - click.startTime,
                intensity: click.intensity
            )
        }
        // Pad to 8
        while gpuClicks.count < 8 {
            gpuClicks.append(GPUClickPoint(position: .zero, age: 100, intensity: 0))
        }
        memcpy(clickBuffer.contents(), &gpuClicks, 8 * MemoryLayout<GPUClickPoint>.stride)

        let gridTotal = Int(gridWidth * gridHeight)
        let threadsPerGroup = MTLSize(width: 256, height: 1, depth: 1)
        let threadGroups = MTLSize(width: (gridTotal + 255) / 256, height: 1, depth: 1)

        // Render gradient
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(renderPipeline)
            encoder.setBuffer(densityBuffer, offset: 0, index: 0)
            encoder.setBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setBuffer(clickBuffer, offset: 0, index: 2)
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
        // Just clear - all work done in update()
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            encoder.endEncoding()
        }
    }

    // MARK: - Interaction

    /// Add a click shockwave at the given position
    public func addClick(at position: SIMD2<Float>, intensity: Float = 1.0) {
        let click = ClickPoint(position: position, startTime: time, intensity: intensity)
        clickPoints.append(click)
    }

    /// Get the current frame as an ASCII string
    public func getASCIIString() -> String {
        return asciiOutput.map { String($0) }.joined(separator: "\n")
    }
}

// MARK: - Error Types

enum GradientError: Error {
    case pipelineCreationFailed
}

// swiftlint:enable type_body_length function_body_length

#endif // os(macOS)
