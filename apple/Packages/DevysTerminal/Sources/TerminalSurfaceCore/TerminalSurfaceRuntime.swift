public import CoreGraphics
import Foundation
public import Observation
public import TerminalCore
public import TerminalVT

public enum TerminalSurfaceDefaults {
    public static let fontSize: CGFloat = 13
    /// Point padding between the host view bounds and the cell grid.
    /// Hosts inset their Metal view by this; text-range projections
    /// offset by it so overlay coordinates line up with rendered rows.
    public static let contentPadding: CGFloat = 2
}

public struct TerminalSurfacePixelSize: Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scale: CGFloat
    public var cellWidthPoints: CGFloat
    public var cellHeightPoints: CGFloat

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        scale: CGFloat,
        cellWidthPoints: CGFloat,
        cellHeightPoints: CGFloat
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.cellWidthPoints = cellWidthPoints
        self.cellHeightPoints = cellHeightPoints
    }

    public var cellWidthPx: Int {
        max(1, Int((cellWidthPoints * scale).rounded()))
    }

    public var cellHeightPx: Int {
        max(1, Int((cellHeightPoints * scale).rounded()))
    }

    public var viewportSize: TerminalViewportSize {
        TerminalViewportSize(
            cols: max(20, pixelWidth / cellWidthPx),
            rows: max(5, pixelHeight / cellHeightPx)
        )
    }
}

struct TerminalSurfaceResizeTransaction: Equatable, Sendable {
    var size: TerminalViewportSize
    var cellWidthPx: Int
    var cellHeightPx: Int

    init(pixelSize: TerminalSurfacePixelSize) {
        self.size = pixelSize.viewportSize
        self.cellWidthPx = pixelSize.cellWidthPx
        self.cellHeightPx = pixelSize.cellHeightPx
    }
}

public struct TerminalSearchState: Equatable, Sendable {
    public var isPresented: Bool
    public var query: String
    public var matchCount: Int
    public var activeMatchIndex: Int?

    public init(
        isPresented: Bool = false,
        query: String = "",
        matchCount: Int = 0,
        activeMatchIndex: Int? = nil
    ) {
        self.isPresented = isPresented
        self.query = query
        self.matchCount = matchCount
        self.activeMatchIndex = activeMatchIndex
    }
}

struct TerminalSearchMatch: Equatable, Sendable {
    var row: Int
    var startCol: Int
    var endCol: Int

    func selectionRange(
        visibleTopRow: Int,
        visibleRowCount: Int
    ) -> TerminalSelectionRange? {
        let visibleRow = row - visibleTopRow
        guard visibleRow >= 0, visibleRow < visibleRowCount else {
            return nil
        }
        return TerminalSelectionRange(
            start: TerminalSelectionPoint(row: visibleRow, col: startCol),
            end: TerminalSelectionPoint(row: visibleRow, col: endCol)
        )
    }
}

/// One live terminal surface: owns the VT runtime, the PTY session
/// handle, resize/scroll/search coalescing, and the render session the
/// host view draws from. Constructed and retained by the composition
/// layer (P0-015 pane state); host views only receive `renderSession`
/// and forward interaction callbacks back into the runtime.
@MainActor
@Observable
public final class TerminalSurfaceRuntime {
    public internal(set) var surfaceUpdate = TerminalSurfaceUpdate(
        surfaceState: TerminalSurfaceState(cols: 80, rows: 24),
        frameProjection: .empty(cols: 80, rows: 24)
    )
    public internal(set) var focusGeneration = 0
    public internal(set) var latestSnapshot: TerminalSnapshot?
    public internal(set) var searchState = TerminalSearchState()
    public let renderSession = TerminalSurfaceRenderSession(
        surfaceState: TerminalSurfaceState(cols: 80, rows: 24),
        frameProjection: .empty(cols: 80, rows: 24)
    )

    public let terminalID: TerminalID
    let launchDescriptor: TerminalLaunchDescriptor
    var callbacks: TerminalSurfaceCallbacks
    let pty: any TerminalSurfacePTYClient
    var vt: TerminalVTRuntime?
    var handle: TerminalSessionHandle?
    var startupTask: Task<Void, Never>?
    var outputTask: Task<Void, Never>?
    var viewportTask: Task<Void, Never>?
    var metadataTask: Task<Void, Never>?
    var scrollTask: Task<Void, Never>?
    var searchTask: Task<Void, Never>?
    var pendingMetadataObservation: TerminalMetadataObservation?
    var resizeCoordinator = TerminalSurfaceResizeCoordinator()
    var pendingScrollDelta = 0
    var latestScrollEvent: TerminalSurfaceScrollEvent?
    var isTerminated = false
    var currentAppearance = TerminalAppearance.defaultDark
    var searchMatches: [TerminalSearchMatch] = []
    var searchTotalRows: Int?
    var searchGeneration = 0
    var latestSurfacePixelSize: TerminalSurfacePixelSize?

    public init(
        terminalID: TerminalID,
        launchDescriptor: TerminalLaunchDescriptor,
        callbacks: TerminalSurfaceCallbacks,
        pty: any TerminalSurfacePTYClient
    ) {
        self.terminalID = terminalID
        self.launchDescriptor = launchDescriptor
        self.callbacks = callbacks
        self.pty = pty
    }

    isolated deinit {
        startupTask?.cancel()
        outputTask?.cancel()
        viewportTask?.cancel()
        metadataTask?.cancel()
        scrollTask?.cancel()
        searchTask?.cancel()
    }
}
