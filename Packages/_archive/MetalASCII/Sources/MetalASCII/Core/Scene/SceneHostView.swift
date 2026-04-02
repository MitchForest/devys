// SceneHostView.swift
// MetalASCII - SwiftUI wrapper for hosting ASCII scenes
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import SwiftUI
import AppKit
import Metal
import MetalKit

// swiftlint:disable type_body_length function_body_length
// swiftlint:disable file_length

// MARK: - Scene Host View

/// SwiftUI view that hosts an ASCIIScene and renders it as text.
public struct SceneHostView: View {

    @Environment(\.devysTheme) private var theme
    @State private var sceneManager = SceneManager()
    @State private var showControls = true
    @State private var showInfo = true

    public init() {}

    public var body: some View {
        ZStack {
            // Background
            theme.base.ignoresSafeArea()

            // Scene rendering
            SceneRenderView(manager: sceneManager, theme: theme)
                .ignoresSafeArea()

            // Overlay UI (fade in/out)
            if showControls || showInfo {
                VStack {
                    HStack {
                        Spacer()
                        if showInfo {
                            sceneInfoOverlay
                                .padding()
                                .transition(.opacity)
                        }
                    }
                    Spacer()
                    if showControls {
                        controlsOverlay
                            .padding()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showControls)
                .animation(.easeInOut(duration: 0.3), value: showInfo)
            }
        }
        .onAppear {
            sceneManager.start()
        }
        .onDisappear {
            sceneManager.stop()
        }
        .onTapGesture(count: 2) {
            // Double-tap to toggle controls
            withAnimation { showControls.toggle() }
        }
        .focusable()
        .onKeyPress { key in
            handleKeyPress(key)
        }
    }

    private func handleKeyPress(_ key: KeyPress) -> KeyPress.Result {
        switch key.characters {
        case " ":
            // Space: toggle controls
            withAnimation { showControls.toggle() }
            return .handled
        case "1":
            sceneManager.currentSceneType = .particle
            return .handled
        case "2":
            sceneManager.currentSceneType = .phyllotaxis
            return .handled
        case "3":
            sceneManager.currentSceneType = .cosmic
            return .handled
        case "4":
            sceneManager.currentSceneType = .flower
            return .handled
        case "5":
            sceneManager.currentSceneType = .gradient
            return .handled
        case "6":
            sceneManager.currentSceneType = .bamboo
            return .handled
        case "d":
            // Cycle dither modes
            let modes: [DitherMode] = [.none, .bayer4x4, .bayer8x8]
            if let idx = modes.firstIndex(of: sceneManager.ditherMode) {
                sceneManager.ditherMode = modes[(idx + 1) % modes.count]
            }
            return .handled
        case "i":
            withAnimation { showInfo.toggle() }
            return .handled
        default:
            return .ignored
        }
    }

    // MARK: - Overlays

    private var sceneInfoOverlay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(sceneManager.currentSceneName)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))

            Text("\(sceneManager.fps, specifier: "%.0f") fps")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            if !showControls {
                Text("SPACE for controls")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.7))
        .cornerRadius(6)
    }

    private var controlsOverlay: some View {
        HStack(spacing: 16) {
            // Scene picker (dropdown)
            HStack(spacing: 8) {
                Text("SCENE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

                Picker("", selection: $sceneManager.currentSceneType) {
                    ForEach(SceneType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .colorScheme(.dark)
            }

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // Dither mode
            HStack(spacing: 8) {
                Text("DITHER")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))

                Picker("", selection: $sceneManager.ditherMode) {
                    Text("None").tag(DitherMode.none)
                    Text("4x4").tag(DitherMode.bayer4x4)
                    Text("8x8").tag(DitherMode.bayer8x8)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .colorScheme(.dark)
            }

            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))

            // Scene-specific controls
            sceneSpecificControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var sceneSpecificControls: some View {
        switch sceneManager.currentSceneType {
        case .particle:
            particleControls
        case .phyllotaxis:
            phyllotaxisControls
        case .cosmic:
            cosmicControls
        case .flower:
            flowerControls
        case .gradient:
            gradientControls
        case .bamboo:
            bambooControls
        }
    }

    private var particleControls: some View {
        HStack(spacing: 16) {
            // Particle count
            HStack(spacing: 6) {
                Text("COUNT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: Binding(
                    get: { Float(sceneManager.particleCount) / 50000.0 },
                    set: { sceneManager.particleCount = Int($0 * 50000) }
                ), in: 0.2...1.0)
                .frame(width: 60)
                .tint(.white)

                Text("\(sceneManager.particleCount / 1000)k")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 28)
            }

            // Turbulence
            HStack(spacing: 6) {
                Text("TURB")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.turbulence, in: 0.2...2.5)
                    .frame(width: 50)
                    .tint(.white)
            }

            // Trail persistence
            HStack(spacing: 6) {
                Text("TRAIL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.trailPersistence, in: 0.5...0.98)
                    .frame(width: 50)
                    .tint(.white)
            }

            // Speed
            HStack(spacing: 6) {
                Text("SPEED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.speed, in: 0.2...3.0)
                    .frame(width: 50)
                    .tint(.white)
            }
        }
    }

    private var phyllotaxisControls: some View {
        HStack(spacing: 16) {
            // Point count
            HStack(spacing: 6) {
                Text("POINTS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: Binding(
                    get: { Float(sceneManager.phyllotaxisPoints) / 5000.0 },
                    set: { sceneManager.phyllotaxisPoints = Int($0 * 5000) }
                ), in: 0.1...1.0)
                .frame(width: 60)
                .tint(.white)

                Text("\(sceneManager.phyllotaxisPoints)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 40)
            }

            // Pulse intensity
            HStack(spacing: 6) {
                Text("PULSE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.phyllotaxisPulse, in: 0...1)
                    .frame(width: 50)
                    .tint(.white)
            }

            // Rotation speed
            HStack(spacing: 6) {
                Text("ROTATE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.phyllotaxisRotation, in: 0...1)
                    .frame(width: 50)
                    .tint(.white)
            }
        }
    }

    private var cosmicControls: some View {
        HStack(spacing: 16) {
            // Ring count
            HStack(spacing: 6) {
                Text("RINGS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Stepper("", value: $sceneManager.cosmicRings, in: 2...16)
                    .labelsHidden()
                    .colorScheme(.dark)

                Text("\(sceneManager.cosmicRings)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 20)
            }

            // Sphere count
            HStack(spacing: 6) {
                Text("SPHERES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Stepper("", value: $sceneManager.cosmicSpheres, in: 4...24)
                    .labelsHidden()
                    .colorScheme(.dark)

                Text("\(sceneManager.cosmicSpheres)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 20)
            }

            // Rotation speed
            HStack(spacing: 6) {
                Text("SPEED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.cosmicRotation, in: 0.1...1.0)
                    .frame(width: 50)
                    .tint(.white)
            }
        }
    }

    private var flowerControls: some View {
        HStack(spacing: 16) {
            // Petals
            HStack(spacing: 6) {
                Text("PETALS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Stepper("", value: $sceneManager.petalCount, in: 3...12)
                    .labelsHidden()
                    .colorScheme(.dark)

                Text("\(sceneManager.petalCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 20)
            }

            // Wind
            HStack(spacing: 6) {
                Text("WIND")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.windStrength, in: 0...1)
                    .frame(width: 80)
                    .tint(.white)
            }
        }
    }

    private var gradientControls: some View {
        HStack(spacing: 16) {
            // Gradient type
            HStack(spacing: 6) {
                Text("TYPE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Picker("", selection: $sceneManager.gradientType) {
                    Text("H").tag(0)
                    Text("V").tag(1)
                    Text("R").tag(2)
                    Text("D").tag(3)
                    Text("W").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                .colorScheme(.dark)
            }

            // Hover intensity
            HStack(spacing: 6) {
                Text("HOVER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.hoverIntensity, in: 0...1)
                    .frame(width: 60)
                    .tint(.white)
            }

            // Flow speed
            HStack(spacing: 6) {
                Text("FLOW")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.flowSpeed, in: 0...1)
                    .frame(width: 60)
                    .tint(.white)
            }
        }
    }

    private var bambooControls: some View {
        HStack(spacing: 16) {
            // Stalk count
            HStack(spacing: 6) {
                Text("STALKS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Stepper("", value: $sceneManager.bambooStalkCount, in: 5...40)
                    .labelsHidden()
                    .colorScheme(.dark)

                Text("\(sceneManager.bambooStalkCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 24)
            }

            // Wind strength
            HStack(spacing: 6) {
                Text("WIND")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.bambooWindStrength, in: 0...1)
                    .frame(width: 60)
                    .tint(.white)
            }

            // Wind speed
            HStack(spacing: 6) {
                Text("SPEED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.bambooWindSpeed, in: 0.2...2.0)
                    .frame(width: 60)
                    .tint(.white)
            }

            // Leaf density
            HStack(spacing: 6) {
                Text("LEAVES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))

                Slider(value: $sceneManager.bambooLeafDensity, in: 0...1)
                    .frame(width: 60)
                    .tint(.white)
            }
        }
    }
}

// MARK: - Available Scenes

/// Enumeration of available scene types.
public enum SceneType: String, CaseIterable, Identifiable, Sendable {
    case particle = "Particle"
    case phyllotaxis = "Phyllotaxis"
    case cosmic = "Cosmic"
    case flower = "Flower"
    case gradient = "Gradient"
    case bamboo = "Bamboo"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .particle: return "Ethereal particle cloud with noise-based flow"
        case .phyllotaxis: return "Golden angle spiral (sunflower pattern)"
        case .cosmic: return "3D orbital rings and spheres"
        case .flower: return "Procedural rose-curve flower with wind animation"
        case .gradient: return "Interactive gradient with mouse effects"
        case .bamboo: return "Bamboo forest swaying in the wind"
        }
    }
}

// MARK: - Scene Manager

/// Manages the current scene and its configuration.
@MainActor
@Observable
public class SceneManager {

    // Scene state
    public var currentSceneType: SceneType = .particle {
        didSet { switchScene(to: currentSceneType) }
    }
    public var currentSceneName: String { currentSceneType.rawValue }
    public var fps: Double = 0

    // Configuration
    public var ditherMode: DitherMode = .bayer8x8 {
        didSet { updateSceneConfig() }
    }

    // Particle-specific config
    public var particleCount: Int = 30000 {
        didSet { updateSceneConfig() }
    }
    public var turbulence: Float = 1.2 {
        didSet { updateSceneConfig() }
    }
    public var trailPersistence: Float = 0.85 {
        didSet { updateSceneConfig() }
    }
    public var speed: Float = 1.0 {
        didSet { updateSceneConfig() }
    }

    // Flower-specific config
    public var windStrength: Float = 0.4 {
        didSet { updateSceneConfig() }
    }
    public var petalCount: Int = 5 {
        didSet { updateSceneConfig() }
    }

    // Gradient-specific config
    public var gradientType: Int = 2 {
        didSet { updateSceneConfig() }
    }
    public var waveAmplitude: Float = 0.15 {
        didSet { updateSceneConfig() }
    }
    public var hoverIntensity: Float = 0.6 {
        didSet { updateSceneConfig() }
    }
    public var flowSpeed: Float = 0.3 {
        didSet { updateSceneConfig() }
    }

    // Mouse state (updated by MetalSceneView)
    public var mousePosition: SIMD2<Float> = .zero {
        didSet { gradientScene?.mousePosition = mousePosition }
    }

    // Bamboo-specific config
    public var bambooStalkCount: Int = 20 {
        didSet { updateSceneConfig() }
    }
    public var bambooWindStrength: Float = 0.5 {
        didSet { updateSceneConfig() }
    }
    public var bambooWindSpeed: Float = 1.0 {
        didSet { updateSceneConfig() }
    }
    public var bambooLeafDensity: Float = 0.6 {
        didSet { updateSceneConfig() }
    }

    // Phyllotaxis-specific config
    public var phyllotaxisPoints: Int = 2000 {
        didSet { updateSceneConfig() }
    }
    public var phyllotaxisPulse: Float = 0.3 {
        didSet { updateSceneConfig() }
    }
    public var phyllotaxisRotation: Float = 0.2 {
        didSet { updateSceneConfig() }
    }

    // Cosmic-specific config
    public var cosmicRings: Int = 8 {
        didSet { updateSceneConfig() }
    }
    public var cosmicSpheres: Int = 12 {
        didSet { updateSceneConfig() }
    }
    public var cosmicRotation: Float = 0.3 {
        didSet { updateSceneConfig() }
    }

    // Internal - scenes
    var particleScene: ParticleCloudScene?
    var phyllotaxisScene: PhyllotaxisScene?
    var cosmicScene: CosmicScene?
    var flowerScene: FlowerScene?
    var gradientScene: GradientScene?
    var bambooScene: BambooScene?
    private var device: MTLDevice?

    // FPS tracking
    private var frameCount: Int = 0
    private var fpsUpdateTime: CFTimeInterval = 0

    public init() {}

    func start() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            metalASCIILog("Error: No Metal device available")
            return
        }
        self.device = device

        switchScene(to: currentSceneType)
    }

    private func switchScene(to type: SceneType) {
        guard let device = device else { return }

        do {
            switch type {
            case .particle:
                if particleScene == nil {
                    particleScene = try ParticleCloudScene(device: device)
                }
                phyllotaxisScene = nil
                cosmicScene = nil
                flowerScene = nil
                gradientScene = nil
                bambooScene = nil

            case .phyllotaxis:
                if phyllotaxisScene == nil {
                    phyllotaxisScene = try PhyllotaxisScene(device: device)
                }
                particleScene = nil
                cosmicScene = nil
                flowerScene = nil
                gradientScene = nil
                bambooScene = nil

            case .cosmic:
                if cosmicScene == nil {
                    cosmicScene = try CosmicScene(device: device)
                }
                particleScene = nil
                phyllotaxisScene = nil
                flowerScene = nil
                gradientScene = nil
                bambooScene = nil

            case .flower:
                if flowerScene == nil {
                    flowerScene = try FlowerScene(device: device)
                }
                particleScene = nil
                phyllotaxisScene = nil
                cosmicScene = nil
                gradientScene = nil
                bambooScene = nil

            case .gradient:
                if gradientScene == nil {
                    gradientScene = try GradientScene(device: device)
                }
                particleScene = nil
                phyllotaxisScene = nil
                cosmicScene = nil
                flowerScene = nil
                bambooScene = nil

            case .bamboo:
                if bambooScene == nil {
                    bambooScene = try BambooScene(device: device)
                }
                particleScene = nil
                phyllotaxisScene = nil
                cosmicScene = nil
                flowerScene = nil
                gradientScene = nil
            }
            updateSceneConfig()
        } catch {
            metalASCIILog("Error creating scene: \(error)")
        }
    }

    func stop() {
        particleScene = nil
        phyllotaxisScene = nil
        cosmicScene = nil
        flowerScene = nil
        gradientScene = nil
        bambooScene = nil
    }

    /// Get the current active scene.
    var currentScene: ASCIIScene? {
        switch currentSceneType {
        case .particle: return particleScene
        case .phyllotaxis: return phyllotaxisScene
        case .cosmic: return cosmicScene
        case .flower: return flowerScene
        case .gradient: return gradientScene
        case .bamboo: return bambooScene
        }
    }

    /// Get ASCII output from current scene.
    var asciiOutput: [[Character]] {
        switch currentSceneType {
        case .particle: return particleScene?.asciiOutput ?? []
        case .phyllotaxis: return phyllotaxisScene?.asciiOutput ?? []
        case .cosmic: return cosmicScene?.asciiOutput ?? []
        case .flower: return flowerScene?.asciiOutput ?? []
        case .gradient: return gradientScene?.asciiOutput ?? []
        case .bamboo: return bambooScene?.asciiOutput ?? []
        }
    }

    /// Get brightness output from current scene.
    var brightnessOutput: [[Float]] {
        switch currentSceneType {
        case .particle: return particleScene?.brightnessOutput ?? []
        case .phyllotaxis: return phyllotaxisScene?.brightnessOutput ?? []
        case .cosmic: return cosmicScene?.brightnessOutput ?? []
        case .flower: return flowerScene?.brightnessOutput ?? []
        case .gradient: return gradientScene?.brightnessOutput ?? []
        case .bamboo: return bambooScene?.brightnessOutput ?? []
        }
    }

    func update(deltaTime: Float) {
        currentScene?.update(deltaTime: deltaTime)

        // Update FPS
        frameCount += 1
        let currentTime = CACurrentMediaTime()
        if currentTime - fpsUpdateTime >= 1.0 {
            fps = Double(frameCount) / (currentTime - fpsUpdateTime)
            frameCount = 0
            fpsUpdateTime = currentTime
        }
    }

    func resize(to size: CGSize) {
        currentScene?.resize(to: size)
    }

    private func updateSceneConfig() {
        // Update particle config
        if let scene = particleScene {
            scene.particleCount = particleCount
            scene.turbulence = turbulence
            scene.trailPersistence = trailPersistence
            scene.speed = speed
            scene.ditherMode = ditherMode.shaderIndex
        }

        // Update phyllotaxis config
        if let scene = phyllotaxisScene {
            scene.pointCount = phyllotaxisPoints
            scene.pulseIntensity = phyllotaxisPulse
            scene.rotationSpeed = phyllotaxisRotation
            scene.ditherMode = ditherMode.shaderIndex
        }

        // Update cosmic config
        if let scene = cosmicScene {
            scene.ringCount = cosmicRings
            scene.sphereCount = cosmicSpheres
            scene.rotationSpeed = cosmicRotation
            scene.ditherMode = ditherMode.shaderIndex
        }

        // Update flower config
        if let scene = flowerScene {
            scene.ditherMode = ditherMode.shaderIndex
            scene.windStrength = windStrength
            scene.petalCount = UInt32(petalCount)
        }

        // Update gradient config
        if let scene = gradientScene {
            scene.ditherMode = ditherMode.shaderIndex
            scene.gradientType = GradientScene.GradientType(rawValue: gradientType) ?? .radial
            scene.waveAmplitude = waveAmplitude
            scene.hoverIntensity = hoverIntensity
            scene.flowSpeed = flowSpeed
            scene.mousePosition = mousePosition
        }

        // Update bamboo config
        if let scene = bambooScene {
            scene.ditherMode = ditherMode.shaderIndex
            scene.stalkCount = bambooStalkCount
            scene.windStrength = bambooWindStrength
            scene.windSpeed = bambooWindSpeed
            scene.leafDensity = bambooLeafDensity
        }
    }
}

// MARK: - Scene Render View (Metal-based)

struct SceneRenderView: NSViewRepresentable {
    let manager: SceneManager
    let theme: ASCIITheme

    func makeNSView(context: Context) -> MetalSceneView {
        MetalSceneView(manager: manager, theme: theme)
    }

    func updateNSView(_ nsView: MetalSceneView, context: Context) {
        nsView.updateTheme(theme)
    }

    static func dismantleNSView(_ nsView: MetalSceneView, coordinator: ()) {
        nsView.stop()
    }
}

/// MTKView-based renderer for 60fps GPU-accelerated ASCII rendering.
class MetalSceneView: MTKView {
    private var manager: SceneManager
    private var renderer: MetalASCIIRenderer?
    private var cachedSize: CGSize = .zero
    private var trackingArea: NSTrackingArea?

    @MainActor
    init(manager: SceneManager, theme: ASCIITheme) {
        self.manager = manager

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        super.init(frame: .zero, device: device)

        // Configure MTKView for optimal performance
        self.preferredFramesPerSecond = 60
        self.enableSetNeedsDisplay = false  // Use display link, not manual
        self.isPaused = false
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)

        // Create renderer
        do {
            renderer = try MetalASCIIRenderer(device: device)
            self.delegate = renderer

            // Update theme colors
            updateTheme(theme)

            // Setup frame callback
            renderer?.onFrameUpdate = { [weak self] deltaTime in
                self?.updateScene(deltaTime: deltaTime)
            }
        } catch {
            metalASCIILog("Failed to create MetalASCIIRenderer: \(error)")
        }

        // Enable mouse tracking
        updateTrackingAreas()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Mouse Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateMousePosition(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        let position = normalizedMousePosition(from: event)

        // Add click shockwave to gradient scene
        if let gradientScene = manager.gradientScene {
            gradientScene.addClick(at: position, intensity: 1.0)
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Move mouse position off-screen when exiting
        Task { @MainActor in
            manager.mousePosition = SIMD2<Float>(-10, -10)
        }
    }

    private func updateMousePosition(with event: NSEvent) {
        let position = normalizedMousePosition(from: event)
        Task { @MainActor in
            manager.mousePosition = position
        }
    }

    private func normalizedMousePosition(from event: NSEvent) -> SIMD2<Float> {
        let location = convert(event.locationInWindow, from: nil)
        let size = bounds.size

        guard size.width > 0 && size.height > 0 else {
            return .zero
        }

        // Convert to normalized coordinates (-1 to 1)
        let x = (Float(location.x) / Float(size.width) - 0.5) * 2.0
        let y = (Float(location.y) / Float(size.height) - 0.5) * 2.0

        // Apply aspect ratio to match shader coordinates
        let aspectRatio = Float(size.width / size.height)

        return SIMD2<Float>(x * aspectRatio, -y)  // Flip Y for shader coords
    }

    // Make view accept first responder for mouse events
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    @MainActor
    func updateTheme(_ theme: ASCIITheme) {
        let textColor = NSColor(theme.text)
        let baseColor = NSColor(theme.base)

        renderer?.foregroundColor = SIMD4(
            Float(textColor.redComponent),
            Float(textColor.greenComponent),
            Float(textColor.blueComponent),
            1.0
        )
        renderer?.backgroundColor = SIMD4(
            Float(baseColor.redComponent),
            Float(baseColor.greenComponent),
            Float(baseColor.blueComponent),
            1.0
        )

        clearColor = MTLClearColor(
            red: Double(baseColor.redComponent),
            green: Double(baseColor.greenComponent),
            blue: Double(baseColor.blueComponent),
            alpha: 1.0
        )
    }

    @MainActor
    private func updateScene(deltaTime: Float) {
        // Resize only when size actually changes
        let currentSize = bounds.size
        if currentSize != cachedSize && currentSize.width > 0 && currentSize.height > 0 {
            cachedSize = currentSize
            manager.resize(to: currentSize)
        }

        // Update scene
        manager.update(deltaTime: deltaTime)

        // Update FPS display
        if let renderer = renderer {
            manager.fps = renderer.fps
        }

        // Send updated grid to renderer
        renderer?.updateGrid(
            ascii: manager.asciiOutput,
            brightness: manager.brightnessOutput
        )
    }

    @MainActor
    func stop() {
        isPaused = true
        delegate = nil
    }
}

// swiftlint:enable type_body_length function_body_length

#endif // os(macOS)
