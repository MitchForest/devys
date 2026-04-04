// SyntaxRuntimeDiagnostics.swift
// Runtime diagnostics for syntax highlighting execution paths.

import Foundation
import OSLog

// swiftlint:disable file_length
// swiftlint:disable type_body_length
private let diagnosticsLogger = Logger(
    subsystem: "com.devys.syntax",
    category: "RuntimeDiagnostics"
)

public enum SyntaxRuntimeBudgets {
    public static let firstInteractiveFrameMs: Double = 16
    public static let firstHighlightedFrameMs: Double = 75
    public static let visibleEditUpdateMs: Double = 50
}

public struct SyntaxSurfaceDiagnosticSnapshot: Sendable, Equatable {
    public let visiblePresentationSamples: Int
    public let loadingPlaceholderFrames: Int
    public let loadingPlaceholderLines: Int
    public let actualHighlightedLines: Int
    public let staleHighlightedLines: Int
    public let loadingLines: Int
    public let prefetchHits: Int
    public let prefetchMisses: Int
    public let completedInteractiveFrames: Int
    public let completedHighlightedFrames: Int
    public let completedRevisitInteractiveFrames: Int
    public let completedRevisitHighlightedFrames: Int
    public let completedVisibleUpdates: Int
    public let scrollSamples: Int
    public let lastScrollDeltaY: Double?
    public let lastVisibleActualHighlightedLines: Int
    public let lastVisibleStaleLines: Int
    public let lastVisibleLoadingLines: Int
    public let lastPrefetchHits: Int
    public let lastPrefetchMisses: Int
    public let lastInteractiveFrameLatencyMs: Double?
    public let lastHighlightedFrameLatencyMs: Double?
    public let lastRevisitInteractiveFrameLatencyMs: Double?
    public let lastRevisitHighlightedFrameLatencyMs: Double?
    public let lastVisibleUpdateLatencyMs: Double?

    public init(
        visiblePresentationSamples: Int,
        loadingPlaceholderFrames: Int,
        loadingPlaceholderLines: Int,
        actualHighlightedLines: Int,
        staleHighlightedLines: Int,
        loadingLines: Int,
        prefetchHits: Int,
        prefetchMisses: Int,
        completedInteractiveFrames: Int,
        completedHighlightedFrames: Int,
        completedRevisitInteractiveFrames: Int,
        completedRevisitHighlightedFrames: Int,
        completedVisibleUpdates: Int,
        scrollSamples: Int,
        lastScrollDeltaY: Double?,
        lastVisibleActualHighlightedLines: Int,
        lastVisibleStaleLines: Int,
        lastVisibleLoadingLines: Int,
        lastPrefetchHits: Int,
        lastPrefetchMisses: Int,
        lastInteractiveFrameLatencyMs: Double?,
        lastHighlightedFrameLatencyMs: Double?,
        lastRevisitInteractiveFrameLatencyMs: Double?,
        lastRevisitHighlightedFrameLatencyMs: Double?,
        lastVisibleUpdateLatencyMs: Double?
    ) {
        self.visiblePresentationSamples = visiblePresentationSamples
        self.loadingPlaceholderFrames = loadingPlaceholderFrames
        self.loadingPlaceholderLines = loadingPlaceholderLines
        self.actualHighlightedLines = actualHighlightedLines
        self.staleHighlightedLines = staleHighlightedLines
        self.loadingLines = loadingLines
        self.prefetchHits = prefetchHits
        self.prefetchMisses = prefetchMisses
        self.completedInteractiveFrames = completedInteractiveFrames
        self.completedHighlightedFrames = completedHighlightedFrames
        self.completedRevisitInteractiveFrames = completedRevisitInteractiveFrames
        self.completedRevisitHighlightedFrames = completedRevisitHighlightedFrames
        self.completedVisibleUpdates = completedVisibleUpdates
        self.scrollSamples = scrollSamples
        self.lastScrollDeltaY = lastScrollDeltaY
        self.lastVisibleActualHighlightedLines = lastVisibleActualHighlightedLines
        self.lastVisibleStaleLines = lastVisibleStaleLines
        self.lastVisibleLoadingLines = lastVisibleLoadingLines
        self.lastPrefetchHits = lastPrefetchHits
        self.lastPrefetchMisses = lastPrefetchMisses
        self.lastInteractiveFrameLatencyMs = lastInteractiveFrameLatencyMs
        self.lastHighlightedFrameLatencyMs = lastHighlightedFrameLatencyMs
        self.lastRevisitInteractiveFrameLatencyMs = lastRevisitInteractiveFrameLatencyMs
        self.lastRevisitHighlightedFrameLatencyMs = lastRevisitHighlightedFrameLatencyMs
        self.lastVisibleUpdateLatencyMs = lastVisibleUpdateLatencyMs
    }

