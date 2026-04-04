// MetalEditorView.swift
// DevysEditor - Metal-accelerated code editor
//
// MTKView-based editor view with Metal rendering.

#if os(macOS)
// periphery:ignore:all - Metal editor entry points are reached via NSView/MTKView runtime callbacks
import AppKit
import MetalKit
import OSLog
import Rendering
import Syntax
import Text

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
    var observedDocumentLoadStateRevision: Int = -1

    /// Callback when the document URL changes (Save As)
    var onDocumentURLChange: ((URL) -> Void)?
    
    /// Line buffer for viewport
    var lineBuffer: LineBuffer?
    var displayModel = EditorDisplayModel()
    
    /// Highlight batch size for incremental tokenization
    let highlightBatchSize = 64
    let openHighlightBudgetNanoseconds: UInt64 = 12_000_000

    let syntaxSchedulingCoordinator = EditorSyntaxSchedulingCoordinator()
    var lastHighlightScrollDelta: CGFloat = 0
    var appliedThemeDescriptor: RuntimeThemeDescriptor = ThemeRegistry.preferredThemeDescriptor
    var pendingThemeDescriptor: RuntimeThemeDescriptor?
    var pendingThemeSyntaxController: SyntaxController?
    var semanticOverlaySnapshot: SemanticOverlaySnapshot?
    var largeFilePolicy: EditorLargeFilePolicy = .default
    var preparedFrame: PreparedFrame?
    var openTrackingGeneration = 0
    var openTrackingIdentifier: String?
    var hasRecordedOpenInteractiveFrame = false
    var hasRecordedOpenHighlightedFrame = false
    var revisitTrackingGeneration = 0
    var revisitTrackingIdentifier: String?
    var hasRecordedRevisitInteractiveFrame = false
    var hasRecordedRevisitHighlightedFrame = false
    var visibleEditGeneration = 0
    var pendingVisibleEditIdentifier: String?
    var shouldRecordScrollTrace = false
    
    /// Debug: has logged highlight usage once
    var hasLoggedHighlightUsage = false
    
    /// Configuration
    var configuration: EditorConfiguration = .default {
        didSet { configurationDidChange() }
    }
    
    /// Background color (linear sRGB)
    var backgroundColor: SIMD4<Float> = hexToLinearColor("#0D0D0D")
    
    /// Line number color (linear sRGB)
    var lineNumberColor: SIMD4<Float> = hexToLinearColor("#555555")

    /// Default editor text color (linear sRGB)
    var textColor: SIMD4<Float> = hexToLinearColor("#d4d4d4")
    
    /// Cursor color (linear sRGB) - white for monochrome terminal aesthetic
    var cursorColor: SIMD4<Float> = hexToLinearColor("#FFFFFF", alpha: 0.9)
    
    /// Selection color (linear sRGB) - white for monochrome terminal aesthetic
    var selectionColor: SIMD4<Float> = hexToLinearColor("#FFFFFF", alpha: 0.12)

    /// Selection anchor for drag/shift selection
    var selectionAnchor: TextPosition?
    
    /// Animation time
    var animationTime: Float = 0
    var lastFrameTime: CFTimeInterval = 0
    
    /// Scale factor
    var scaleFactor: CGFloat = 2.0

    var backgroundHighlightTask: Task<Void, Never>? {
        get { syntaxSchedulingCoordinator.backgroundHighlightTask }
        set { syntaxSchedulingCoordinator.backgroundHighlightTask = newValue }
    }

    // periphery:ignore - mirrored task handle for render scheduling coordination
    var visibleHighlightBudgetTask: Task<Void, Never>? {
        get { syntaxSchedulingCoordinator.visibleHighlightBudgetTask }
        set { syntaxSchedulingCoordinator.visibleHighlightBudgetTask = newValue }
    }
    
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
        let bg = hexToLinearColor("#000000")
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
    struct PreparedEditorRow {
        let lineIndex: Int
        let highlightedLine: SyntaxHighlightedLine?
        let lineNumberPacket: ResolvedTextRenderPacket
        let contentPacket: ResolvedTextRenderPacket
    }

    struct DrawContext {
        let document: EditorDocument
        let lineBuffer: LineBuffer
    }

    struct PreparedFrame {
        let displaySnapshot: EditorDisplaySnapshot
        let resolvedRows: [PreparedEditorRow]
    }

    // MARK: - Layout
    
    public override func layout() {
        super.layout()
        mtkView.frame = bounds
        lineBuffer?.viewportHeight = bounds.height
        updateUniforms()
        refreshPreparedFrame()
        highlightVisibleLines()
    }
    
    // MARK: - MTKViewDelegate
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateUniforms()
        refreshPreparedFrame()
    }
    
    public func draw(in view: MTKView) {
        updateAnimationClock()
        guard let frame = preparedFrame else { return }
        SyntaxRuntimeDiagnostics.beginRenderPass(surface: "editor")
        defer { SyntaxRuntimeDiagnostics.endRenderPass(surface: "editor") }
        recordFrameDiagnostics(frame)
        buildCellBuffer(rows: frame.resolvedRows)
        buildOverlayBuffer()
        cellBuffer.syncToGPU()
        overlayBuffer.syncToGPU()
        renderFrame(in: view)
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

    private func updateAnimationClock() {
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            animationTime += Float(currentTime - lastFrameTime)
        }
        lastFrameTime = currentTime
        uniforms.time = animationTime
    }

    // periphery:ignore - retained as a focused guard helper for draw-path evolution
    private func drawContext() -> DrawContext? {
        guard let document,
              let lineBuffer,
              mtkView.drawableSize.width > 0,
              mtkView.drawableSize.height > 0 else {
            return nil
        }
        return DrawContext(document: document, lineBuffer: lineBuffer)
    }

    private func prepareFrame(using context: DrawContext) -> PreparedFrame {
        context.lineBuffer.updateVisibleRange()
        let displaySnapshot = displaySnapshot(
            for: context.lineBuffer.visibleRange,
            document: context.document
        )
        let resolvedRows = displaySnapshot.visibleRows.map { row in
            PreparedEditorRow(
                lineIndex: row.lineIndex,
                highlightedLine: row.highlightedLine,
                lineNumberPacket: glyphAtlas.resolve(row.lineNumberPacket),
                contentPacket: glyphAtlas.resolve(row.contentPacket)
            )
        }
        return PreparedFrame(
            displaySnapshot: displaySnapshot,
            resolvedRows: resolvedRows
        )
    }

    func refreshPreparedFrame(document documentOverride: EditorDocument? = nil) {
        let targetDocument = documentOverride ?? document
        guard let targetDocument,
              let lineBuffer else {
            preparedFrame = nil
            return
        }
        preparedFrame = prepareFrame(
            using: DrawContext(document: targetDocument, lineBuffer: lineBuffer)
        )
    }

    private func recordFrameDiagnostics(_ frame: PreparedFrame) {
        let actualHighlightedLines = frame.displaySnapshot.actualHighlightedLineCount
        let staleLines = frame.displaySnapshot.visibleRows.reduce(into: 0) { count, row in
            if row.highlightedLine?.status == .stale {
                count += 1
            }
        }
        let loadingLines = max(
            0,
            frame.displaySnapshot.visibleRows.count - actualHighlightedLines - staleLines
        )
        let prefetchHits = actualHighlightedLines + staleLines
        let prefetchMisses = loadingLines
        SyntaxRuntimeDiagnostics.recordVisiblePresentation(
            surface: "editor",
            actualHighlightedLines: actualHighlightedLines,
            staleLines: staleLines,
            loadingLines: loadingLines
        )
        SyntaxRuntimeDiagnostics.recordPrefetchSample(
            surface: "editor",
            hits: prefetchHits,
            misses: prefetchMisses
        )
        recordOpenFrameDiagnostics(for: frame)
        recordRevisitFrameDiagnostics(for: frame)
        if shouldRecordScrollTrace {
            SyntaxRuntimeDiagnostics.recordScrollTrace(
                surface: "editor",
                deltaY: Double(lastHighlightScrollDelta),
                actualHighlightedLines: actualHighlightedLines,
                staleLines: staleLines,
                loadingLines: loadingLines,
                prefetchHits: prefetchHits,
                prefetchMisses: prefetchMisses
            )
            shouldRecordScrollTrace = false
        }
        completeVisibleEditIfReady(for: frame)
    }

    private func recordOpenFrameDiagnostics(for frame: PreparedFrame) {
        if let openTrackingIdentifier, !hasRecordedOpenInteractiveFrame {
            SyntaxRuntimeDiagnostics.markFirstInteractiveFrame(
                surface: "editor",
                identifier: openTrackingIdentifier
            )
            hasRecordedOpenInteractiveFrame = true
        }
        let visibleRows = frame.displaySnapshot.visibleRows
        if let openTrackingIdentifier,
           !hasRecordedOpenHighlightedFrame,
           !visibleRows.isEmpty,
           visibleRows.allSatisfy({ $0.highlightedLine?.status.countsAsActual == true }) {
            SyntaxRuntimeDiagnostics.markFirstHighlightedFrame(
                surface: "editor",
                identifier: openTrackingIdentifier
            )
            hasRecordedOpenHighlightedFrame = true
        }
    }

    private func recordRevisitFrameDiagnostics(for frame: PreparedFrame) {
        if let revisitTrackingIdentifier, !hasRecordedRevisitInteractiveFrame {
            SyntaxRuntimeDiagnostics.markFirstInteractiveRevisitFrame(
                surface: "editor",
                identifier: revisitTrackingIdentifier
            )
            hasRecordedRevisitInteractiveFrame = true
        }
        let visibleRows = frame.displaySnapshot.visibleRows
        if let revisitTrackingIdentifier,
           !hasRecordedRevisitHighlightedFrame,
           !visibleRows.isEmpty,
           visibleRows.allSatisfy({ $0.highlightedLine?.status.countsAsActual == true }) {
            SyntaxRuntimeDiagnostics.markFirstHighlightedRevisitFrame(
                surface: "editor",
                identifier: revisitTrackingIdentifier
            )
            hasRecordedRevisitHighlightedFrame = true
        }
    }

    private func completeVisibleEditIfReady(for frame: PreparedFrame) {
        if let visibleEditIdentifier = pendingVisibleEditIdentifier,
           !frame.displaySnapshot.visibleRows.isEmpty,
           frame.displaySnapshot.visibleRows.allSatisfy({ $0.highlightedLine?.status.countsAsActual == true }) {
            SyntaxRuntimeDiagnostics.completeVisibleEdit(
                surface: "editor",
                identifier: visibleEditIdentifier
            )
            pendingVisibleEditIdentifier = nil
        }
    }

    private func renderFrame(in view: MTKView) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = pipeline.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        drawCells(encoder: encoder)
        drawOverlays(encoder: encoder)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        cellBuffer.advanceBuffer()
    }
}

#endif
