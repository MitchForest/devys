// MetalDiffDocumentView.swift
// Metal-backed diff renderer.

#if os(macOS)
import AppKit
import MetalKit
import Syntax
import Rendering

struct HighlightKey: Hashable {
    let content: String
    let language: String
    let themeName: String
}

struct HighlightToken: Sendable {
    let range: Range<Int>
    let foreground: SIMD4<Float>
    let background: SIMD4<Float>?
    let fontStyle: FontStyle
}

actor DiffHighlightEngine {
    private let grammarService = TMRegistry()
    private var tokenizerCache: [String: TMTokenizer] = [:]
    private var resolverCache: [String: ThemeResolver] = [:]

    func highlight(line: String, language: String, themeName: String) async -> [HighlightToken] {
        guard let tokenizer = await tokenizer(for: language),
              let resolver = resolver(for: themeName) else {
            return []
        }

        let result = tokenizer.tokenizeLine(line: line, prevState: nil)
        return result.tokens.compactMap { token in
            guard !token.range.isEmpty else { return nil }
            let style = resolver.resolve(scopes: token.scopes)
            let foreground = hexToLinearColor(style.foreground)
            let background = style.background.map { hexToLinearColor($0) }
            return HighlightToken(
                range: token.range,
                foreground: foreground,
                background: background,
                fontStyle: style.fontStyle
            )
        }
    }

    private func tokenizer(for language: String) async -> TMTokenizer? {
        if let cached = tokenizerCache[language] {
            return cached
        }

        guard TMRegistry.isLanguageAvailable(language) else {
            return nil
        }

        do {
            let grammar = try await grammarService.grammar(for: language)
            let tokenizer = TMTokenizer(grammar: grammar)
            tokenizerCache[language] = tokenizer
            return tokenizer
        } catch {
            return nil
        }
    }

    private func resolver(for themeName: String) -> ThemeResolver? {
        if let cached = resolverCache[themeName] {
            return cached
        }

        if let theme = try? ShikiTheme.load(name: themeName) {
            let resolver = ThemeResolver(theme: theme)
            resolverCache[themeName] = resolver
            return resolver
        }

        if let fallback = try? ShikiTheme.load(name: "github-dark") {
            let resolver = ThemeResolver(theme: fallback)
            resolverCache[themeName] = resolver
            return resolver
        }

        return nil
    }
}

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

    let highlightEngine = DiffHighlightEngine()
    var highlightCache: [HighlightKey: [HighlightToken]] = [:]
    var pendingHighlights: Set<HighlightKey> = []
    var highlightQueue: [HighlightKey] = []
    var highlightTask: Task<Void, Never>?
    let highlightBatchSize = 64
    var syntaxHighlightingEnabled = true
    var maxHighlightLineLength = 1200

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
    private(set) var diffTheme: DiffTheme = .current()
    private(set) var themeName: String = ThemeRegistry().currentThemeName
    private(set) var language: String = "plaintext"
    var splitRatio: CGFloat = 0.5

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
        self.layout = layout
        updateDocumentSize(layout.contentSize)
        resetHighlights()
        updateDividerTrackingArea()
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
    }

    func updateTheme(_ theme: DiffTheme, themeName: String) {
        diffTheme = theme
        if self.themeName != themeName {
            self.themeName = themeName
            resetHighlights()
        }
        applyClearColor()
    }

    func updateLanguage(_ language: String) {
        if self.language != language {
            self.language = language
            resetHighlights()
        }
    }

    func updateSplitRatio(_ ratio: CGFloat) {
        self.splitRatio = max(0.2, min(0.8, ratio))
        updateDividerTrackingArea()
    }

    func updateHighlighting(enabled: Bool, maxLineLength: Int) {
        let normalizedMax = max(0, maxLineLength)
        if syntaxHighlightingEnabled != enabled || maxHighlightLineLength != normalizedMax {
            syntaxHighlightingEnabled = enabled
            maxHighlightLineLength = normalizedMax
            resetHighlights()
        }
    }

    private func updateDocumentSize(_ size: CGSize) {
        frame = CGRect(origin: .zero, size: size)
        updateVisibleRect()
    }

    private func applyClearColor() {
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
}
#endif
