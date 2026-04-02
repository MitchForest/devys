// MetalEditorView.swift
// DevysEditor - Metal-accelerated code editor
//
// MTKView-based editor view with Metal rendering.

#if os(macOS)
import AppKit
import MetalKit
import Syntax
import Rendering
import OSLog

let metalEditorLogger = Logger(subsystem: "com.devys.editor", category: "MetalEditorView")

// MARK: - Metal Editor View

/// GPU-accelerated editor view using Metal.
@MainActor
public final class MetalEditorView: NSView, MTKViewDelegate {
    
    // MARK: - Properties
    
    /// The MTKView for rendering
    var mtkView: MTKView!
    
    /// Render pipeline
    var pipeline: EditorRenderPipeline!
    
    /// Glyph atlas
    var glyphAtlas: EditorGlyphAtlas!
    
    /// Cell buffer
    var cellBuffer: EditorCellBuffer!
    
    /// Overlay buffer
    var overlayBuffer: EditorOverlayBuffer!
    
    /// Current uniforms
    var uniforms = EditorUniforms()
    
    /// Editor metrics
    var metrics: EditorMetrics!
    
    /// Document being edited
    var document: EditorDocument? {
        didSet { documentDidChange() }
    }

    /// Callback when the document URL changes (Save As)
    var onDocumentURLChange: ((URL) -> Void)?
    
    /// Line buffer for viewport
    var lineBuffer: LineBuffer?
    
    /// Highlight engine
    var highlightEngine: HighlightEngine?
    
    /// Cached highlighted lines
    var cachedHighlightedLines: [Int: HighlightedLine] = [:]
    
    /// Whether highlighting is in progress
    var isHighlighting = false

    /// Highlight batch size for incremental tokenization
    let highlightBatchSize = 64

    /// Background highlight task (buffer fill)
    var backgroundHighlightTask: Task<Void, Never>?
    
    /// Debug: has logged highlight usage once
    var hasLoggedHighlightUsage = false
    
    /// Configuration
    var configuration: EditorConfiguration = .default {
        didSet { configurationDidChange() }
    }
    
    /// Background color (linear sRGB)
    var backgroundColor: SIMD4<Float> = hexToLinearColor("#0D0D0D")
    
    /// Foreground color (linear sRGB)
    var foregroundColor: SIMD4<Float> = hexToLinearColor("#EFEFEF")
    
    /// Line number color (linear sRGB)
    var lineNumberColor: SIMD4<Float> = hexToLinearColor("#555555")
    
    /// Cursor color (linear sRGB) - white for monochrome terminal aesthetic
    var cursorColor: SIMD4<Float> = hexToLinearColor("#FFFFFF", alpha: 0.9)
    
    /// Selection color (linear sRGB) - white for monochrome terminal aesthetic
    var selectionColor: SIMD4<Float> = hexToLinearColor("#FFFFFF", alpha: 0.12)

    /// Selection anchor for drag/shift selection
    var selectionAnchor: TextPosition?
    
    // DevysColors palettes (properly converted to linear sRGB)
    struct DevysColorPalette {
        let bg0: SIMD4<Float>
        let text: SIMD4<Float>
        let textTertiary: SIMD4<Float>
        let accent: SIMD4<Float>
        let accentMuted: SIMD4<Float>
    }
    
    static let devysColorsDark = DevysColorPalette(
        bg0: hexToLinearColor("#000000"),           // True black background
        text: hexToLinearColor("#EFEFEF"),          // Primary text
        textTertiary: hexToLinearColor("#666666"),  // Tertiary text (line numbers)
        accent: hexToLinearColor("#FFFFFF"),        // White accent for monochrome
        accentMuted: hexToLinearColor("#FFFFFF", alpha: 0.12)
    )
    
    static let devysColorsLight = DevysColorPalette(
        bg0: hexToLinearColor("#FFFFFF"),           // White background
        text: hexToLinearColor("#1A1A1A"),          // Primary text (near black)
        textTertiary: hexToLinearColor("#888888"),  // Tertiary text (line numbers)
        accent: hexToLinearColor("#1A1A1A"),        // Dark accent for light mode
        accentMuted: hexToLinearColor("#1A1A1A", alpha: 0.12)
    )
    
    /// Animation time
    var animationTime: Float = 0
    var lastFrameTime: CFTimeInterval = 0
    
