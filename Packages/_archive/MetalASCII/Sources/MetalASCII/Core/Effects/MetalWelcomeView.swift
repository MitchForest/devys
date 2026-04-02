// MetalWelcomeView.swift
// DevysUI - GPU-accelerated animated welcome effects
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import SwiftUI
import MetalKit

// swiftlint:disable type_body_length function_body_length cyclomatic_complexity

// MARK: - SwiftUI Wrapper

/// SwiftUI view that displays GPU-accelerated animated welcome effects.
///
/// ## Usage
/// ```swift
/// MetalWelcomeView(effectType: .constellation)
///     .environment(\.devysTheme, theme)
/// ```
///
/// ## Features
/// - 60fps GPU-accelerated rendering
/// - Multiple effect types (constellation, flow field, waves, etc.)
/// - Theme-aware accent color integration
/// - Automatic cleanup on view removal
public struct MetalWelcomeView: NSViewRepresentable {

    @Environment(\.devysTheme) private var theme

    let effectType: WelcomeEffectType

    /// Creates a Metal welcome view with specified effect.
    /// - Parameter effectType: The visual effect to display
    public init(effectType: WelcomeEffectType = .constellation) {
        self.effectType = effectType
    }

    public func makeNSView(context: Context) -> WelcomeMetalView {
        let view = WelcomeMetalView(effectType: effectType)
        view.updateColors(accent: theme.accent, background: theme.base)
        return view
    }

    public func updateNSView(_ nsView: WelcomeMetalView, context: Context) {
        nsView.effectType = effectType
        nsView.updateColors(accent: theme.accent, background: theme.base)
    }
}

// MARK: - MTKView Implementation

/// MTKView subclass that renders animated welcome effects at 60fps.
///
/// Implements MTKViewDelegate for the render loop. Each frame:
/// 1. Updates particle positions via compute shader (if needed)
/// 2. Renders particles/geometry via render pipeline
/// 3. Optionally renders connection lines (constellation)
@MainActor
public final class WelcomeMetalView: MTKView, MTKViewDelegate {

    // MARK: - Properties

    /// Render pipeline manager
    private var pipeline: WelcomeRenderPipeline?

    /// Current effect type
    public var effectType: WelcomeEffectType {
        didSet {
            if effectType != oldValue {
                reinitializeBuffers()
            }
        }
    }

    /// GPU buffers
    private var particleBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    private var lineBuffer: MTLBuffer?
    private var matrixColumnBuffer: MTLBuffer?

    /// Uniforms
    private var uniforms = WelcomeUniforms()

    /// Animation timing
    private var animationTime: Float = 0
    private var lastFrameTime: CFTimeInterval = 0

    /// Line data for constellation connections
    private var lineVertexCount: Int = 0

    /// Whether initialization succeeded
    private var isInitialized = false

    /// Current viewport size (used for particle initialization)
    private var currentViewportSize: CGSize = .zero

    /// Whether particles have been initialized with a valid size
    private var particlesInitialized = false

    // MARK: - Initialization

    /// Create a Metal welcome view with specified effect
    /// - Parameter effectType: The visual effect to display
    public init(effectType: WelcomeEffectType) {
        self.effectType = effectType

        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)

