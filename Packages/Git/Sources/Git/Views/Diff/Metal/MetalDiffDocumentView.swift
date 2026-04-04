// MetalDiffDocumentView.swift
// Metal-backed diff renderer.

#if os(macOS)
// periphery:ignore:all - NSView/MTKView entry points are runtime-driven
import AppKit
import MetalKit
import Syntax
import Rendering

// swiftlint:disable type_body_length
@MainActor
final class MetalDiffDocumentView: NSView, MTKViewDelegate {

    // MARK: - Coordinate System

    /// Use flipped coordinates (Y=0 at top, increases downward).
    /// This matches NSScrollView's expected coordinate system for proper scrolling.
    override var isFlipped: Bool { true }

    struct RenderMetrics {
        let scale: Float
        let cellWidth: Float
        let lineHeight: Float
        let lineNumberColumnWidth: Float
        let prefixColumnWidth: Float
        let gutterPadding: Float
        let dividerWidth: Float
    }

    struct PreparedFrame {
        let displaySnapshot: DiffDisplaySnapshot
        let resolvedSnapshot: ResolvedDiffDisplaySnapshot
        let visibleOrigin: CGPoint
        let visibleSize: CGSize
        let renderMetrics: RenderMetrics
    }

    var baseSyntaxController: SyntaxController?
    var modifiedSyntaxController: SyntaxController?
    var pendingBaseSyntaxController: SyntaxController?
    var pendingModifiedSyntaxController: SyntaxController?
    var sourceDocuments: DiffSourceDocuments = .empty
    var baseSemanticOverlaySnapshot: SemanticOverlaySnapshot?
    var modifiedSemanticOverlaySnapshot: SemanticOverlaySnapshot?
    let syntaxSchedulingCoordinator = DiffSyntaxSchedulingCoordinator()
    let highlightBatchSize = 64
    let openHighlightBudgetNanoseconds: UInt64 = 12_000_000
    var syntaxHighlightingEnabled = true
    var maxHighlightLineLength = 1200
    var syntaxBacklogPolicy: SyntaxBacklogPolicy = .fullDocument
    var lastVisibleOriginY: CGFloat = 0
    var lastScrollDeltaY: CGFloat = 0
    var openTrackingGeneration = 0
    var openTrackingIdentifier: String?
    var hasRecordedOpenInteractiveFrame = false
    var hasRecordedOpenHighlightedFrame = false
    var revisitTrackingGeneration = 0
    var revisitTrackingIdentifier: String?
    var hasRecordedRevisitInteractiveFrame = false
    var hasRecordedRevisitHighlightedFrame = false
    var visibleRefreshGeneration = 0
    var pendingVisibleRefreshIdentifier: String?
    var shouldRecordScrollTrace = false

    nonisolated(unsafe) var scrollObserver: NSObjectProtocol?

    var mtkView: MTKView!
    var pipeline: EditorRenderPipeline!
    var glyphAtlas: EditorGlyphAtlas!
    var cellBuffer: EditorCellBuffer!
    var underlayBuffer: EditorOverlayBuffer!
    var overlayBuffer: EditorOverlayBuffer!

    var uniforms = EditorUniforms()
    var metrics: EditorMetrics!
    var scaleFactor: CGFloat = 2.0

    private(set) var layout: DiffRenderLayout?
    private(set) var configuration: DiffRenderConfiguration = .init()
    var diffTheme: DiffTheme = .current()
    var displayModel = DiffDisplayModel()
    var themeName: String = ThemeRegistry.preferredThemeName
    var themeVersion: Int = ThemeRegistry.preferredThemeDescriptor.version
    var pendingThemeName: String?
    var pendingThemeVersion: Int?
    var pendingDiffTheme: DiffTheme?
    private(set) var language: String = "plaintext"
    var splitRatio: CGFloat = 0.5
    var preparedFrame: PreparedFrame?

    // periphery:ignore - mirrored task handle for diff scheduling coordination
    var highlightTask: Task<Void, Never>? {
        get { syntaxSchedulingCoordinator.highlightTask }
        set { syntaxSchedulingCoordinator.highlightTask = newValue }
    }

