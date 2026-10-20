public import CoreGraphics
public import MetalKit

/// Turns precise/line scroll deltas into whole terminal lines while
/// preserving fractional remainders between events.
public struct TerminalScrollAccumulator: Sendable {
    private var pendingPixelDelta: CGFloat = 0

    public init() {}

    public mutating func appendPixelDelta(
        _ pixelDelta: CGFloat,
        lineHeight: CGFloat
    ) -> Int {
        let lineHeight = max(1, lineHeight)
        pendingPixelDelta += pixelDelta
        let lines = Int((pendingPixelDelta / lineHeight).rounded(.towardZero))
        guard lines != 0 else { return 0 }
        pendingPixelDelta -= CGFloat(lines) * lineHeight
        return lines
    }

    public mutating func reset() {
        pendingPixelDelta = 0
    }
}

@MainActor
public enum TerminalSurfaceTiming {
    public static let viewportResizeCoalescingNanoseconds: UInt64 = 8_000_000
    public static let renderInvalidationCoalescingNanoseconds: UInt64 = 8_000_000
    public static let scrollProcessingCoalescingNanoseconds: UInt64 = 8_000_000
    public static let drawRetryNanoseconds: UInt64 = 8_000_000
}

/// Coalesces draw requests for an on-demand-driven MTKView. Hosts that
/// run the view on a display link (the iOS default) skip this and let
/// the link pace frames.
@MainActor
public final class MetalDrawScheduler {
    private let surface: String
    private weak var view: MTKView?
    private var scheduledDrawTask: Task<Void, Never>?
    private var isVisible = true

    public init(surface: String = "metal") {
        self.surface = surface
    }

    deinit {
        scheduledDrawTask?.cancel()
    }

    public func attach(_ view: MTKView) {
        self.view = view
    }

    public func setVisible(_ isVisible: Bool) {
        guard self.isVisible != isVisible else { return }
        self.isVisible = isVisible
        if isVisible {
            requestImmediateDraw()
        } else {
            scheduledDrawTask?.cancel()
            scheduledDrawTask = nil
            MetalSurfaceDiagnostics.recordDrawSkipped(surface: surface)
        }
    }

    public func requestDraw() {
        MetalSurfaceDiagnostics.recordDrawRequested(surface: surface)
        guard isVisible else {
            MetalSurfaceDiagnostics.recordDrawSkipped(surface: surface)
            return
        }

        guard scheduledDrawTask == nil else { return }
        MetalSurfaceDiagnostics.recordDrawCoalesced(surface: surface)
        scheduledDrawTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: TerminalSurfaceTiming.drawRetryNanoseconds)
            } catch {
                return
            }
            self.scheduledDrawTask = nil
            self.drawIfPossible()
        }
    }

    public func requestImmediateDraw() {
        MetalSurfaceDiagnostics.recordDrawRequested(surface: surface)
        scheduledDrawTask?.cancel()
        scheduledDrawTask = nil
        drawIfPossible()
    }

    public func requestRetry(afterNanoseconds delay: UInt64 = TerminalSurfaceTiming.drawRetryNanoseconds) {
        guard isVisible else {
            MetalSurfaceDiagnostics.recordDrawSkipped(surface: surface)
            return
        }
        guard scheduledDrawTask == nil else { return }
        scheduledDrawTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard let self else { return }
            self.scheduledDrawTask = nil
            self.drawIfPossible()
        }
    }

    private func drawIfPossible() {
        guard isVisible else {
            MetalSurfaceDiagnostics.recordDrawSkipped(surface: surface)
            return
        }
        guard let view, view.window != nil, !view.bounds.isEmpty else {
            MetalSurfaceDiagnostics.recordDrawSkipped(surface: surface)
            return
        }
        MetalSurfaceDiagnostics.recordDrawImmediate(surface: surface)
        view.draw()
    }
}