    public var prefetchHitRate: Double? {
        let total = prefetchHits + prefetchMisses
        guard total > 0 else { return nil }
        return Double(prefetchHits) / Double(total)
    }
}

public struct SyntaxRuntimeDiagnosticSnapshot: Sendable, Equatable {
    public let activeRenderPasses: Int
    public let totalSyntaxRequests: Int
    public let syntaxRequestsDuringRender: Int
    public let displayPreparationsDuringRender: Int
    public let diffProjectionOperationsDuringRender: Int
    public let assetLoadEvents: Int
    public let loadingPlaceholderFrames: Int
    public let loadingPlaceholderLines: Int
    public let visibleHighlightedLines: Int
    public let visibleStaleLines: Int
    public let visibleLoadingLines: Int
    public let visibleUnhighlightedLines: Int
    public let prefetchHits: Int
    public let prefetchMisses: Int
    public let completedInteractiveFrames: Int
    public let completedHighlightedFrames: Int
    public let completedRevisitInteractiveFrames: Int
    public let completedRevisitHighlightedFrames: Int
    public let completedVisibleEditUpdates: Int
    public let lastRenderSurface: String?
    public let lastInteractiveFrameLatencyMs: Double?
    public let lastHighlightedFrameLatencyMs: Double?
    public let lastRevisitInteractiveFrameLatencyMs: Double?
    public let lastRevisitHighlightedFrameLatencyMs: Double?
    public let lastVisibleEditLatencyMs: Double?
    public let surfaceMetrics: [String: SyntaxSurfaceDiagnosticSnapshot]

    public var prefetchHitRate: Double? {
        let total = prefetchHits + prefetchMisses
        guard total > 0 else { return nil }
        return Double(prefetchHits) / Double(total)
    }

    public var exceededFirstInteractiveFrameBudget: Bool {
        guard let lastInteractiveFrameLatencyMs else { return false }
        return lastInteractiveFrameLatencyMs > SyntaxRuntimeBudgets.firstInteractiveFrameMs
    }

    public var exceededFirstHighlightedFrameBudget: Bool {
        guard let lastHighlightedFrameLatencyMs else { return false }
        return lastHighlightedFrameLatencyMs > SyntaxRuntimeBudgets.firstHighlightedFrameMs
    }

    public var exceededVisibleEditBudget: Bool {
        guard let lastVisibleEditLatencyMs else { return false }
        return lastVisibleEditLatencyMs > SyntaxRuntimeBudgets.visibleEditUpdateMs
    }

    public init(
        activeRenderPasses: Int,
        totalSyntaxRequests: Int,
        syntaxRequestsDuringRender: Int,
        displayPreparationsDuringRender: Int,
        diffProjectionOperationsDuringRender: Int,
        assetLoadEvents: Int,
        loadingPlaceholderFrames: Int,
        loadingPlaceholderLines: Int,
        visibleHighlightedLines: Int,
        visibleStaleLines: Int,
        visibleLoadingLines: Int,
        visibleUnhighlightedLines: Int,
        prefetchHits: Int,
        prefetchMisses: Int,
        completedInteractiveFrames: Int,
        completedHighlightedFrames: Int,
        completedRevisitInteractiveFrames: Int,
        completedRevisitHighlightedFrames: Int,
        completedVisibleEditUpdates: Int,
        lastRenderSurface: String?,
        lastInteractiveFrameLatencyMs: Double?,
        lastHighlightedFrameLatencyMs: Double?,
        lastRevisitInteractiveFrameLatencyMs: Double?,
        lastRevisitHighlightedFrameLatencyMs: Double?,
        lastVisibleEditLatencyMs: Double?,
        surfaceMetrics: [String: SyntaxSurfaceDiagnosticSnapshot]
    ) {
        self.activeRenderPasses = activeRenderPasses
        self.totalSyntaxRequests = totalSyntaxRequests
        self.syntaxRequestsDuringRender = syntaxRequestsDuringRender
        self.displayPreparationsDuringRender = displayPreparationsDuringRender
        self.diffProjectionOperationsDuringRender = diffProjectionOperationsDuringRender
        self.assetLoadEvents = assetLoadEvents
        self.loadingPlaceholderFrames = loadingPlaceholderFrames
        self.loadingPlaceholderLines = loadingPlaceholderLines
        self.visibleHighlightedLines = visibleHighlightedLines
        self.visibleStaleLines = visibleStaleLines
        self.visibleLoadingLines = visibleLoadingLines
        self.visibleUnhighlightedLines = visibleUnhighlightedLines
        self.prefetchHits = prefetchHits
        self.prefetchMisses = prefetchMisses
        self.completedInteractiveFrames = completedInteractiveFrames
        self.completedHighlightedFrames = completedHighlightedFrames
        self.completedRevisitInteractiveFrames = completedRevisitInteractiveFrames
        self.completedRevisitHighlightedFrames = completedRevisitHighlightedFrames
        self.completedVisibleEditUpdates = completedVisibleEditUpdates
        self.lastRenderSurface = lastRenderSurface
        self.lastInteractiveFrameLatencyMs = lastInteractiveFrameLatencyMs
        self.lastHighlightedFrameLatencyMs = lastHighlightedFrameLatencyMs
        self.lastRevisitInteractiveFrameLatencyMs = lastRevisitInteractiveFrameLatencyMs
        self.lastRevisitHighlightedFrameLatencyMs = lastRevisitHighlightedFrameLatencyMs
        self.lastVisibleEditLatencyMs = lastVisibleEditLatencyMs
        self.surfaceMetrics = surfaceMetrics
    }
}