    // periphery:ignore - mirrored task handle for diff scheduling coordination
    var visibleHighlightBudgetTask: Task<Void, Never>? {
        get { syntaxSchedulingCoordinator.visibleHighlightBudgetTask }
        set { syntaxSchedulingCoordinator.visibleHighlightBudgetTask = newValue }
    }

    /// Callback when split ratio changes via drag
    var onSplitRatioChanged: ((CGFloat) -> Void)?

    /// Whether we're currently dragging the divider
    var isDraggingDivider = false

    /// Tracking area for cursor changes
    var dividerTrackingArea: NSTrackingArea?

    /// Hit zone width for detecting divider interaction (pixels on each side)
    let dividerHitZone: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func commonInit() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("MetalDiffDocumentView: No Metal device available")
        }

        scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0

        mtkView = MTKView(frame: bounds, device: device)
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        applyClearColor()
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.autoresizingMask = []
        addSubview(mtkView)

        do {
            pipeline = try EditorRenderPipeline(device: device)
        } catch {
            fatalError("MetalDiffDocumentView: Failed to create pipeline: \(error)")
        }

        metrics = EditorMetrics.measure(fontSize: configuration.fontSize, fontName: configuration.fontName)
        glyphAtlas = EditorGlyphAtlas(
            device: device,
            fontName: configuration.fontName,
            fontSize: configuration.fontSize,
            scaleFactor: scaleFactor
        )

        cellBuffer = EditorCellBuffer(device: device)
        underlayBuffer = EditorOverlayBuffer(device: device)
        overlayBuffer = EditorOverlayBuffer(device: device)

        updateUniforms()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrollView()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeScrollView()
    }

    func updateLayout(_ layout: DiffRenderLayout) {
        _ = SyntaxRuntimeDiagnostics.recordDiffProjectionWorkDuringRender(
            operation: "MetalDiffDocumentView.updateLayout",
            metadata: "contentHeight=\(layout.contentSize.height)"
        )
        self.layout = layout
        refreshHighlightRequests()
        updateDocumentSize(layout.contentSize)
        updateDividerTrackingArea()
        refreshPreparedFrame()
    }

    func updateConfiguration(_ configuration: DiffRenderConfiguration) {
        let needsFontUpdate = configuration.fontName != self.configuration.fontName
            || configuration.fontSize != self.configuration.fontSize

        self.configuration = configuration

        if needsFontUpdate {
            metrics = EditorMetrics.measure(fontSize: configuration.fontSize, fontName: configuration.fontName)
            if let device = mtkView.device {
                glyphAtlas = EditorGlyphAtlas(
                    device: device,
                    fontName: configuration.fontName,
                    fontSize: configuration.fontSize,
                    scaleFactor: scaleFactor
                )
            }
        }
        updateUniforms()
        refreshPreparedFrame()
    }

    func updateTheme(_ theme: DiffTheme, themeName: String) {
        let descriptor = ThemeRegistry.descriptor(name: themeName)
        if self.themeVersion != descriptor.version {
            beginThemeTransition(to: descriptor, theme: theme)
            return
        }
        diffTheme = theme
        self.themeName = descriptor.name
        self.themeVersion = descriptor.version
        pendingThemeName = nil
        pendingThemeVersion = nil
        pendingDiffTheme = nil
        applyClearColor()
        refreshPreparedFrame()
    }

    func updateLanguage(_ language: String) {
        if self.language != language {
            self.language = language
            refreshHighlightRequests(resetCache: true, resetEngines: true)
        }
    }

    func updateSplitRatio(_ ratio: CGFloat) {
        self.splitRatio = max(0.2, min(0.8, ratio))
        updateDividerTrackingArea()
        refreshPreparedFrame()
    }

    func updateHighlighting(
        enabled: Bool,
        maxLineLength: Int,
        backlogPolicy: SyntaxBacklogPolicy = .fullDocument
    ) {
        let normalizedMax = max(0, maxLineLength)
        if syntaxHighlightingEnabled != enabled
            || maxHighlightLineLength != normalizedMax
            || syntaxBacklogPolicy != backlogPolicy {
            syntaxHighlightingEnabled = enabled
            maxHighlightLineLength = normalizedMax
            syntaxBacklogPolicy = backlogPolicy
            if enabled {
                refreshHighlightRequests(resetCache: true, resetEngines: true)
            } else {
                cancelHighlighting(resetCache: true, resetEngines: true)
            }
        }
    }

    func refreshHighlightRequests(
        resetCache: Bool = false,
        resetEngines: Bool = false
    ) {
        guard let layout else {
            cancelHighlighting(resetCache: resetCache, resetEngines: resetEngines)
            return
        }

        guard syntaxHighlightingEnabled else {
            cancelHighlighting(resetCache: true, resetEngines: true)
            return
        }

        let sources = layout.sourceDocuments
        let shouldRebuildModels = resetCache || resetEngines || sourceDocuments != sources
        sourceDocuments = sources

        if shouldRebuildModels {
            syntaxSchedulingCoordinator.cancelAll()
            pendingBaseSyntaxController = nil
            pendingModifiedSyntaxController = nil
            pendingThemeName = nil
            pendingThemeVersion = nil
            pendingDiffTheme = nil
            baseSyntaxController = sources.hasSourceLines(for: .base) ? SyntaxController(
                documentSnapshot: sources.snapshot(for: .base),
                language: language,
                themeName: themeName,
                maximumTokenizationLineLength: maxHighlightLineLength
            ) : nil
            modifiedSyntaxController = sources.hasSourceLines(for: .modified) ? SyntaxController(
                documentSnapshot: sources.snapshot(for: .modified),
                language: language,
                themeName: themeName,
                maximumTokenizationLineLength: maxHighlightLineLength
            ) : nil
            pendingVisibleRefreshIdentifier = nil
            beginOpenTracking()
        } else if baseSyntaxController != nil || modifiedSyntaxController != nil {
            beginRevisitTracking()
            beginVisibleRefreshTracking()
        }

        refreshSyntaxViewport()
    }

    func cancelHighlighting(
        resetCache: Bool = false,
        resetEngines: Bool = false
    ) {
        syntaxSchedulingCoordinator.cancelAll()
        if resetCache {
            sourceDocuments = .empty
            displayModel.reset()
            preparedFrame = nil
        }
        if resetEngines {
            baseSyntaxController = nil
            modifiedSyntaxController = nil
            pendingBaseSyntaxController = nil
            pendingModifiedSyntaxController = nil
            pendingThemeName = nil
            pendingThemeVersion = nil
            pendingDiffTheme = nil
            displayModel.reset()
            preparedFrame = nil
        }
        pendingVisibleRefreshIdentifier = nil
    }

    private func updateDocumentSize(_ size: CGSize) {
        frame = CGRect(origin: .zero, size: size)
        updateVisibleRect()
    }

    func beginOpenTracking() {
        openTrackingGeneration += 1
        openTrackingIdentifier = "diff-open-\(openTrackingGeneration)"
        hasRecordedOpenInteractiveFrame = false
        hasRecordedOpenHighlightedFrame = false
        guard let openTrackingIdentifier else { return }
        SyntaxRuntimeDiagnostics.beginTrackedOpen(
            surface: "diff",
            identifier: openTrackingIdentifier
        )
    }

    func beginRevisitTracking() {
        revisitTrackingGeneration += 1
        revisitTrackingIdentifier = "diff-revisit-\(revisitTrackingGeneration)"
        hasRecordedRevisitInteractiveFrame = false
        hasRecordedRevisitHighlightedFrame = false
        guard let revisitTrackingIdentifier else { return }
        SyntaxRuntimeDiagnostics.beginTrackedRevisit(
            surface: "diff",
            identifier: revisitTrackingIdentifier
        )
    }

    func beginVisibleRefreshTracking() {
        visibleRefreshGeneration += 1
        pendingVisibleRefreshIdentifier = "diff-refresh-\(visibleRefreshGeneration)"
        guard let pendingVisibleRefreshIdentifier else { return }
        SyntaxRuntimeDiagnostics.beginVisibleEdit(
            surface: "diff",
            identifier: pendingVisibleRefreshIdentifier
        )
    }

    private func beginThemeTransition(
        to descriptor: RuntimeThemeDescriptor,
        theme: DiffTheme
    ) {
        guard syntaxHighlightingEnabled else {
            themeName = descriptor.name
            themeVersion = descriptor.version
            diffTheme = theme
            pendingThemeName = nil
            pendingThemeVersion = nil
            pendingDiffTheme = nil
            applyClearColor()
            return
        }

        pendingThemeName = descriptor.name
        pendingThemeVersion = descriptor.version
        pendingDiffTheme = theme
        syntaxSchedulingCoordinator.cancelAll()
        pendingBaseSyntaxController = sourceDocuments.hasSourceLines(for: .base) ? SyntaxController(
            documentSnapshot: sourceDocuments.snapshot(for: .base),
            language: language,
            themeName: descriptor.name,
            maximumTokenizationLineLength: maxHighlightLineLength
        ) : nil
        pendingModifiedSyntaxController = sourceDocuments.hasSourceLines(for: .modified) ? SyntaxController(
            documentSnapshot: sourceDocuments.snapshot(for: .modified),
            language: language,
            themeName: descriptor.name,
            maximumTokenizationLineLength: maxHighlightLineLength
        ) : nil
        refreshSyntaxViewport()
    }

    func applyClearColor() {
        mtkView.clearColor = MTLClearColor(
            red: Double(diffTheme.background.x),
            green: Double(diffTheme.background.y),
            blue: Double(diffTheme.background.z),
            alpha: Double(diffTheme.background.w)
        )
    }

    func updateUniforms() {
        let scale = Float(scaleFactor)
        uniforms.viewportSize = SIMD2(Float(mtkView.drawableSize.width), Float(mtkView.drawableSize.height))
        uniforms.cellSize = SIMD2(Float(metrics.cellWidth) * scale, Float(metrics.lineHeight) * scale)
        uniforms.atlasSize = SIMD2(Float(glyphAtlas.atlasWidth), Float(glyphAtlas.atlasHeight))
        uniforms.cursorBlinkRate = 2.0
    }

    func refreshPreparedFrame() {
        guard let layout else {
            preparedFrame = nil
            return
        }

        let visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        let visibleOrigin = visibleRect.origin
        let visibleSize = visibleRect.size
        let renderMetrics = makeRenderMetrics()
        let totalRows = rowCount(for: layout)
        guard totalRows > 0 else {
            preparedFrame = nil
            return
        }

        let rowHeight = CGFloat(metrics.lineHeight)
        let startRow = max(0, Int(floor(visibleOrigin.y / rowHeight)))
        let endRow = min(totalRows - 1, Int(ceil((visibleOrigin.y + visibleSize.height) / rowHeight)))
        guard startRow <= endRow else {
            preparedFrame = nil
            return
        }

        let visibleRowRange = startRow...endRow
        let displaySnapshot = displayModel.snapshot(displaySnapshotRequest(
            layout: layout,
            visibleRowRange: visibleRowRange
        ))
        preparedFrame = PreparedFrame(
            displaySnapshot: displaySnapshot,
            resolvedSnapshot: resolve(displaySnapshot),
            visibleOrigin: visibleOrigin,
            visibleSize: visibleSize,
            renderMetrics: renderMetrics
        )
    }

    func refreshSyntaxViewport() {
        syntaxSchedulingCoordinator.refreshViewport { [weak self] in
            self?.syntaxSchedulingContext()
        }
        refreshPreparedFrame()
    }

    func displaySnapshotRequest(
        layout: DiffRenderLayout,
        visibleRowRange: ClosedRange<Int>
    ) -> DiffDisplaySnapshotRequest {
        DiffDisplaySnapshotRequest(
            layout: layout,
            visibleRowRange: visibleRowRange,
            syntaxHighlightingEnabled: syntaxHighlightingEnabled,
            renderContext: DiffDisplayRenderContext(
                themeVersion: themeVersion,
                metrics: metrics,
                diffTheme: diffTheme
            ),
            baseSyntaxSnapshot: baseSyntaxController?.currentSnapshot(),
            modifiedSyntaxSnapshot: modifiedSyntaxController?.currentSnapshot(),
            baseSemanticOverlaySnapshot: baseSemanticOverlaySnapshot,
            modifiedSemanticOverlaySnapshot: modifiedSemanticOverlaySnapshot
        )
    }
}
// swiftlint:enable type_body_length
#endif
