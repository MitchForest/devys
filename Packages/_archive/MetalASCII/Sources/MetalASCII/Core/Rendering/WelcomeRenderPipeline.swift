// WelcomeRenderPipeline.swift
// DevysUI - Metal pipeline management for welcome effects
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation
import Metal

// MARK: - Welcome Render Pipeline

/// Manages Metal device, command queue, and shader pipelines for welcome effects.
///
/// Follows the same pattern as DevysTerminal's TerminalRenderPipeline for consistency.
public final class WelcomeRenderPipeline: @unchecked Sendable {

    // MARK: - Properties

    /// The Metal device
    public let device: MTLDevice

    /// Command queue for submitting work
    public let commandQueue: MTLCommandQueue

    /// Shader library
    private let library: MTLLibrary

    // MARK: - Render Pipeline States

    /// Particle rendering pipeline (constellation, flow field, starfield)
    public private(set) var particlePipeline: MTLRenderPipelineState!

    /// Line rendering pipeline (constellation connections)
    public private(set) var linePipeline: MTLRenderPipelineState!

    /// Wave/grid field pipeline
    public private(set) var gridPipeline: MTLRenderPipelineState!

    /// Matrix rain pipeline
    public private(set) var matrixRainPipeline: MTLRenderPipelineState!

    /// Noise mesh pipeline
    public private(set) var noiseMeshPipeline: MTLRenderPipelineState!

    // MARK: - Compute Pipeline States

    /// Particle physics update compute pipeline
    public private(set) var particleUpdatePipeline: MTLComputePipelineState!

    // MARK: - Initialization

    /// Create render pipeline with optional Metal device
    /// - Parameter device: Metal device (uses system default if nil)
    public init(device: MTLDevice? = nil) throws {
        // Get or create device
        guard let metalDevice = device ?? MTLCreateSystemDefaultDevice() else {
            throw WelcomeRenderError.noMetalDevice
        }
        self.device = metalDevice

        // Create command queue
        guard let queue = metalDevice.makeCommandQueue() else {
            throw WelcomeRenderError.commandQueueFailed
        }
        self.commandQueue = queue

        // Load shader library
        // Try SPM bundle first, then default library, then compile from source
        if let lib = try? metalDevice.makeDefaultLibrary(bundle: Bundle.module) {
            self.library = lib
        } else if let defaultLib = metalDevice.makeDefaultLibrary() {
            self.library = defaultLib
        } else {
            throw WelcomeRenderError.shaderNotFound("WelcomeShaders library")
        }

        // Create all pipeline states
        try createRenderPipelines()
        try createComputePipelines()
    }

    // MARK: - Pipeline Creation

    /// Create all render pipeline states
    private func createRenderPipelines() throws {
        // Particle pipeline (point sprites with glow)
        particlePipeline = try createRenderPipeline(
            vertex: "particleVertex",
            fragment: "particleFragment",
            label: "Particle Pipeline"
        )

        // Line pipeline (constellation connections)
        linePipeline = try createRenderPipeline(
            vertex: "connectionLineVertex",
            fragment: "lineFragment",
            label: "Line Pipeline"
        )

        // Grid/wave field pipeline
        gridPipeline = try createRenderPipeline(
            vertex: "waveFieldVertex",
            fragment: "gridFragment",
            label: "Grid Pipeline"
        )

        // Matrix rain pipeline
        matrixRainPipeline = try createRenderPipeline(
            vertex: "matrixRainVertex",
            fragment: "matrixRainFragment",
            label: "Matrix Rain Pipeline"
        )

        // Noise mesh pipeline
        noiseMeshPipeline = try createRenderPipeline(
            vertex: "noiseMeshVertex",
            fragment: "gridFragment",
            label: "Noise Mesh Pipeline"
        )
    }