public struct MetalSurfaceDiagnosticsSnapshot: Equatable, Sendable {
    public var hostCreated = 0
    public var hostDeinitialized = 0
    public var drawSkipped = 0
    public var drawRequested = 0
    public var drawCommitted = 0
    public var drawableUnavailable = 0
    public var immediateDraws = 0
    public var hostFrameChanges = 0
    public var drawableSizeChanges = 0
    public var viewportRequests = 0
    public var viewportApplications = 0
    public var resizeIncrementsApplied = 0
    public var renderInvalidationsRequested = 0
    public var renderInvalidationsApplied = 0
    public var renderSnapshotsApplied = 0
    public var coalescedDraws = 0
    public var scrollEventsReceived = 0
    public var scrollLinesEmitted = 0
    public var scrollTasksStarted = 0
    public var scrollApplications = 0
    public var scrollDeltasApplied = 0
    public var scrollRoutedToViewport = 0
    public var scrollRoutedToPTY = 0

    public init() {}
}

@MainActor
public enum MetalSurfaceDiagnostics {
    private static var snapshotStorage = MetalSurfaceDiagnosticsSnapshot()

    public static var snapshot: MetalSurfaceDiagnosticsSnapshot {
        snapshotStorage
    }

    public static func reset() {
        snapshotStorage = MetalSurfaceDiagnosticsSnapshot()
    }

    public static func recordHostCreated(surface _: String) {
        snapshotStorage.hostCreated += 1
    }

    public static func recordHostDeinitialized(surface _: String) {
        snapshotStorage.hostDeinitialized += 1
    }

    public static func recordDrawSkipped(surface _: String) {
        snapshotStorage.drawSkipped += 1
    }

    public static func recordDrawRequested(surface _: String) {
        snapshotStorage.drawRequested += 1
    }

    public static func recordDrawCoalesced(surface _: String) {
        snapshotStorage.coalescedDraws += 1
    }

    public static func recordDrawCommitted(surface _: String) {
        snapshotStorage.drawCommitted += 1
    }

    public static func recordDrawableUnavailable(surface _: String) {
        snapshotStorage.drawableUnavailable += 1
    }

    public static func recordDrawImmediate(surface _: String) {
        snapshotStorage.immediateDraws += 1
    }

    public static func recordHostFrameChanged(surface _: String) {
        snapshotStorage.hostFrameChanges += 1
    }

    public static func recordDrawableSizeChanged(surface _: String) {
        snapshotStorage.drawableSizeChanges += 1
    }

    public static func recordViewportRequested(surface _: String) {
        snapshotStorage.viewportRequests += 1
    }

    public static func recordViewportApplied(surface _: String) {
        snapshotStorage.viewportApplications += 1
    }

    public static func recordResizeIncrementsApplied(surface _: String) {
        snapshotStorage.resizeIncrementsApplied += 1
    }

    public static func recordRenderInvalidationRequested(surface _: String) {
        snapshotStorage.renderInvalidationsRequested += 1
    }

    public static func recordRenderInvalidationApplied(surface _: String) {
        snapshotStorage.renderInvalidationsApplied += 1
    }

    public static func recordRenderSnapshotApplied(surface _: String) {
        snapshotStorage.renderSnapshotsApplied += 1
    }

    public static func recordScrollEventReceived(surface _: String) {
        snapshotStorage.scrollEventsReceived += 1
    }

    public static func recordScrollLinesEmitted(_ lines: Int, surface _: String) {
        snapshotStorage.scrollLinesEmitted += abs(lines)
    }

    public static func recordScrollTaskStarted(surface _: String) {
        snapshotStorage.scrollTasksStarted += 1
    }

    public static func recordScrollApplication(_ delta: Int, surface _: String) {
        snapshotStorage.scrollApplications += 1
        snapshotStorage.scrollDeltasApplied += abs(delta)
    }

    public static func recordScrollRoutedToViewport(surface _: String) {
        snapshotStorage.scrollRoutedToViewport += 1
    }

    public static func recordScrollRoutedToPTY(surface _: String) {
        snapshotStorage.scrollRoutedToPTY += 1
    }
}
