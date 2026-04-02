// Scene.swift
// MetalASCII - Reusable scene protocol for ASCII art projects
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import MetalKit

// MARK: - Scene Protocol

/// Protocol for ASCII art scenes/projects.
/// Implement this to create new ASCII art visualizations.
public protocol ASCIIScene: AnyObject {
    /// Display name of the scene
    var name: String { get }

    /// Brief description
    var description: String { get }

    /// Initialize the scene with a Metal device
    init(device: MTLDevice) throws

    /// Called when the view size changes
    func resize(to size: CGSize)

    /// Update scene state (called every frame)
    /// - Parameter deltaTime: Time since last frame in seconds
    func update(deltaTime: Float)

    /// Render the scene
    /// - Parameters:
    ///   - commandBuffer: Metal command buffer
    ///   - renderPassDescriptor: Render pass descriptor
    func render(commandBuffer: MTLCommandBuffer, renderPassDescriptor: MTLRenderPassDescriptor)
}

// MARK: - Scene Registry

/// Registry of available ASCII art scenes
@MainActor
public enum SceneRegistry {
    /// All registered scene types
    public static var scenes: [ASCIIScene.Type] = []

    /// Register a scene type
    public static func register(_ sceneType: ASCIIScene.Type) {
        scenes.append(sceneType)
    }

    /// Create a scene by name
    public static func create(name: String, device: MTLDevice) throws -> ASCIIScene? {
        for sceneType in scenes {
            if let scene = try? sceneType.init(device: device) {
                if scene.name.lowercased() == name.lowercased() {
                    return scene
                }
            }
        }
        return nil
    }
}

// MARK: - Scene View

/// MTKView that hosts an ASCIIScene
@MainActor
public class ASCIISceneView: MTKView, MTKViewDelegate {

    private var scene: ASCIIScene?
    private var lastFrameTime: CFTimeInterval = 0

    public init(scene: ASCIIScene, frame: CGRect = .zero) {
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        self.scene = scene
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.delegate = self
        self.colorPixelFormat = .bgra8Unorm_srgb
        self.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)
        self.preferredFramesPerSecond = 60
        self.isPaused = false
        self.enableSetNeedsDisplay = false
    }

    public func setScene(_ scene: ASCIIScene) {
        self.scene = scene
        scene.resize(to: bounds.size)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        scene?.resize(to: size)
    }

    public func draw(in view: MTKView) {
        guard let scene = scene,
              let device = self.device,
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else {
            return
        }

        // Calculate delta time
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastFrameTime == 0 ? 0.016 : Float(currentTime - lastFrameTime)
        lastFrameTime = currentTime

        // Update and render scene
        scene.update(deltaTime: deltaTime)
        scene.render(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDescriptor)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

#endif // os(macOS)