public enum SyntaxRuntimeDiagnostics {
    private static let state = SyntaxRuntimeDiagnosticsState()

    public static func beginRenderPass(surface: String) {
        let depth = state.beginRenderPass(surface: surface)
        #if DEBUG
        diagnosticsLogger.debug(
            "Begin render pass surface=\(surface, privacy: .public) depth=\(depth, privacy: .public)"
        )
        #endif
    }

    public static func endRenderPass(surface: String) {
        let depth = state.endRenderPass(surface: surface)
        #if DEBUG
        diagnosticsLogger.debug(
            "End render pass surface=\(surface, privacy: .public) depth=\(depth, privacy: .public)"
        )
        #endif
    }

    public static func beginTrackedOpen(surface: String, identifier: String) {
        state.beginTrackedOpen(surface: surface, identifier: identifier)
    }

    public static func beginTrackedRevisit(surface: String, identifier: String) {
        state.beginTrackedRevisit(surface: surface, identifier: identifier)
    }

    public static func markFirstInteractiveFrame(surface: String, identifier: String) {
        if let latency = state.markFirstInteractiveFrame(surface: surface, identifier: identifier) {
            if latency > SyntaxRuntimeBudgets.firstInteractiveFrameMs {
                diagnosticsLogger.error(
                    """
                    Interactive frame budget exceeded \
                    surface=\(surface, privacy: .public) \
                    id=\(identifier, privacy: .public) \
                    latency_ms=\(latency, privacy: .public) \
                    budget_ms=\(SyntaxRuntimeBudgets.firstInteractiveFrameMs, privacy: .public)
                    """
                )
            }
            #if DEBUG
            diagnosticsLogger.debug(
                """
                First interactive frame \
                surface=\(surface, privacy: .public) \
                id=\(identifier, privacy: .public) \
                latency_ms=\(latency, privacy: .public)
                """
            )
            #endif
        }
    }

    public static func markFirstHighlightedFrame(surface: String, identifier: String) {
        if let latency = state.markFirstHighlightedFrame(surface: surface, identifier: identifier) {
            if latency > SyntaxRuntimeBudgets.firstHighlightedFrameMs {
                diagnosticsLogger.error(
                    """
                    Highlighted frame budget exceeded \
                    surface=\(surface, privacy: .public) \
                    id=\(identifier, privacy: .public) \
                    latency_ms=\(latency, privacy: .public) \
                    budget_ms=\(SyntaxRuntimeBudgets.firstHighlightedFrameMs, privacy: .public)
                    """
                )
            }
            #if DEBUG
            diagnosticsLogger.debug(
                """
                First highlighted frame \
                surface=\(surface, privacy: .public) \
                id=\(identifier, privacy: .public) \
                latency_ms=\(latency, privacy: .public)
                """
            )
            #endif
        }
    }

    public static func markFirstInteractiveRevisitFrame(surface: String, identifier: String) {
        if let latency = state.markFirstInteractiveRevisitFrame(surface: surface, identifier: identifier) {
            #if DEBUG
            diagnosticsLogger.debug(
                """
                First revisit interactive frame \
                surface=\(surface, privacy: .public) \
                id=\(identifier, privacy: .public) \
                latency_ms=\(latency, privacy: .public)
                """
            )
            #endif
        }
    }