    /// Scale factor
    var scaleFactor: CGFloat = 2.0
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("MetalEditorView: No Metal device available")
        }
        
        // Create MTKView
        mtkView = MTKView(frame: bounds, device: device)
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        // Use proper linear value for dark background (hexToLinearColor("#0D0D0D"))
        let bg = Self.devysColorsDark.bg0
        mtkView.clearColor = MTLClearColor(red: Double(bg.x), green: Double(bg.y), blue: Double(bg.z), alpha: 1.0)
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoresizingMask = [.width, .height]
        addSubview(mtkView)
        
        // Create render pipeline
        do {
            pipeline = try EditorRenderPipeline(device: device)
        } catch {
            fatalError("MetalEditorView: Failed to create pipeline: \(error)")
        }
        
        // Get scale factor
        scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        
        // Create metrics
        metrics = EditorMetrics.measure(
            fontSize: configuration.fontSize,
            fontName: configuration.fontName
        )
        
        // Create glyph atlas
        glyphAtlas = EditorGlyphAtlas(
            device: device,
            fontName: configuration.fontName,
            fontSize: configuration.fontSize,
            scaleFactor: scaleFactor
        )
        
        // Create buffers
        cellBuffer = EditorCellBuffer(device: device)
        overlayBuffer = EditorOverlayBuffer(device: device)
        
        updateUniforms()
    }
    
}

extension MetalEditorView {
    // MARK: - Layout
    
    public override func layout() {
        super.layout()
        mtkView.frame = bounds
        lineBuffer?.viewportHeight = bounds.height
        updateUniforms()
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateUniforms()
    }
    
    public func draw(in view: MTKView) {
        // Update animation time
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            animationTime += Float(currentTime - lastFrameTime)
        }
        lastFrameTime = currentTime
        uniforms.time = animationTime
        
        guard let document = document,
              let lineBuffer = lineBuffer,
              mtkView.drawableSize.width > 0,
              mtkView.drawableSize.height > 0 else {
            return
        }
        
        // Update visible range
        lineBuffer.updateVisibleRange()
        
        // Get lines to render
        let visibleRange = lineBuffer.visibleRange
        let lines = document.lines(in: visibleRange)
        
        // Check if we need to highlight new lines (on scroll)
        let needsHighlight = visibleRange.contains { lineIndex in
            cachedHighlightedLines[lineIndex] == nil
        }
        
        if needsHighlight && !isHighlighting {
            backgroundHighlightTask?.cancel()
            backgroundHighlightTask = nil
            Task { @MainActor in
                await highlightVisibleLines()
            }
        }
        
        // Build cell buffer
        buildCellBuffer(lines: lines, startLine: visibleRange.lowerBound)
        
        // Build overlay buffer (cursor)
        buildOverlayBuffer()
        
        // Sync to GPU
        cellBuffer.syncToGPU()
        overlayBuffer.syncToGPU()
        
        // Render
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = pipeline.commandQueue.makeCommandBuffer() else {
            return
        }
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        // Draw cells
        drawCells(encoder: encoder)
        
        // Draw overlays
        drawOverlays(encoder: encoder)
        
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        cellBuffer.advanceBuffer()
    }
    
    // MARK: - Drawing
    
    private func drawCells(encoder: MTLRenderCommandEncoder) {
        guard cellBuffer.cellCount > 0 else { return }
        
        encoder.setRenderPipelineState(pipeline.cellPipeline)
        encoder.setVertexBuffer(cellBuffer.currentBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
        
        if let texture = glyphAtlas.texture {
            encoder.setFragmentTexture(texture, index: 0)
        }
        
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4,
            instanceCount: cellBuffer.cellCount
        )
    }
    
    private func drawOverlays(encoder: MTLRenderCommandEncoder) {
        guard overlayBuffer.vertexCount > 0, let buffer = overlayBuffer.currentBuffer else { return }
        
        encoder.setRenderPipelineState(pipeline.overlayPipeline)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<EditorUniforms>.size, index: 1)
        
        encoder.drawPrimitives(
            type: .triangle,
            vertexStart: 0,
            vertexCount: overlayBuffer.vertexCount
        )
    }
    
    // MARK: - Uniforms
    
    private func updateUniforms() {
        let scale = Float(scaleFactor)
        uniforms.viewportSize = SIMD2(Float(mtkView.drawableSize.width), Float(mtkView.drawableSize.height))
        uniforms.cellSize = SIMD2(Float(metrics.cellWidth) * scale, Float(metrics.lineHeight) * scale)
        uniforms.atlasSize = SIMD2(Float(glyphAtlas.atlasWidth), Float(glyphAtlas.atlasHeight))
        uniforms.cursorBlinkRate = 2.0
    }
}

#endif
