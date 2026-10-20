// Net-new for P0-014: the reference repo's terminal had no iOS host at
// all (macOS-only package, plain-text iOS fallback). This UIView host
// drives the same GhosttyMetalTerminalRenderer / TerminalRenderPipeline
// as the macOS host. Scope: software keyboard via
// UIKeyInput/UITextInputTraits with autocorrect and smart substitutions
// off, hardware keyboard via pressesBegan, an accessory bar (Ctrl-C
// interrupt, Esc, Tab, arrows), pan-gesture scrollback, and display-link
// drive (on-demand under Reduced Motion, observed live). P0-045 adds
// touch selection (long-press to select a word, drag handles, edit-menu
// copy) and pinch-to-resize-font (10-20pt, snapped, per pane session).

#if os(iOS)
    import CoreGraphics
    import MetalKit
    import SwiftUI
    import TerminalCore
    import TerminalSurfaceCore
    import TerminalVT
    import UIKit

    struct GhosttyTerminalIOSPlatformView: UIViewRepresentable {
        let renderSession: TerminalSurfaceRenderSession
        let appearance: TerminalAppearance
        let fontSize: CGFloat
        let selectionMode: Bool
        let focusRequestID: Int
        let isSurfaceVisible: Bool
        let targetPointSize: CGSize
        let callbacks: GhosttyTerminalViewCallbacks

        func makeUIView(context _: Context) -> GhosttyTerminalIOSHostView {
            GhosttyTerminalIOSHostView()
        }

        func updateUIView(_ uiView: GhosttyTerminalIOSHostView, context _: Context) {
            uiView.update(viewUpdate, callbacks: callbacks)
        }

        private var viewUpdate: GhosttyTerminalViewUpdate {
            GhosttyTerminalViewUpdate(
                renderSession: renderSession,
                appearance: appearance,
                fontSize: fontSize,
                selectionMode: selectionMode,
                focusRequestID: focusRequestID,
                isSurfaceVisible: isSurfaceVisible,
                targetPointSize: targetPointSize
            )
        }

        static func dismantleUIView(_ uiView: GhosttyTerminalIOSHostView, coordinator _: ()) {
            uiView.uninstallRenderSession()
        }
    }

    final class GhosttyTerminalIOSHostView: UIView, GhosttyTerminalRenderHost {
        let metalView = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        var renderer: GhosttyMetalTerminalRenderer?
        weak var renderSession: TerminalSurfaceRenderSession?
        let drawScheduler = MetalDrawScheduler(surface: "terminal")
        var callbacks = GhosttyTerminalViewCallbacks()
        var currentAppearance = TerminalAppearance.defaultDark
        var currentFontSize: CGFloat = TerminalSurfaceDefaults.fontSize
        var lastAppliedRenderRevision: UInt64?
        var lastAppliedAppearance: TerminalAppearance?
        var lastAppliedFontSize: CGFloat?
        var lastRenderFailure: String?
        private var focusRequestID = 0
        private var lastHandledFocusRequestID = 0
        private var targetPointSize = CGSize.zero
        private var lastSurfaceSize: TerminalSurfacePixelSize?
        private var scrollAccumulator = TerminalScrollAccumulator()
        private var lastPanTranslationY: CGFloat = 0
        private var pressLevelHandledUsages: Set<Int> = []
        /// Sampled at host creation and re-resolved live when the
        /// Reduced Motion setting changes mid-session (P0-045): the
        /// display-link drive swaps for on-demand drawing without a
        /// remount.
        private var driveConfiguration = TerminalIOSInputAdapter.driveConfiguration(
            reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
        )
        private var isSurfaceVisibleState = true
        fileprivate var selectionModeEnabled = true
        fileprivate var pinchBaseFontSize: CGFloat?
        fileprivate var longPressWordRange: TerminalSelectionRange?
        fileprivate var handleDragAnchor: TerminalSelectionPoint?
        fileprivate lazy var editMenuInteraction = UIEditMenuInteraction(delegate: nil)
        fileprivate let startSelectionHandle = TerminalSelectionHandleComponent(knobPlacement: .aboveBar)
        fileprivate let endSelectionHandle = TerminalSelectionHandleComponent(knobPlacement: .belowBar)
        private lazy var accessoryBar: UIToolbar = makeAccessoryBar()

        // UITextInputTraits: a terminal wants raw bytes, never editor
        // assistance.
        var autocorrectionType: UITextAutocorrectionType = .no
        var autocapitalizationType: UITextAutocapitalizationType = .none
        var spellCheckingType: UITextSpellCheckingType = .no
        var smartQuotesType: UITextSmartQuotesType = .no
        var smartDashesType: UITextSmartDashesType = .no
        var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
        var keyboardType: UIKeyboardType = .asciiCapable
        var keyboardAppearance: UIKeyboardAppearance = .default

        override var canBecomeFirstResponder: Bool { true }

        override var inputAccessoryView: UIView? { accessoryBar }

        init() {
            super.init(frame: .zero)
            MetalSurfaceDiagnostics.recordHostCreated(surface: "terminal")
            backgroundColor = .clear
            configureMetalView()
            configureAccessibility()
            configureGestures()
            addSubview(metalView)
            configureSelectionChrome()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reduceMotionStatusDidChange),
                name: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        isolated deinit {
            MetalSurfaceDiagnostics.recordHostDeinitialized(surface: "terminal")
        }
    }

    // MARK: - Update and view lifecycle

    extension GhosttyTerminalIOSHostView {
        func update(_ update: GhosttyTerminalViewUpdate, callbacks: GhosttyTerminalViewCallbacks) {
            self.callbacks = callbacks
            focusRequestID = update.focusRequestID
            currentAppearance = update.appearance
            selectionModeEnabled = update.selectionMode
            targetPointSize = update.targetPointSize
            isSurfaceVisibleState = update.isSurfaceVisible
            metalView.isHidden = !update.isSurfaceVisible
            drawScheduler.setVisible(update.isSurfaceVisible)
            applyDriveConfiguration()
            installRenderSessionIfNeeded(update.renderSession)
            // A pinched size persists for the pane session on the render
            // session, surviving host-view recreation; the view-supplied
            // size applies otherwise.
            currentFontSize = update.renderSession.preferredFontSize ?? update.fontSize

            guard ensureRenderer(fontSize: currentFontSize) else {
                updateAccessibilityGridValue(update.renderSession.surfaceState)
                return
            }

            applyRenderSessionSnapshot()
            updateAccessibilityGridValue(update.renderSession.surfaceState)
            synchronizeHostedGeometry()
            synchronizeSelectionChrome()
            applyFocusRequestIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            synchronizeHostedGeometry()
            requestDraw()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            synchronizeHostedGeometry()
            applyFocusRequestIfNeeded()
            requestDraw()
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            guard previousTraitCollection?.displayScale != traitCollection.displayScale else { return }
            synchronizeHostedGeometry()
            requestDraw()
        }

    }

    // MARK: - Rendering, drive mode, and geometry

    extension GhosttyTerminalIOSHostView {
        func requestDraw() {
            // Every applied snapshot and geometry pass routes through
            // here (GhosttyTerminalRenderHost), so the selection chrome
            // follows engine-driven selection changes too.
            synchronizeSelectionChrome()
            // Display-link mode paces its own frames; only the on-demand
            // (Reduced Motion) mode draws through the scheduler.
            guard metalView.isPaused else { return }
            drawScheduler.requestDraw()
        }

        private func configureMetalView() {
            drawScheduler.attach(metalView)
            metalView.colorPixelFormat = .bgra8Unorm_srgb
            metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            applyDriveConfiguration()
            metalView.autoResizeDrawable = true
            metalView.isOpaque = false
            metalView.backgroundColor = .clear
            metalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        @objc private func reduceMotionStatusDidChange() {
            applyDriveConfigurationIfChanged(
                reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled
            )
        }

        func applyDriveConfigurationIfChanged(reduceMotionEnabled: Bool) {
            let configuration = TerminalIOSInputAdapter.driveConfiguration(
                reduceMotionEnabled: reduceMotionEnabled
            )
            guard configuration != driveConfiguration else { return }
            driveConfiguration = configuration
            applyDriveConfiguration()
            // Entering on-demand mode must paint the current frame
            // through the scheduler; leaving it, the unpaused link
            // resumes on its own.
            requestDraw()
        }

        private func applyDriveConfiguration() {
            metalView.isPaused = TerminalIOSInputAdapter.metalViewIsPaused(
                configuration: driveConfiguration,
                isSurfaceVisible: isSurfaceVisibleState
            )
            metalView.enableSetNeedsDisplay = driveConfiguration.enableSetNeedsDisplay
            metalView.preferredFramesPerSecond = driveConfiguration.preferredFramesPerSecond
            metalView.framebufferOnly = driveConfiguration.framebufferOnly
        }

        var currentScaleFactor: CGFloat {
            let scale = traitCollection.displayScale
            return scale > 0 ? scale : 2
        }

        func ensureRenderer(fontSize: CGFloat) -> Bool {
            if let renderer, renderer.fontSize == GhosttyTerminalFontMetrics.default(fontSize: fontSize).fontSize {
                metalView.delegate = renderer
                lastRenderFailure = nil
                return true
            }
            if renderer != nil {
                renderer = nil
                metalView.delegate = nil
                lastAppliedRenderRevision = nil
                lastAppliedAppearance = nil
                lastAppliedFontSize = nil
            }

            guard let device = metalView.device else {
                reportRenderFailure("Metal terminal rendering is unavailable on this device.")
                return false
            }

            do {
                let renderer = try GhosttyMetalTerminalRenderer(
                    device: device,
                    scaleFactor: currentScaleFactor,
                    fontSize: fontSize,
                    onFirstAtlasMutation: callbacks.onFirstAtlasMutation,
                    onDrawableUnavailable: { [weak self] in
                        guard let self, self.metalView.isPaused else { return }
                        self.drawScheduler.requestRetry()
                    },
                    onFirstFrameCommit: callbacks.onFirstFrameCommit,
                    onFirstInteractiveFrame: callbacks.onFirstInteractiveFrame
                )
                self.renderer = renderer
                metalView.delegate = renderer
                lastRenderFailure = nil
                return true
            } catch {
                reportRenderFailure(
                    "Failed to initialize the Metal terminal renderer: \(error.localizedDescription)"
                )
                return false
            }
        }

        private func reportRenderFailure(_ message: String) {
            guard lastRenderFailure != message else { return }
            lastRenderFailure = message
            callbacks.onRenderFailure(message)
        }

        fileprivate var terminalContentRect: CGRect {
            bounds.insetBy(
                dx: TerminalSurfaceDefaults.contentPadding,
                dy: TerminalSurfaceDefaults.contentPadding
            )
        }

        fileprivate func terminalContentPoint(from point: CGPoint) -> CGPoint {
            let contentRect = terminalContentRect
            return CGPoint(
                x: point.x - contentRect.minX,
                y: point.y - contentRect.minY
            )
        }

        fileprivate func gridMetrics() -> GhosttyTerminalGridMetrics? {
            guard let renderer else { return nil }
            return GhosttyTerminalGridMetrics(
                cols: max(1, renderer.surfaceState.cols),
                rows: max(1, renderer.surfaceState.rows),
                cellWidth: renderer.pointCellSize.width,
                cellHeight: renderer.pointCellSize.height
            )
        }

        private func synchronizeHostedGeometry() {
            guard bounds.width > 1, bounds.height > 1 else { return }
            let targetFrame = terminalContentRect
            if metalView.frame != targetFrame {
                metalView.frame = targetFrame
                MetalSurfaceDiagnostics.recordHostFrameChanged(surface: "terminal")
            }
            let scale = currentScaleFactor
            if metalView.contentScaleFactor != scale {
                metalView.contentScaleFactor = scale
                MetalSurfaceDiagnostics.recordDrawableSizeChanged(surface: "terminal")
            }
            notifySurfaceSizeIfNeeded()
        }

        private func notifySurfaceSizeIfNeeded() {
            guard let renderer,
                  targetPointSize.width > 1,
                  targetPointSize.height > 1
            else { return }
            let cellSize = renderer.pointCellSize
            let scale = currentScaleFactor
            let contentPointSize = CGSize(
                width: max(1, targetPointSize.width - TerminalSurfaceDefaults.contentPadding * 2),
                height: max(1, targetPointSize.height - TerminalSurfaceDefaults.contentPadding * 2)
            )
            let surfaceSize = TerminalSurfacePixelSize(
                pixelWidth: Int(floor(max(1, contentPointSize.width * scale))),
                pixelHeight: Int(floor(max(1, contentPointSize.height * scale))),
                scale: scale,
                cellWidthPoints: cellSize.width,
                cellHeightPoints: cellSize.height
            )
            guard surfaceSize != lastSurfaceSize else { return }
            lastSurfaceSize = surfaceSize
            MetalSurfaceDiagnostics.recordViewportRequested(surface: "terminal")
            callbacks.onSurfaceSizeChange(surfaceSize)
        }

        private func applyFocusRequestIfNeeded() {
            guard focusRequestID != lastHandledFocusRequestID,
                  window != nil
            else { return }
            if becomeFirstResponder() {
                lastHandledFocusRequestID = focusRequestID
            }
        }

    }

    // MARK: - Accessibility

    extension GhosttyTerminalIOSHostView {
        fileprivate func configureAccessibility() {
            isAccessibilityElement = true
            accessibilityLabel = "Terminal"
            accessibilityTraits = [.allowsDirectInteraction]
            accessibilityHint =
                "Supports typing, hardware keyboards, the shortcut bar, scrollback scrolling, " +
                "long-press text selection with drag handles, and pinch to resize text. " +
                "Screen-reader cell navigation is not supported."
        }

        func updateAccessibilityGridValue(_ surfaceState: TerminalSurfaceState) {
            accessibilityValue = "\(surfaceState.cols) columns by \(surfaceState.rows) rows"
        }

    }

    // MARK: - Gestures

    extension GhosttyTerminalIOSHostView {
        fileprivate func configureGestures() {
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(tap)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            addGestureRecognizer(pan)
            let longPress = UILongPressGestureRecognizer(
                target: self,
                action: #selector(handleLongPress(_:))
            )
            addGestureRecognizer(longPress)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            addGestureRecognizer(pinch)
        }

        @objc private func handleTap() {
            if renderSession?.selectionRange != nil {
                callbacks.onClearSelection()
                synchronizeSelectionChrome()
            }
            callbacks.onTap()
            _ = becomeFirstResponder()
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                handleDragAnchor = grabbedHandleAnchor(at: gesture.location(in: self))
                if handleDragAnchor != nil {
                    editMenuInteraction.dismissMenu()
                } else {
                    scrollAccumulator.reset()
                    lastPanTranslationY = 0
                }
            case .changed:
                if let anchor = handleDragAnchor {
                    dragSelection(anchor: anchor, toLocation: gesture.location(in: self))
                } else {
                    panScrollback(gesture)
                }
            case .ended, .cancelled, .failed:
                if handleDragAnchor != nil {
                    callbacks.onSelectionEnd()
                    synchronizeSelectionChrome()
                    if gesture.state == .ended {
                        presentEditMenu(at: gesture.location(in: self))
                    }
                }
                handleDragAnchor = nil
                scrollAccumulator.reset()
                lastPanTranslationY = 0
            default:
                break
            }
        }

        private func panScrollback(_ gesture: UIPanGestureRecognizer) {
            guard let renderer else { return }
            MetalSurfaceDiagnostics.recordScrollEventReceived(surface: "terminal")
            let translationY = gesture.translation(in: self).y
            let deltaY = translationY - lastPanTranslationY
            lastPanTranslationY = translationY
            let lineHeight = max(renderer.pointCellSize.height, 1)
            // Finger down = view earlier scrollback, matching natural
            // scrolling (the macOS path negates scrollingDeltaY the
            // same way).
            let lines = scrollAccumulator.appendPixelDelta(-deltaY, lineHeight: lineHeight)
            guard lines != 0 else { return }
            MetalSurfaceDiagnostics.recordScrollLinesEmitted(lines, surface: "terminal")
            callbacks.onScroll(scrollEvent(lines: lines, location: gesture.location(in: self)))
        }

        private func scrollEvent(lines: Int, location: CGPoint) -> TerminalSurfaceScrollEvent {
            guard let renderer else { return TerminalSurfaceScrollEvent(lines: lines) }
            let contentRect = terminalContentRect
            let contentPoint = CGPoint(
                x: location.x - contentRect.minX,
                y: location.y - contentRect.minY
            )
            let scale = currentScaleFactor
            return TerminalSurfaceScrollEvent(
                lines: lines,
                positionX: Float(max(0, contentPoint.x * scale)),
                positionY: Float(max(0, contentPoint.y * scale)),
                screenWidthPx: UInt32(max(1, Int((contentRect.width * scale).rounded()))),
                screenHeightPx: UInt32(max(1, Int((contentRect.height * scale).rounded()))),
                cellWidthPx: UInt32(max(1, Int((renderer.pointCellSize.width * scale).rounded()))),
                cellHeightPx: UInt32(max(1, Int((renderer.pointCellSize.height * scale).rounded())))
            )
        }

    }

    // MARK: - Hardware keyboard

    extension GhosttyTerminalIOSHostView {
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key, Self.shouldHandleAtPressLevel(key) else { continue }
                if let command = TerminalIOSInputAdapter.keyCommand(
                    hidUsage: key.keyCode.rawValue,
                    characters: key.characters,
                    charactersIgnoringModifiers: key.charactersIgnoringModifiers,
                    modifierFlagsRawValue: key.modifierFlags.rawValue,
                    action: 1
                ) {
                    pressLevelHandledUsages.insert(key.keyCode.rawValue)
                    callbacks.onInput(command)
                    handled = true
                }
            }
            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                guard let key = press.key,
                      pressLevelHandledUsages.remove(key.keyCode.rawValue) != nil
                else { continue }
                if let command = TerminalIOSInputAdapter.keyCommand(
                    hidUsage: key.keyCode.rawValue,
                    characters: key.characters,
                    charactersIgnoringModifiers: key.charactersIgnoringModifiers,
                    modifierFlagsRawValue: key.modifierFlags.rawValue,
                    action: 0
                ) {
                    callbacks.onInput(command)
                    handled = true
                }
            }
            if !handled {
                super.pressesEnded(presses, with: event)
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses {
                if let key = press.key {
                    pressLevelHandledUsages.remove(key.keyCode.rawValue)
                }
            }
            super.pressesCancelled(presses, with: event)
        }

        /// Printable keys reach `insertText` through the text-input system;
        /// handling them here too would double-type. Press-level handling
        /// covers control-modified keys and the non-text cluster (escape,
        /// arrows, function and navigation keys) that never reaches
        /// UIKeyInput.
        private static func shouldHandleAtPressLevel(_ key: UIKey) -> Bool {
            if key.modifierFlags.contains(.command) {
                return false
            }
            if key.modifierFlags.contains(.control) {
                return true
            }
            return pressLevelUsages.contains(key.keyCode.rawValue)
        }

        private static let pressLevelUsages: Set<Int> = {
            var usages: Set<Int> = [41] // escape
            usages.formUnion(58...69) // F1-F12
            usages.formUnion(73...78) // insert/home/pageUp/deleteForward/end/pageDown
            usages.formUnion(79...82) // arrows
            return usages
        }()

    }

    // MARK: - Touch selection (P0-045)

    private extension GhosttyTerminalIOSHostView {
        static let handleGrabRadius: CGFloat = 24

        func configureSelectionChrome() {
            startSelectionHandle.isHidden = true
            endSelectionHandle.isHidden = true
            addSubview(startSelectionHandle)
            addSubview(endSelectionHandle)
            addInteraction(editMenuInteraction)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard selectionModeEnabled, let grid = gridMetrics() else { return }
            let cell = grid.clampedCell(for: terminalContentPoint(from: gesture.location(in: self)))
            switch gesture.state {
            case .began:
                _ = becomeFirstResponder()
                editMenuInteraction.dismissMenu()
                callbacks.onSelectWord(cell.row, cell.col)
                // No word under the finger: anchor a character-level
                // selection at the pressed cell for the drag that follows.
                longPressWordRange = renderSession?.selectionRange ?? TerminalSelectionRange(
                    start: TerminalSelectionPoint(row: cell.row, col: cell.col),
                    end: TerminalSelectionPoint(row: cell.row, col: cell.col)
                )
                synchronizeSelectionChrome()
            case .changed:
                guard let wordRange = longPressWordRange else { return }
                let anchor = TerminalIOSInputAdapter.selectionAnchor(
                    forWordRange: wordRange,
                    extendingToRow: cell.row,
                    col: cell.col
                )
                applyDraggedSelection(anchor: anchor, focusRow: cell.row, focusCol: cell.col)
            case .ended:
                longPressWordRange = nil
                callbacks.onSelectionEnd()
                synchronizeSelectionChrome()
                presentEditMenu(at: gesture.location(in: self))
            case .cancelled, .failed:
                longPressWordRange = nil
                callbacks.onSelectionEnd()
                synchronizeSelectionChrome()
            default:
                break
            }
        }

        func grabbedHandleAnchor(at location: CGPoint) -> TerminalSelectionPoint? {
            guard selectionModeEnabled,
                  let range = renderSession?.selectionRange,
                  let grid = gridMetrics()
            else { return nil }
            let carets = TerminalIOSInputAdapter.selectionCaretRects(for: range, metrics: grid)
            guard let handle = TerminalIOSInputAdapter.grabbedHandle(
                at: terminalContentPoint(from: location),
                startCaret: carets.start,
                endCaret: carets.end,
                grabRadius: Self.handleGrabRadius
            ) else { return nil }
            return TerminalIOSInputAdapter.selectionAnchor(forGrabbedHandle: handle, in: range)
        }

        func dragSelection(anchor: TerminalSelectionPoint, toLocation location: CGPoint) {
            guard let grid = gridMetrics() else { return }
            let cell = grid.clampedCell(for: terminalContentPoint(from: location))
            applyDraggedSelection(anchor: anchor, focusRow: cell.row, focusCol: cell.col)
        }

        func applyDraggedSelection(anchor: TerminalSelectionPoint, focusRow: Int, focusCol: Int) {
            callbacks.onSelectionBegin(anchor.row, anchor.col)
            callbacks.onSelectionMove(focusRow, focusCol)
            synchronizeSelectionChrome()
        }

        func synchronizeSelectionChrome() {
            guard selectionModeEnabled,
                  let range = renderSession?.selectionRange,
                  let grid = gridMetrics()
            else {
                setSelectionHandlesHidden(true)
                return
            }
            let carets = TerminalIOSInputAdapter.selectionCaretRects(for: range, metrics: grid)
            let contentRect = terminalContentRect
            startSelectionHandle.place(
                overCaretRect: carets.start.offsetBy(dx: contentRect.minX, dy: contentRect.minY)
            )
            endSelectionHandle.place(
                overCaretRect: carets.end.offsetBy(dx: contentRect.minX, dy: contentRect.minY)
            )
            setSelectionHandlesHidden(false)
        }

        func setSelectionHandlesHidden(_ hidden: Bool) {
            guard startSelectionHandle.isHidden != hidden else { return }
            startSelectionHandle.isHidden = hidden
            endSelectionHandle.isHidden = hidden
            if hidden {
                editMenuInteraction.dismissMenu()
            }
        }

        func presentEditMenu(at location: CGPoint) {
            guard callbacks.selectionTextProvider()?.isEmpty == false else { return }
            let configuration = UIEditMenuConfiguration(
                identifier: "devys.terminal.selection",
                sourcePoint: location
            )
            editMenuInteraction.presentEditMenu(with: configuration)
        }
    }

    // MARK: - Edit-menu copy

    extension GhosttyTerminalIOSHostView {
        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(UIResponderStandardEditActions.copy(_:)) {
                return callbacks.selectionTextProvider()?.isEmpty == false
            }
            return super.canPerformAction(action, withSender: sender)
        }

        /// The pasteboard text is the exact cell text from the
        /// projection (`selectionTextProvider` → runtime →
        /// `TerminalFrameProjection.text(in:)`).
        override func copy(_: Any?) {
            guard let text = callbacks.selectionTextProvider(), !text.isEmpty else { return }
            UIPasteboard.general.string = text
            callbacks.onClearSelection()
            synchronizeSelectionChrome()
        }
    }

    // MARK: - Pinch-to-resize (P0-045)

    private extension GhosttyTerminalIOSHostView {
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                pinchBaseFontSize = currentFontSize
            case .changed:
                guard let base = pinchBaseFontSize else { return }
                applyPinchedFontSize(TerminalIOSInputAdapter.pinchedFontSize(
                    base: base,
                    scale: gesture.scale
                ))
            case .ended, .cancelled, .failed:
                pinchBaseFontSize = nil
            default:
                break
            }
        }

        func applyPinchedFontSize(_ fontSize: CGFloat) {
            guard fontSize != currentFontSize else { return }
            renderSession?.preferredFontSize = fontSize
            currentFontSize = fontSize
            guard ensureRenderer(fontSize: fontSize) else { return }
            applyRenderSessionSnapshot()
            // The new cell metrics flow through the existing cell-size →
            // setSurfaceSize path; the VT engine preserves the scrollback
            // position through the resize.
            synchronizeHostedGeometry()
            synchronizeSelectionChrome()
        }
    }

    // MARK: - Selection handle chrome

    /// iOS-style selection handle: a caret bar over the selected line
    /// with a round knob above it (start) or below it (end). Pure
    /// chrome — hit-testing runs through the host's pan recognizer and
    /// the adapter's grab model.
    private final class TerminalSelectionHandleComponent: UIView {
        enum KnobPlacement {
            case aboveBar
            case belowBar
        }

        static let knobDiameter: CGFloat = 10

        private let knobPlacement: KnobPlacement
        private let barView = UIView()
        private let knobView = UIView()

        init(knobPlacement: KnobPlacement) {
            self.knobPlacement = knobPlacement
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            knobView.layer.cornerRadius = Self.knobDiameter / 2
            addSubview(barView)
            addSubview(knobView)
            applyTintColors()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            nil
        }

        /// `caretRect` is the caret bar in the host's coordinate space;
        /// the knob extends beyond the line above or below it.
        func place(overCaretRect caretRect: CGRect) {
            frame = CGRect(
                x: caretRect.midX - Self.knobDiameter / 2,
                y: knobPlacement == .aboveBar ? caretRect.minY - Self.knobDiameter : caretRect.minY,
                width: Self.knobDiameter,
                height: caretRect.height + Self.knobDiameter
            )
            let barTop = knobPlacement == .aboveBar ? Self.knobDiameter : 0
            barView.frame = CGRect(
                x: (Self.knobDiameter - caretRect.width) / 2,
                y: barTop,
                width: caretRect.width,
                height: caretRect.height
            )
            knobView.frame = CGRect(
                x: 0,
                y: knobPlacement == .aboveBar ? 0 : bounds.height - Self.knobDiameter,
                width: Self.knobDiameter,
                height: Self.knobDiameter
            )
        }

        override func tintColorDidChange() {
            super.tintColorDidChange()
            applyTintColors()
        }

        private func applyTintColors() {
            barView.backgroundColor = tintColor
            knobView.backgroundColor = tintColor
        }
    }

    // MARK: - Accessory bar

    private extension GhosttyTerminalIOSHostView {
        func makeAccessoryBar() -> UIToolbar {
            let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
            bar.autoresizingMask = [.flexibleWidth]
            bar.items = [
                accessoryItem(title: "ctrl-c", accessibilityLabel: "Interrupt, control C") {
                    $0.callbacks.onInput(TerminalIOSInputAdapter.interruptCommand())
                },
                accessoryItem(title: "esc", accessibilityLabel: "Escape") {
                    $0.callbacks.onInput(TerminalIOSInputAdapter.escapeCommand())
                },
                accessoryItem(title: "tab", accessibilityLabel: "Tab") {
                    $0.callbacks.onInput(TerminalIOSInputAdapter.tabCommand())
                },
                accessoryItem(title: "↑", accessibilityLabel: "Arrow up") {
                    $0.callbacks.onInput(TerminalIOSInputAdapter.arrowUpCommand())
                },
                accessoryItem(title: "↓", accessibilityLabel: "Arrow down") {
                    $0.callbacks.onInput(TerminalIOSInputAdapter.arrowDownCommand())
                },
                UIBarButtonItem.flexibleSpace()
            ]
            return bar
        }

        func accessoryItem(
            title: String,
            accessibilityLabel: String,
            send: @escaping (GhosttyTerminalIOSHostView) -> Void
        ) -> UIBarButtonItem {
            let item = UIBarButtonItem(
                title: title,
                primaryAction: UIAction(title: title) { [weak self] _ in
                    guard let self else { return }
                    send(self)
                }
            )
            item.accessibilityLabel = accessibilityLabel
            return item
        }
    }

    // MARK: - Software keyboard

    extension GhosttyTerminalIOSHostView: UIKeyInput, UITextInputTraits {
        var hasText: Bool { true }

        func insertText(_ text: String) {
            guard let command = TerminalIOSInputAdapter.insertTextCommand(text) else { return }
            callbacks.onInput(command)
        }

        func deleteBackward() {
            callbacks.onInput(TerminalIOSInputAdapter.deleteBackwardCommand())
        }
    }
#endif