    public static func markFirstHighlightedRevisitFrame(surface: String, identifier: String) {
        if let latency = state.markFirstHighlightedRevisitFrame(surface: surface, identifier: identifier) {
            #if DEBUG
            diagnosticsLogger.debug(
                """
                First revisit highlighted frame \
                surface=\(surface, privacy: .public) \
                id=\(identifier, privacy: .public) \
                latency_ms=\(latency, privacy: .public)
                """
            )
            #endif
        }
    }

    public static func beginVisibleEdit(surface: String, identifier: String) {
        state.beginVisibleEdit(surface: surface, identifier: identifier)
    }

    public static func completeVisibleEdit(surface: String, identifier: String) {
        if let latency = state.completeVisibleEdit(surface: surface, identifier: identifier) {
            if latency > SyntaxRuntimeBudgets.visibleEditUpdateMs {
                diagnosticsLogger.error(
                    """
                    Visible edit budget exceeded \
                    surface=\(surface, privacy: .public) \
                    id=\(identifier, privacy: .public) \
                    latency_ms=\(latency, privacy: .public) \
                    budget_ms=\(SyntaxRuntimeBudgets.visibleEditUpdateMs, privacy: .public)
                    """
                )
            }
            #if DEBUG
            diagnosticsLogger.debug(
                """
                Visible edit completed \
                surface=\(surface, privacy: .public) \
                id=\(identifier, privacy: .public) \
                latency_ms=\(latency, privacy: .public)
                """
            )
            #endif
        }
    }

    public static func recordVisiblePresentation(
        surface: String,
        actualHighlightedLines: Int,
        staleLines: Int,
        loadingLines: Int
    ) {
        state.recordVisiblePresentation(
            surface: surface,
            actualHighlightedLines: actualHighlightedLines,
            staleLines: staleLines,
            loadingLines: loadingLines
        )
    }

    public static func recordLoadingPlaceholder(surface: String, lineCount: Int) {
        state.recordLoadingPlaceholder(surface: surface, lineCount: lineCount)
    }

    public static func recordPrefetchSample(surface: String, hits: Int, misses: Int) {
        state.recordPrefetchSample(surface: surface, hits: hits, misses: misses)
    }

    // swiftlint:disable function_parameter_count
    public static func recordScrollTrace(
        surface: String,
        deltaY: Double,
        actualHighlightedLines: Int,
        staleLines: Int,
        loadingLines: Int,
        prefetchHits: Int,
        prefetchMisses: Int
    ) {
        state.recordScrollTrace(
            surface: surface,
            deltaY: deltaY,
            actualHighlightedLines: actualHighlightedLines,
            staleLines: staleLines,
            loadingLines: loadingLines,
            prefetchHits: prefetchHits,
            prefetchMisses: prefetchMisses
        )
    }
    // swiftlint:enable function_parameter_count

    public static func withStrictRenderAssertionsEnabledForTesting<T>(
        _ enabled: Bool,
        perform work: () throws -> T
    ) rethrows -> T {
        let previous = state.overrideStrictRenderAssertions(enabled)
        defer { _ = state.overrideStrictRenderAssertions(previous) }
        return try work()
    }

    @discardableResult
    public static func recordSyntaxRequest(
        operation: String,
        metadata: String? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        let context = state.recordSyntaxRequest()
        guard context.isDuringRender else { return false }

        let surface = context.lastRenderSurface ?? "unknown"
        let metadataDescription = metadata ?? "-"
        diagnosticsLogger.error(
            """
            Syntax request during render operation=\(operation, privacy: .public) \
            surface=\(surface, privacy: .public) metadata=\(metadataDescription, privacy: .public) \
            file=\(String(describing: file), privacy: .public):\(line, privacy: .public)
            """
        )

        if state.strictRenderAssertionsEnabled {
            assertionFailure(
                "Syntax request during render: \(operation) surface=\(surface) metadata=\(metadataDescription)"
            )
        }

        return true
    }

    @discardableResult
    public static func recordDisplayPreparationDuringRender(
        operation: String,
        metadata: String? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        let context = state.recordDisplayPreparationDuringRender()
        guard context.isDuringRender else { return false }
        return emitRenderPathViolation(
            kind: "Display preparation",
            operation: operation,
            metadata: metadata,
            surface: context.lastRenderSurface,
            file: file,
            line: line
        )
    }

    @discardableResult
    public static func recordDiffProjectionWorkDuringRender(
        operation: String,
        metadata: String? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        let context = state.recordDiffProjectionWorkDuringRender()
        guard context.isDuringRender else { return false }
        return emitRenderPathViolation(
            kind: "Diff projection work",
            operation: operation,
            metadata: metadata,
            surface: context.lastRenderSurface,
            file: file,
            line: line
        )
    }

