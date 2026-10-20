public import CoreGraphics
public import TerminalVT

/// Main-actor snapshot store between the surface runtime and a host
/// view's renderer: applies coalesced surface updates, selection and
/// search overlays, and notifies the installed host through
/// `invalidationHandler`.
@MainActor
public final class TerminalSurfaceRenderSession {
    public private(set) var surfaceState: TerminalSurfaceState
    public private(set) var frameProjection: TerminalFrameProjection
    public private(set) var searchRanges: [TerminalSelectionRange] = []
    public private(set) var activeSearchRange: TerminalSelectionRange?
    private let projectionBuilder = TerminalProjectionBuilder()
    private var pendingInvalidationTask: Task<Void, Never>?
    public private(set) var renderRevision: UInt64 = 0

    public var invalidationHandler: (@MainActor () -> Void)?

    /// Host-applied font-size override (pinch-to-resize on iOS). Lives
    /// on the render session so it persists for the pane session across
    /// host-view recreation, and resets with the session on relaunch.
    /// `nil` means the view-supplied font size applies.
    public var preferredFontSize: CGFloat?

    deinit {
        pendingInvalidationTask?.cancel()
    }

    public init(
        surfaceState: TerminalSurfaceState = .init(cols: 1, rows: 1),
        frameProjection: TerminalFrameProjection = .empty()
    ) {
        self.surfaceState = surfaceState
        self.frameProjection = frameProjection
    }

    public func renderInputs(
        appearance: TerminalAppearance,
        fontSize: CGFloat
    ) -> TerminalSurfaceRenderInputs {
        TerminalSurfaceRenderInputs(
            revision: renderRevision,
            surfaceState: surfaceState,
            frameProjection: frameProjection,
            searchRanges: searchRanges,
            activeSearchRange: activeSearchRange,
            appearance: appearance,
            fontSize: fontSize
        )
    }

    public var appCursorMode: Bool {
        surfaceState.appCursorMode
    }

    public var selectionRange: TerminalSelectionRange? {
        surfaceState.selectionRange
    }

    public func apply(update: TerminalSurfaceUpdate) {
        surfaceState = update.surfaceState
        frameProjection = projectionBuilder.merge(
            current: frameProjection,
            update: update.frameProjection
        )
        renderRevision &+= 1
        requestCoalescedInvalidation()
    }

    public func applySelection(_ selectionRange: TerminalSelectionRange?) {
        surfaceState = surfaceState.withSelection(selectionRange)
        frameProjection = projectionBuilder.applySelection(
            selectionRange,
            to: frameProjection
        )
        renderRevision &+= 1
        invalidateImmediately()
    }

    func applySearch(
        ranges searchRanges: [TerminalSelectionRange],
        activeRange: TerminalSelectionRange?
    ) {
        self.searchRanges = searchRanges
        activeSearchRange = activeRange
        renderRevision &+= 1
        invalidateImmediately()
    }

    public func wordSelection(
        atRow row: Int,
        col: Int
    ) -> TerminalSelectionRange? {
        frameProjection.wordSelection(atRow: row, col: col)
    }

    public func selectionText() -> String? {
        frameProjection.text(in: surfaceState.selectionRange)
    }

    private func requestCoalescedInvalidation() {
        MetalSurfaceDiagnostics.recordRenderInvalidationRequested(surface: "terminal")
        guard pendingInvalidationTask == nil else { return }
        pendingInvalidationTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: TerminalSurfaceTiming.renderInvalidationCoalescingNanoseconds)
            } catch {
                return
            }
            guard let self else { return }
            self.pendingInvalidationTask = nil
            self.invalidateImmediately()
        }
    }

    private func invalidateImmediately() {
        pendingInvalidationTask?.cancel()
        pendingInvalidationTask = nil
        MetalSurfaceDiagnostics.recordRenderInvalidationApplied(surface: "terminal")
        invalidationHandler?()
    }
}

/// One immutable frame handed from the render session to a host view's
/// renderer; the host compares `revision`/`appearance`/`fontSize` to skip
/// redundant renderer updates.
@MainActor
public struct TerminalSurfaceRenderInputs {
    public let revision: UInt64
    public let surfaceState: TerminalSurfaceState
    public let frameProjection: TerminalFrameProjection
    public let searchRanges: [TerminalSelectionRange]
    public let activeSearchRange: TerminalSelectionRange?
    public let appearance: TerminalAppearance
    public let fontSize: CGFloat
}
