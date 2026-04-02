// ASCIITextRenderer.swift
// MetalASCII - Renders ASCII art to an NSView using Core Text
//
// Copyright © 2026 Devys. All rights reserved.

#if os(macOS)
import AppKit
import CoreText

// MARK: - ASCII Text Renderer

/// High-performance ASCII art renderer using Core Text.
/// Renders character grid with per-character brightness.
@MainActor
public class ASCIITextRenderer: NSView {

    // MARK: - Properties

    /// The ASCII character grid
    public var characters: [[Character]] = [] {
        didSet { needsDisplay = true }
    }

    /// Brightness values for each character (0-1)
    public var brightness: [[Float]] = []

    /// Base color for the ASCII art
    public var baseColor: NSColor = .white

    /// Background color
    public var backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)

    /// Font to use for rendering
    public var monoFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)

    /// Character cell size (calculated from font)
    private var cellSize: CGSize = .zero

    /// Cached character attributes
    private var attributeCache: [Int: [NSAttributedString.Key: Any]] = [:]

    // MARK: - Initialization

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        updateCellSize()
    }

    private func updateCellSize() {
        let testString = "M" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: monoFont]
        let size = testString.size(withAttributes: attributes)
        cellSize = CGSize(width: ceil(size.width), height: ceil(size.height))

        // Pre-cache brightness levels
        attributeCache.removeAll()
        for level in 0...255 {
            let brightness = CGFloat(level) / 255.0
            let color = NSColor(
                red: baseColor.redComponent * brightness,
                green: baseColor.greenComponent * brightness,
                blue: baseColor.blueComponent * brightness,
                alpha: 1.0
            )
            attributeCache[level] = [
                .font: monoFont,
                .foregroundColor: color
            ]
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Fill background
        context.setFillColor(backgroundColor.cgColor)
        context.fill(dirtyRect)

        // If no characters yet, draw a loading message
        if characters.isEmpty {
            let loadingText = "Loading..." as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: monoFont,
                .foregroundColor: NSColor.white
            ]
            loadingText.draw(at: CGPoint(x: bounds.midX - 40, y: bounds.midY), withAttributes: attrs)
            return
        }
        guard let fallbackAttributes = attributeCache[255] else { return }

        let rows = characters.count
        let cols = characters.first?.count ?? 0

        // Calculate starting position (centered)
        let totalWidth = CGFloat(cols) * cellSize.width
        let totalHeight = CGFloat(rows) * cellSize.height
        let startX = (bounds.width - totalWidth) / 2
        let startY = (bounds.height - totalHeight) / 2

        // Draw each character
        for row in 0..<rows {
            for col in 0..<characters[row].count {
                let char = characters[row][col]
                if char == " " { continue }  // Skip spaces for performance

                // Get brightness (default to 1.0 if not available)
                let bright: Float
                if row < brightness.count && col < brightness[row].count {
                    bright = brightness[row][col]
                } else {
                    bright = 1.0
                }

                let x = startX + CGFloat(col) * cellSize.width
                let y = startY + CGFloat(rows - 1 - row) * cellSize.height  // Flip Y

                // Get cached attributes
                let level = Int(bright * 255)
                let attrs = attributeCache[min(level, 255)] ?? fallbackAttributes

                let str = String(char) as NSString
                str.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }
    }

    // MARK: - Configuration

    /// Update the font size to fit columns in the view
    public func fitToColumns(_ columns: Int) {
        guard columns > 0 else { return }
        let idealWidth = bounds.width / CGFloat(columns)
        let fontSize = max(4, min(20, idealWidth * 1.6))
        monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        updateCellSize()
        needsDisplay = true
    }

    /// Set the color theme
    public func setColor(_ color: NSColor) {
        baseColor = color
        updateCellSize()  // Rebuild attribute cache
        needsDisplay = true
    }
}

// MARK: - ASCII Scene View with Text Rendering

/// A view that renders an ASCIIScene as text characters.
@MainActor
public class ASCIISceneTextView: NSView {

    private var scene: ASCIIScene?
    private let textRenderer = ASCIITextRenderer()
    private var lastFrameTime: CFTimeInterval = 0

    // Metal resources
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var offscreenTexture: MTLTexture?

    public init(scene: ASCIIScene, frame: CGRect = .zero) {
        self.scene = scene
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0).cgColor

        // Setup Metal
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()

        // Add text renderer
        textRenderer.frame = bounds
        textRenderer.autoresizingMask = [.width, .height]
        addSubview(textRenderer)

        // Start display link
        setupDisplayLink()
    }

    private func setupDisplayLink() {
        // Use a timer instead of CVDisplayLink for simpler MainActor compatibility
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.renderFrame()
            }
        }
    }

    public override func layout() {
        super.layout()
        textRenderer.frame = bounds
        scene?.resize(to: bounds.size)
        textRenderer.fitToColumns(120)  // Default columns

        // Create offscreen texture
        if let device = device {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb,
                width: max(1, Int(bounds.width)),
                height: max(1, Int(bounds.height)),
                mipmapped: false
            )
            desc.usage = [.renderTarget]
            desc.storageMode = .private
            offscreenTexture = device.makeTexture(descriptor: desc)
        }
    }

    private func renderFrame() {
        guard let scene = scene,
              let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let offscreenTexture = offscreenTexture else {
            return
        }

        // Calculate delta time
        let currentTime = CACurrentMediaTime()
        let deltaTime = lastFrameTime == 0 ? 0.016 : Float(currentTime - lastFrameTime)
        lastFrameTime = currentTime

        // Update scene
        scene.update(deltaTime: deltaTime)

        // Create render pass for offscreen rendering
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = offscreenTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1)

        // Render scene
        scene.render(commandBuffer: commandBuffer, renderPassDescriptor: renderPassDesc)

        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateTextRenderer()
            }
        }

        commandBuffer.commit()
    }

    private func updateTextRenderer() {
        guard let flowerScene = scene as? FlowerScene else { return }
        textRenderer.characters = flowerScene.asciiOutput
        textRenderer.brightness = flowerScene.brightnessOutput
    }

    public func setScene(_ scene: ASCIIScene) {
        self.scene = scene
        scene.resize(to: bounds.size)
    }
}

#endif // os(macOS)