        commonInit()
    }

    required init(coder: NSCoder) {
        self.effectType = .constellation
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard let device = self.device else {
            metalASCIILog("WelcomeMetalView: No Metal device available")
            return
        }

        // Configure MTKView
        self.delegate = self
        self.colorPixelFormat = .bgra8Unorm_srgb
        self.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        self.preferredFramesPerSecond = 60
        self.isPaused = false
        self.enableSetNeedsDisplay = false

        // Allow transparent background
        self.layer?.isOpaque = false

        // Create pipeline
        do {
            pipeline = try WelcomeRenderPipeline(device: device)
            createBuffers()
            isInitialized = true
        } catch {
            metalASCIILog("WelcomeMetalView: Pipeline creation failed: \(error)")
        }
    }

    // MARK: - Buffer Management

    private func createBuffers() {
        guard let device = self.device else { return }

        let particleCount = effectType.defaultParticleCount

        // Particle buffer
        let particleSize = MemoryLayout<Particle>.stride * particleCount
        particleBuffer = device.makeBuffer(length: particleSize, options: .storageModeShared)

        // Uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<WelcomeUniforms>.stride, options: .storageModeShared)

        // Line buffer for constellation (worst case: every particle connected)
        let maxLines = particleCount * particleCount / 2
        let lineBufferSize = MemoryLayout<SIMD4<Float>>.stride * maxLines * 2
        lineBuffer = device.makeBuffer(length: min(lineBufferSize, 1024 * 1024), options: .storageModeShared)

        // Matrix column buffer
        if effectType == .matrixRain {
            let columnCount = particleCount
            let columnSize = MemoryLayout<MatrixColumn>.stride * columnCount
            matrixColumnBuffer = device.makeBuffer(length: columnSize, options: .storageModeShared)
        }

        // Note: Particle initialization is deferred until we have a valid viewport size
        // This happens in mtkView(_:drawableSizeWillChange:)
    }

    private func reinitializeBuffers() {
        particlesInitialized = false
        createBuffers()

        // If we already have a valid viewport size, initialize particles now
        if currentViewportSize.width > 1 && currentViewportSize.height > 1 {
            initializeParticles(for: currentViewportSize)
            if effectType == .matrixRain {
                initializeMatrixColumns(for: currentViewportSize)
            }
        }
    }

    private func initializeParticles(for size: CGSize? = nil) {
        guard let buffer = particleBuffer else { return }

        // Determine the size to use - prefer passed size, then currentViewportSize, then fallback
        let effectiveSize: CGSize
        if let size = size, size.width > 1 && size.height > 1 {
            effectiveSize = size
        } else if currentViewportSize.width > 1 && currentViewportSize.height > 1 {
            effectiveSize = currentViewportSize
        } else {
            // Don't initialize with invalid size - defer until we have a valid one
            return
        }

        let count = effectType.defaultParticleCount
        let particles = buffer.contents().bindMemory(to: Particle.self, capacity: count)

        // Use safe ranges (ensure at least 1 pixel range to avoid empty range crash)
        let maxX = max(Float(effectiveSize.width), 1.0)
        let maxY = max(Float(effectiveSize.height), 1.0)

        for i in 0..<count {
            let position = SIMD2<Float>(
                Float.random(in: 0..<maxX),
                Float.random(in: 0..<maxY)
            )

            let velocity: SIMD2<Float>
            let particleSize: Float

            switch effectType {
            case .constellation:
                velocity = SIMD2<Float>(
                    Float.random(in: -15...15),
                    Float.random(in: -15...15)
                )
                particleSize = Float.random(in: 2...5)

            case .flowField:
                velocity = SIMD2<Float>(
                    Float.random(in: -30...30),
                    Float.random(in: -30...30)
                )
                particleSize = Float.random(in: 1...3)

            case .starfield:
                velocity = SIMD2<Float>(-Float.random(in: 20...80), 0)
                particleSize = Float.random(in: 1...4)

            case .orbits:
                velocity = .zero  // Computed in shader
                particleSize = Float.random(in: 2...4)

            default:
                velocity = .zero
                particleSize = 3.0
            }

            particles[i] = Particle(
                position: position,
                velocity: velocity,
                life: Float.random(in: 0.5...1.0),
                size: particleSize,
                brightness: Float.random(in: 0.4...1.0),
                flags: 0
            )
        }

        particlesInitialized = true
    }

    private func initializeMatrixColumns(for size: CGSize? = nil) {
        guard let buffer = matrixColumnBuffer else { return }

        // Determine the size to use
        let effectiveSize: CGSize
        if let size = size, size.height > 1 {
            effectiveSize = size
        } else if currentViewportSize.height > 1 {
            effectiveSize = currentViewportSize
        } else {
            // Don't initialize with invalid size
            return
        }

        let count = effectType.defaultParticleCount
        let columns = buffer.contents().bindMemory(to: MatrixColumn.self, capacity: count)

        let screenHeight = max(Float(effectiveSize.height), 1.0)

        for i in 0..<count {
            columns[i] = MatrixColumn(
                yOffset: Float.random(in: 0...(screenHeight * 2)),
                speed: Float.random(in: 80...200),
                characterSeed: UInt32.random(in: 0...1000),
                brightness: Float.random(in: 0.5...1.0)
            )
        }
    }

    // MARK: - Color Updates

    /// Update colors from theme
    func updateColors(accent: Color, background: Color) {
        // Convert SwiftUI colors to SIMD4
        if let nsAccent = NSColor(accent).usingColorSpace(.deviceRGB) {
            uniforms.accentColor = SIMD4<Float>(
                Float(nsAccent.redComponent),
                Float(nsAccent.greenComponent),
                Float(nsAccent.blueComponent),
                Float(nsAccent.alphaComponent)
            )
        }

        if let nsBg = NSColor(background).usingColorSpace(.deviceRGB) {
            clearColor = MTLClearColor(
                red: Double(nsBg.redComponent),
                green: Double(nsBg.greenComponent),
                blue: Double(nsBg.blueComponent),
                alpha: 1.0
            )
            uniforms.backgroundColor = SIMD4<Float>(
                Float(nsBg.redComponent),
                Float(nsBg.greenComponent),
                Float(nsBg.blueComponent),
                1.0
            )
        }
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Skip if size is invalid (zero or near-zero dimensions)
        guard size.width > 1 && size.height > 1 else {
            return
        }

        // Store the viewport size
        currentViewportSize = size
        uniforms.viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))

        // Re-initialize particles for new size
        initializeParticles(for: size)
        if effectType == .matrixRain {
            initializeMatrixColumns(for: size)
        }
    }

    public func draw(in view: MTKView) {
        // Don't render until we have valid particles
        guard isInitialized,
              particlesInitialized,
              currentViewportSize.width > 1 && currentViewportSize.height > 1,
              let pipeline = pipeline,
              let commandBuffer = pipeline.commandQueue.makeCommandBuffer(),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        // Calculate delta time
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastFrameTime == 0 ? 0.016 : Float(currentTime - lastFrameTime)
        lastFrameTime = currentTime
        animationTime += deltaTime

        // Update uniforms
        uniforms.time = animationTime
        uniforms.deltaTime = min(deltaTime, 0.05)  // Cap to prevent large jumps
        uniforms.effectType = effectType.shaderEffectID
        uniforms.particleCount = UInt32(effectType.defaultParticleCount)

        // Effect-specific parameters
        switch effectType {
        case .flowField:
            uniforms.effectParam1 = 1.0   // Noise scale
            uniforms.effectParam2 = 1.5   // Speed multiplier
        case .waveField:
            uniforms.effectParam1 = 50    // Grid size
            uniforms.effectParam2 = 1.0   // Wave amplitude
        case .noiseMesh:
            uniforms.effectParam1 = 40    // Grid size
            uniforms.effectParam2 = 1.0   // Noise scale
            uniforms.effectParam3 = 1.0   // Height scale
        case .starfield:
            uniforms.effectParam1 = 1.0   // Speed
        case .orbits:
            uniforms.effectParam1 = 0.5   // Orbit speed
        default:
            break
        }

        // Update uniform buffer
        if let uniformBuffer = uniformBuffer {
            memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<WelcomeUniforms>.stride)
        }

        // Update matrix rain columns (CPU-side for simplicity)
        if effectType == .matrixRain {
            updateMatrixRain(deltaTime: deltaTime)
        }

        // Compute pass (update particles)
        if effectType.usesComputeShader {
            if let computeEncoder = commandBuffer.makeComputeCommandEncoder() {
                computeEncoder.setComputePipelineState(pipeline.particleUpdatePipeline)
                computeEncoder.setBuffer(particleBuffer, offset: 0, index: 0)
                computeEncoder.setBuffer(uniformBuffer, offset: 0, index: 1)

                let threadGroupSize = MTLSize(width: 64, height: 1, depth: 1)
                let particleCount = effectType.defaultParticleCount
                let threadGroups = MTLSize(
                    width: (particleCount + 63) / 64,
                    height: 1,
                    depth: 1
                )
                computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
                computeEncoder.endEncoding()
            }
        }

        // Build connection lines for constellation
        if effectType == .constellation {
            buildConstellationLines()
        }

        // Render pass
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
            renderEncoder.setRenderPipelineState(pipeline.renderPipeline(for: effectType))

            switch effectType {
            case .constellation, .flowField, .starfield, .orbits:
                renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                renderEncoder.drawPrimitives(
                    type: .point,
                    vertexStart: 0,
                    vertexCount: effectType.defaultParticleCount
                )

            case .matrixRain:
                renderEncoder.setVertexBuffer(matrixColumnBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                let columnsCount = effectType.defaultParticleCount
                let charsPerColumn = 25
                renderEncoder.drawPrimitives(
                    type: .point,
                    vertexStart: 0,
                    vertexCount: columnsCount * charsPerColumn,
                    instanceCount: columnsCount
                )

            case .waveField, .noiseMesh:
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 0)
                renderEncoder.drawPrimitives(
                    type: .point,
                    vertexStart: 0,
                    vertexCount: effectType.defaultParticleCount
                )
            }

            // Draw constellation connection lines
            if effectType == .constellation && lineVertexCount > 0 {
                renderEncoder.setRenderPipelineState(pipeline.linePipeline)
                renderEncoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)
                renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                renderEncoder.drawPrimitives(
                    type: .line,
                    vertexStart: 0,
                    vertexCount: lineVertexCount
                )
            }

            renderEncoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Effect-Specific Updates

    private func updateMatrixRain(deltaTime: Float) {
        guard let buffer = matrixColumnBuffer,
              currentViewportSize.height > 1 else { return }

        let count = effectType.defaultParticleCount
        let columns = buffer.contents().bindMemory(to: MatrixColumn.self, capacity: count)
        let screenHeight = Float(currentViewportSize.height)

        for i in 0..<count {
            columns[i].yOffset += columns[i].speed * deltaTime

            // Wrap around
            if columns[i].yOffset > screenHeight + 500 {
                columns[i].yOffset = -200
                columns[i].speed = Float.random(in: 80...200)
                columns[i].brightness = Float.random(in: 0.5...1.0)
            }
        }
    }

    private func buildConstellationLines() {
        guard let particleBuffer = particleBuffer,
              let lineBuffer = lineBuffer else { return }

        let count = effectType.defaultParticleCount
        let particles = particleBuffer.contents().bindMemory(to: Particle.self, capacity: count)
        let lines = lineBuffer.contents().bindMemory(to: SIMD4<Float>.self, capacity: count * count)

        let connectionDistance: Float = 120.0
        var lineIndex = 0
        let maxLines = (lineBuffer.length / MemoryLayout<SIMD4<Float>>.stride) / 2

        // Simple O(n²) approach - could optimize with spatial hashing
        for i in 0..<min(count, 100) {  // Limit checks for performance
            for j in (i + 1)..<min(count, 100) {
                let p1 = particles[i].position
                let p2 = particles[j].position

                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let distSq = dx * dx + dy * dy

                if distSq < connectionDistance * connectionDistance && lineIndex < maxLines - 1 {
                    let dist = sqrt(distSq)
                    let alpha = 1.0 - dist / connectionDistance

                    // Line start
                    lines[lineIndex * 2] = SIMD4<Float>(p1.x, p1.y, alpha, 0)
                    // Line end
                    lines[lineIndex * 2 + 1] = SIMD4<Float>(p2.x, p2.y, alpha, 0)

                    lineIndex += 1
                }
            }
        }

        lineVertexCount = lineIndex * 2
    }
}

// swiftlint:enable type_body_length function_body_length cyclomatic_complexity

#endif // os(macOS)