    @discardableResult
    private static func emitRenderPathViolation(
        kind: String,
        operation: String,
        metadata: String?,
        surface: String?,
        file: StaticString,
        line: UInt
    ) -> Bool {
        let resolvedSurface = surface ?? "unknown"
        let metadataDescription = metadata ?? "-"
        diagnosticsLogger.error(
            """
            \(kind, privacy: .public) during render \
            operation=\(operation, privacy: .public) \
            surface=\(resolvedSurface, privacy: .public) \
            metadata=\(metadataDescription, privacy: .public) \
            file=\(String(describing: file), privacy: .public):\(line, privacy: .public)
            """
        )

        if state.strictRenderAssertionsEnabled {
            assertionFailure(
                "\(kind) during render: \(operation) surface=\(resolvedSurface) metadata=\(metadataDescription)"
            )
        }

        return true
    }

    @discardableResult
    public static func measureAssetLoad<T>(
        kind: String,
        name: String,
        work: () throws -> T
    ) rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try work()
        let duration = clock.now - start
        recordAssetLoad(kind: kind, name: name, duration: duration)
        return result
    }

    public static func recordAssetLoad(kind: String, name: String, duration: Duration) {
        let milliseconds = duration.milliseconds
        state.recordAssetLoad()
        #if DEBUG
        diagnosticsLogger.debug(
            """
            Asset load \
            kind=\(kind, privacy: .public) \
            name=\(name, privacy: .public) \
            duration_ms=\(milliseconds, privacy: .public)
            """
        )
        #endif
    }

    public static func snapshot() -> SyntaxRuntimeDiagnosticSnapshot {
        state.snapshot()
    }

    public static func reset() {
        state.reset()
    }
}

private final class SyntaxRuntimeDiagnosticsState: @unchecked Sendable {
    private struct SurfaceMetrics {
        var visiblePresentationSamples = 0
        var loadingPlaceholderFrames = 0
        var loadingPlaceholderLines = 0
        var actualHighlightedLines = 0
        var staleHighlightedLines = 0
        var loadingLines = 0
        var prefetchHits = 0
        var prefetchMisses = 0
        var completedInteractiveFrames = 0
        var completedHighlightedFrames = 0
        var completedRevisitInteractiveFrames = 0
        var completedRevisitHighlightedFrames = 0
        var completedVisibleUpdates = 0
        var scrollSamples = 0
        var lastScrollDeltaY: Double?
        var lastVisibleActualHighlightedLines = 0
        var lastVisibleStaleLines = 0
        var lastVisibleLoadingLines = 0
        var lastPrefetchHits = 0
        var lastPrefetchMisses = 0
        var lastInteractiveFrameLatencyMs: Double?
        var lastHighlightedFrameLatencyMs: Double?
        var lastRevisitInteractiveFrameLatencyMs: Double?
        var lastRevisitHighlightedFrameLatencyMs: Double?
        var lastVisibleUpdateLatencyMs: Double?

        func snapshot() -> SyntaxSurfaceDiagnosticSnapshot {
            SyntaxSurfaceDiagnosticSnapshot(
                visiblePresentationSamples: visiblePresentationSamples,
                loadingPlaceholderFrames: loadingPlaceholderFrames,
                loadingPlaceholderLines: loadingPlaceholderLines,
                actualHighlightedLines: actualHighlightedLines,
                staleHighlightedLines: staleHighlightedLines,
                loadingLines: loadingLines,
                prefetchHits: prefetchHits,
                prefetchMisses: prefetchMisses,
                completedInteractiveFrames: completedInteractiveFrames,
                completedHighlightedFrames: completedHighlightedFrames,
                completedRevisitInteractiveFrames: completedRevisitInteractiveFrames,
                completedRevisitHighlightedFrames: completedRevisitHighlightedFrames,
                completedVisibleUpdates: completedVisibleUpdates,
                scrollSamples: scrollSamples,
                lastScrollDeltaY: lastScrollDeltaY,
                lastVisibleActualHighlightedLines: lastVisibleActualHighlightedLines,
                lastVisibleStaleLines: lastVisibleStaleLines,
                lastVisibleLoadingLines: lastVisibleLoadingLines,
                lastPrefetchHits: lastPrefetchHits,
                lastPrefetchMisses: lastPrefetchMisses,
                lastInteractiveFrameLatencyMs: lastInteractiveFrameLatencyMs,
                lastHighlightedFrameLatencyMs: lastHighlightedFrameLatencyMs,
                lastRevisitInteractiveFrameLatencyMs: lastRevisitInteractiveFrameLatencyMs,
                lastRevisitHighlightedFrameLatencyMs: lastRevisitHighlightedFrameLatencyMs,
                lastVisibleUpdateLatencyMs: lastVisibleUpdateLatencyMs
            )
        }
    }