    /// Create compute pipeline states
    private func createComputePipelines() throws {
        guard let computeFunc = library.makeFunction(name: "updateParticles") else {
            throw WelcomeRenderError.shaderNotFound("updateParticles")
        }

        particleUpdatePipeline = try device.makeComputePipelineState(function: computeFunc)
    }

    /// Create a render pipeline with specified shaders
    private func createRenderPipeline(
        vertex: String,
        fragment: String,
        label: String
    ) throws -> MTLRenderPipelineState {
        guard let vertexFunc = library.makeFunction(name: vertex) else {
            throw WelcomeRenderError.shaderNotFound(vertex)
        }
        guard let fragmentFunc = library.makeFunction(name: fragment) else {
            throw WelcomeRenderError.shaderNotFound(fragment)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertexFunc
        descriptor.fragmentFunction = fragmentFunc

        // Configure color attachment with alpha blending for particles
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Pipeline Selection

    /// Get the appropriate render pipeline for an effect type
    public func renderPipeline(for effectType: WelcomeEffectType) -> MTLRenderPipelineState {
        switch effectType {
        case .constellation, .flowField, .starfield, .orbits:
            return particlePipeline
        case .waveField:
            return gridPipeline
        case .matrixRain:
            return matrixRainPipeline
        case .noiseMesh:
            return noiseMeshPipeline
        }
    }

    /// Get the primitive type for an effect
    public func primitiveType(for effectType: WelcomeEffectType) -> MTLPrimitiveType {
        switch effectType {
        case .constellation, .flowField, .starfield, .orbits, .matrixRain:
            return .point
        case .waveField, .noiseMesh:
            return .point  // Could be .lineStrip for wireframe
        }
    }
}

// MARK: - Errors

/// Errors that can occur during pipeline creation
public enum WelcomeRenderError: Error, LocalizedError, Sendable {
    case noMetalDevice
    case commandQueueFailed
    case shaderNotFound(String)
    case bufferCreationFailed
    case pipelineCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal-capable device found"
        case .commandQueueFailed:
            return "Failed to create command queue"
        case .shaderNotFound(let name):
            return "Shader not found: \(name)"
        case .bufferCreationFailed:
            return "Failed to create GPU buffer"
        case .pipelineCreationFailed(let error):
            return "Pipeline creation failed: \(error)"
        }
    }
}

// MARK: - GPU Structures (Swift side)

/// Per-frame uniforms - must match Metal struct layout
public struct WelcomeUniforms {
    public var viewportSize: SIMD2<Float> = .zero
    public var time: Float = 0
    public var deltaTime: Float = 0
    public var accentColor = SIMD4<Float>(1, 1, 1, 1)
    public var backgroundColor = SIMD4<Float>(0, 0, 0, 1)
    public var effectType: UInt32 = 0
    public var particleCount: UInt32 = 0
    public var effectParam1: Float = 1.0
    public var effectParam2: Float = 1.0
    public var effectParam3: Float = 1.0
    public var effectParam4: Float = 1.0

    public init() {}
}

/// Individual particle data - must match Metal struct layout
public struct Particle {
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    public var life: Float
    public var size: Float
    public var brightness: Float
    public var flags: UInt32

    public init(
        position: SIMD2<Float> = .zero,
        velocity: SIMD2<Float> = .zero,
        life: Float = 1.0,
        size: Float = 4.0,
        brightness: Float = 1.0,
        flags: UInt32 = 0
    ) {
        self.position = position
        self.velocity = velocity
        self.life = life
        self.size = size
        self.brightness = brightness
        self.flags = flags
    }
}

/// Matrix rain column data - must match Metal struct layout
public struct MatrixColumn {
    public var yOffset: Float
    public var speed: Float
    public var characterSeed: UInt32
    public var brightness: Float

    public init(
        yOffset: Float = 0,
        speed: Float = 100,
        characterSeed: UInt32 = 0,
        brightness: Float = 1.0
    ) {
        self.yOffset = yOffset
        self.speed = speed
        self.characterSeed = characterSeed
        self.brightness = brightness
    }
}
