// Shared fixtures for the TerminalSurfaceCore suites: an in-memory PTY
// seam double, a callback recorder, and frame-projection builders.
// Cross-suite timing helpers live in TerminalTestSupport.swift.

import Foundation
import TerminalCore
@testable import TerminalSurfaceCore
import TerminalVT

actor TerminalSurfaceTestPTYClient: TerminalSurfacePTYClient {
    private enum TestError: Error {
        case requestedFailure
    }

    private var createCalls = 0
    private var resizeCalls: [TerminalViewportSize] = []
    private var terminatedHandles: [TerminalSessionHandle] = []
    private var sent: [Data] = []
    private var continuation: AsyncStream<TerminalPTYEvent>.Continuation?
    private var failCreate: Bool
    private var remainingResizeFailures: Int
    private let handle = TerminalSessionHandle(id: UUID())

    init(
        failCreate: Bool = false,
        failResizeCount: Int = 0
    ) {
        self.failCreate = failCreate
        self.remainingResizeFailures = failResizeCount
    }

    func create(
        descriptor _: TerminalLaunchDescriptor,
        size _: TerminalViewportSize
    ) async throws -> TerminalSessionHandle {
        createCalls += 1
        if failCreate {
            throw TestError.requestedFailure
        }
        return handle
    }

    func attach(_: TerminalSessionHandle) async throws -> AsyncStream<TerminalPTYEvent> {
        AsyncStream { continuation in
            Task {
                self.storeContinuation(continuation)
            }
        }
    }

    func resize(_: TerminalSessionHandle, size: TerminalViewportSize) async throws {
        resizeCalls.append(size)
        if remainingResizeFailures > 0 {
            remainingResizeFailures -= 1
            throw TestError.requestedFailure
        }
    }

    func send(_ data: Data, to _: TerminalSessionHandle) async throws {
        sent.append(data)
    }

    func currentWorkingDirectory(_: TerminalSessionHandle) async -> URL? {
        nil
    }

    func processSnapshot(_: TerminalSessionHandle) async -> TerminalProcessSnapshot {
        TerminalProcessSnapshot()
    }

    func terminate(_ handle: TerminalSessionHandle) async {
        terminatedHandles.append(handle)
    }

    func testHandle() -> TerminalSessionHandle {
        handle
    }

    func storeContinuation(_ continuation: AsyncStream<TerminalPTYEvent>.Continuation) {
        self.continuation = continuation
    }

    func yield(_ event: TerminalPTYEvent) {
        continuation?.yield(event)
    }

    func sentData() -> [Data] {
        sent
    }

    func createCount() -> Int {
        createCalls
    }

    func resizeSizes() -> [TerminalViewportSize] {
        resizeCalls
    }

    func terminateCount() -> Int {
        terminatedHandles.count
    }
}

@MainActor
final class TerminalSurfaceCallbackRecorder {
    private(set) var titles: [String] = []
    private(set) var currentDirectories: [String?] = []
    private(set) var snapshots: [TerminalSnapshot] = []
    private(set) var statuses: [TerminalStatus] = []
    private(set) var selectionChanges: [String?] = []
    private(set) var bellCount = 0
    private(set) var exits: [TerminalExit] = []

    func callbacks() -> TerminalSurfaceCallbacks {
        TerminalSurfaceCallbacks(
            titleChanged: { [weak self] title in self?.titles.append(title) },
            currentDirectoryChanged: { [weak self] directory in self?.currentDirectories.append(directory) },
            snapshotChanged: { [weak self] snapshot in self?.snapshots.append(snapshot) },
            statusChanged: { [weak self] status in self?.statuses.append(status) },
            selectionChanged: { [weak self] text in self?.selectionChanges.append(text) },
            bell: { [weak self] in self?.bellCount += 1 },
            exited: { [weak self] exit in self?.exits.append(exit) }
        )
    }
}

func terminalTestPixelSize() -> TerminalSurfacePixelSize {
    TerminalSurfacePixelSize(
        pixelWidth: 1600,
        pixelHeight: 800,
        scale: 2,
        cellWidthPoints: 8,
        cellHeightPoints: 20
    )
}

func makeTerminalProjection(strings: [String]) -> TerminalFrameProjection {
    let rows = strings.enumerated().map { rowIndex, string in
        TerminalProjectedRow(
            index: rowIndex,
            cells: Array(string.enumerated()).map { column, character in
                makeTerminalCell(column: column, grapheme: String(character))
            },
            isDirty: true
        )
    }
    let cols = strings.map(\.count).max() ?? 1
    return makeTerminalProjection(rows: rows, cols: cols)
}

func makeTerminalProjection(
    rows: [TerminalProjectedRow],
    cols: Int
) -> TerminalFrameProjection {
    TerminalFrameProjection(
        cols: cols,
        rows: max(1, rows.count),
        defaultForegroundPacked: 0xFFFFFF,
        defaultBackgroundPacked: 0x000000,
        dirtyState: .init(kind: .full, dirtyRows: rows.map(\.index)),
        rowsByIndex: rows,
        overlay: TerminalOverlayProjection(
            selectionRange: nil,
            cursor: .init(),
            cursorVisible: true,
            cursorStyle: .block,
            viewportOffset: 0
        )
    )
}

func makeTerminalCell(
    column: Int,
    grapheme: String,
    isWide: Bool = false,
    isWideContinuation: Bool = false
) -> TerminalProjectedCell {
    TerminalProjectedCell(
        column: column,
        grapheme: grapheme,
        foregroundPacked: 0xFFFFFF,
        backgroundPacked: 0x000000,
        isWide: isWide,
        isWideContinuation: isWideContinuation
    )
}