    private let lock = NSLock()
    private let clock = ContinuousClock()

    private var renderPassStack: [String] = []
    private var totalSyntaxRequests = 0
    private var syntaxRequestsDuringRender = 0
    private var displayPreparationsDuringRender = 0
    private var diffProjectionOperationsDuringRender = 0
    private var assetLoadEvents = 0
    private var loadingPlaceholderFrames = 0
    private var loadingPlaceholderLines = 0
    private var visibleHighlightedLines = 0
    private var visibleStaleLines = 0
    private var visibleLoadingLines = 0
    private var visibleUnhighlightedLines = 0
    private var prefetchHits = 0
    private var prefetchMisses = 0
    private var completedInteractiveFrames = 0
    private var completedHighlightedFrames = 0
    private var completedRevisitInteractiveFrames = 0
    private var completedRevisitHighlightedFrames = 0
    private var completedVisibleEditUpdates = 0
    private var lastInteractiveFrameLatencyMs: Double?
    private var lastHighlightedFrameLatencyMs: Double?
    private var lastRevisitInteractiveFrameLatencyMs: Double?
    private var lastRevisitHighlightedFrameLatencyMs: Double?
    private var lastVisibleEditLatencyMs: Double?
    private var openStarts: [String: ContinuousClock.Instant] = [:]
    private var revisitStarts: [String: ContinuousClock.Instant] = [:]
    private var editStarts: [String: ContinuousClock.Instant] = [:]
    private var strictRenderAssertionOverride: Bool?
    private var surfaceMetrics: [String: SurfaceMetrics] = [:]

    var strictRenderAssertionsEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let override = strictRenderAssertionOverride {
            return override
        }
        return ProcessInfo.processInfo.environment["DEVYS_STRICT_RENDER_ASSERTS"] == "1"
    }

    func beginRenderPass(surface: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        renderPassStack.append(surface)
        return renderPassStack.count
    }

    func endRenderPass(surface: String) -> Int {
        lock.lock()
        defer { lock.unlock() }

        if let index = renderPassStack.lastIndex(of: surface) {
            renderPassStack.remove(at: index)
        } else if !renderPassStack.isEmpty {
            renderPassStack.removeLast()
        }

        return renderPassStack.count
    }

    func beginTrackedOpen(surface: String, identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        openStarts[trackingKey(surface: surface, identifier: identifier)] = clock.now
    }

    func beginTrackedRevisit(surface: String, identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        revisitStarts[trackingKey(surface: surface, identifier: identifier)] = clock.now
    }

    func markFirstInteractiveFrame(surface: String, identifier: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let key = trackingKey(surface: surface, identifier: identifier)
        guard let start = openStarts[key] else { return nil }
        let latency = milliseconds(since: start)
        completedInteractiveFrames += 1
        lastInteractiveFrameLatencyMs = latency
        updateSurfaceMetrics(surface) {
            $0.completedInteractiveFrames += 1
            $0.lastInteractiveFrameLatencyMs = latency
        }
        return latency
    }

    func markFirstHighlightedFrame(surface: String, identifier: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let key = trackingKey(surface: surface, identifier: identifier)
        guard let start = openStarts.removeValue(forKey: key) else { return nil }
        let latency = milliseconds(since: start)
        completedHighlightedFrames += 1
        lastHighlightedFrameLatencyMs = latency
        updateSurfaceMetrics(surface) {
            $0.completedHighlightedFrames += 1
            $0.lastHighlightedFrameLatencyMs = latency
        }
        return latency
    }

    func markFirstInteractiveRevisitFrame(surface: String, identifier: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let key = trackingKey(surface: surface, identifier: identifier)
        guard let start = revisitStarts[key] else { return nil }
        let latency = milliseconds(since: start)
        completedRevisitInteractiveFrames += 1
        lastRevisitInteractiveFrameLatencyMs = latency
        updateSurfaceMetrics(surface) {
            $0.completedRevisitInteractiveFrames += 1
            $0.lastRevisitInteractiveFrameLatencyMs = latency
        }
        return latency
    }

    func markFirstHighlightedRevisitFrame(surface: String, identifier: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let key = trackingKey(surface: surface, identifier: identifier)
        guard let start = revisitStarts.removeValue(forKey: key) else { return nil }
        let latency = milliseconds(since: start)
        completedRevisitHighlightedFrames += 1
        lastRevisitHighlightedFrameLatencyMs = latency
        updateSurfaceMetrics(surface) {
            $0.completedRevisitHighlightedFrames += 1
            $0.lastRevisitHighlightedFrameLatencyMs = latency
        }
        return latency
    }

    func beginVisibleEdit(surface: String, identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        editStarts[trackingKey(surface: surface, identifier: identifier)] = clock.now
    }

    func completeVisibleEdit(surface: String, identifier: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        let key = trackingKey(surface: surface, identifier: identifier)
        guard let start = editStarts.removeValue(forKey: key) else { return nil }
        let latency = milliseconds(since: start)
        completedVisibleEditUpdates += 1
        lastVisibleEditLatencyMs = latency
        updateSurfaceMetrics(surface) {
            $0.completedVisibleUpdates += 1
            $0.lastVisibleUpdateLatencyMs = latency
        }
        return latency
    }

    func recordVisiblePresentation(
        surface: String,
        actualHighlightedLines: Int,
        staleLines: Int,
        loadingLines: Int
    ) {
        lock.lock()
        defer { lock.unlock() }

        let normalizedActual = max(0, actualHighlightedLines)
        let normalizedStale = max(0, staleLines)
        let normalizedLoading = max(0, loadingLines)

        visibleHighlightedLines += normalizedActual
        visibleStaleLines += normalizedStale
        visibleLoadingLines += normalizedLoading
        visibleUnhighlightedLines += normalizedStale + normalizedLoading

        updateSurfaceMetrics(surface) {
            $0.visiblePresentationSamples += 1
            $0.actualHighlightedLines += normalizedActual
            $0.staleHighlightedLines += normalizedStale
            $0.loadingLines += normalizedLoading
            $0.lastVisibleActualHighlightedLines = normalizedActual
            $0.lastVisibleStaleLines = normalizedStale
            $0.lastVisibleLoadingLines = normalizedLoading
        }
    }

    func recordLoadingPlaceholder(surface: String, lineCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        let normalizedLineCount = max(0, lineCount)
        loadingPlaceholderFrames += 1
        loadingPlaceholderLines += normalizedLineCount
        updateSurfaceMetrics(surface) {
            $0.loadingPlaceholderFrames += 1
            $0.loadingPlaceholderLines += normalizedLineCount
        }
    }

    func recordPrefetchSample(surface: String, hits: Int, misses: Int) {
        lock.lock()
        defer { lock.unlock() }
        let normalizedHits = max(0, hits)
        let normalizedMisses = max(0, misses)
        prefetchHits += normalizedHits
        prefetchMisses += normalizedMisses
        updateSurfaceMetrics(surface) {
            $0.prefetchHits += normalizedHits
            $0.prefetchMisses += normalizedMisses
            $0.lastPrefetchHits = normalizedHits
            $0.lastPrefetchMisses = normalizedMisses
        }
    }

    // swiftlint:disable function_parameter_count
    func recordScrollTrace(
        surface: String,
        deltaY: Double,
        actualHighlightedLines: Int,
        staleLines: Int,
        loadingLines: Int,
        prefetchHits: Int,
        prefetchMisses: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        updateSurfaceMetrics(surface) {
            $0.scrollSamples += 1
            $0.lastScrollDeltaY = deltaY
            $0.lastVisibleActualHighlightedLines = max(0, actualHighlightedLines)
            $0.lastVisibleStaleLines = max(0, staleLines)
            $0.lastVisibleLoadingLines = max(0, loadingLines)
            $0.lastPrefetchHits = max(0, prefetchHits)
            $0.lastPrefetchMisses = max(0, prefetchMisses)
        }
    }
    // swiftlint:enable function_parameter_count

    func overrideStrictRenderAssertions(_ enabled: Bool?) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        let previous = strictRenderAssertionOverride
        strictRenderAssertionOverride = enabled
        return previous
    }

    func recordSyntaxRequest() -> (isDuringRender: Bool, lastRenderSurface: String?) {
        lock.lock()
        defer { lock.unlock() }

        totalSyntaxRequests += 1
        let isDuringRender = !renderPassStack.isEmpty
        if isDuringRender {
            syntaxRequestsDuringRender += 1
        }

        return (isDuringRender, renderPassStack.last)
    }

    func recordDisplayPreparationDuringRender() -> (isDuringRender: Bool, lastRenderSurface: String?) {
        lock.lock()
        defer { lock.unlock() }

        let isDuringRender = !renderPassStack.isEmpty
        if isDuringRender {
            displayPreparationsDuringRender += 1
        }
        return (isDuringRender, renderPassStack.last)
    }

    func recordDiffProjectionWorkDuringRender() -> (isDuringRender: Bool, lastRenderSurface: String?) {
        lock.lock()
        defer { lock.unlock() }

        let isDuringRender = !renderPassStack.isEmpty
        if isDuringRender {
            diffProjectionOperationsDuringRender += 1
        }
        return (isDuringRender, renderPassStack.last)
    }

    func recordAssetLoad() {
        lock.lock()
        defer { lock.unlock() }
        assetLoadEvents += 1
    }

    func snapshot() -> SyntaxRuntimeDiagnosticSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return SyntaxRuntimeDiagnosticSnapshot(
            activeRenderPasses: renderPassStack.count,
            totalSyntaxRequests: totalSyntaxRequests,
            syntaxRequestsDuringRender: syntaxRequestsDuringRender,
            displayPreparationsDuringRender: displayPreparationsDuringRender,
            diffProjectionOperationsDuringRender: diffProjectionOperationsDuringRender,
            assetLoadEvents: assetLoadEvents,
            loadingPlaceholderFrames: loadingPlaceholderFrames,
            loadingPlaceholderLines: loadingPlaceholderLines,
            visibleHighlightedLines: visibleHighlightedLines,
            visibleStaleLines: visibleStaleLines,
            visibleLoadingLines: visibleLoadingLines,
            visibleUnhighlightedLines: visibleUnhighlightedLines,
            prefetchHits: prefetchHits,
            prefetchMisses: prefetchMisses,
            completedInteractiveFrames: completedInteractiveFrames,
            completedHighlightedFrames: completedHighlightedFrames,
            completedRevisitInteractiveFrames: completedRevisitInteractiveFrames,
            completedRevisitHighlightedFrames: completedRevisitHighlightedFrames,
            completedVisibleEditUpdates: completedVisibleEditUpdates,
            lastRenderSurface: renderPassStack.last,
            lastInteractiveFrameLatencyMs: lastInteractiveFrameLatencyMs,
            lastHighlightedFrameLatencyMs: lastHighlightedFrameLatencyMs,
            lastRevisitInteractiveFrameLatencyMs: lastRevisitInteractiveFrameLatencyMs,
            lastRevisitHighlightedFrameLatencyMs: lastRevisitHighlightedFrameLatencyMs,
            lastVisibleEditLatencyMs: lastVisibleEditLatencyMs,
            surfaceMetrics: surfaceMetrics.mapValues { $0.snapshot() }
        )
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        renderPassStack.removeAll()
        totalSyntaxRequests = 0
        syntaxRequestsDuringRender = 0
        displayPreparationsDuringRender = 0
        diffProjectionOperationsDuringRender = 0
        assetLoadEvents = 0
        loadingPlaceholderFrames = 0
        loadingPlaceholderLines = 0
        visibleHighlightedLines = 0
        visibleStaleLines = 0
        visibleLoadingLines = 0
        visibleUnhighlightedLines = 0
        prefetchHits = 0
        prefetchMisses = 0
        completedInteractiveFrames = 0
        completedHighlightedFrames = 0
        completedRevisitInteractiveFrames = 0
        completedRevisitHighlightedFrames = 0
        completedVisibleEditUpdates = 0
        lastInteractiveFrameLatencyMs = nil
        lastHighlightedFrameLatencyMs = nil
        lastRevisitInteractiveFrameLatencyMs = nil
        lastRevisitHighlightedFrameLatencyMs = nil
        lastVisibleEditLatencyMs = nil
        openStarts.removeAll()
        revisitStarts.removeAll()
        editStarts.removeAll()
        strictRenderAssertionOverride = nil
        surfaceMetrics.removeAll()
    }

    private func trackingKey(surface: String, identifier: String) -> String {
        "\(surface)::\(identifier)"
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Double {
        (clock.now - start).milliseconds
    }

    private func updateSurfaceMetrics(
        _ surface: String,
        update: (inout SurfaceMetrics) -> Void
    ) {
        var metrics = surfaceMetrics[surface] ?? SurfaceMetrics()
        update(&metrics)
        surfaceMetrics[surface] = metrics
    }
}
// swiftlint:enable type_body_length

private extension Duration {
    var milliseconds: Double {
        let seconds = Double(components.seconds) * 1_000
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000
        return seconds + attoseconds
    }
}
