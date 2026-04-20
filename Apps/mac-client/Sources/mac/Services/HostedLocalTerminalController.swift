import Foundation
import GhosttyTerminal
import GhosttyTerminalCore
import Observation

@MainActor
@Observable
final class HostedLocalTerminalController {
    private final class SocketConnection: @unchecked Sendable {
        let handle: FileHandle

        init(handle: FileHandle) {
            self.handle = handle
        }
    }

    private struct PendingFrame {
        let type: TerminalHostStreamFrameType
        let payload: Data
    }

    private let session: GhosttyTerminalSession
    private let socketPath: String
    let scrollbackMax: Int
    let projectionBuilder = GhosttyTerminalProjectionBuilder()
    var appearance: GhosttyTerminalAppearance
    var performanceObserver: TerminalOpenPerformanceObserver?
    var runtime: GhosttyVTRuntime?
    var measuredViewport: HostedTerminalViewport?
    var viewportContinuations: [CheckedContinuation<HostedTerminalViewport?, Never>] = []

    private var connection: SocketConnection?
    private var attachTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    private var pendingFrames: [PendingFrame] = []
    private var selectionAnchor: GhosttyTerminalSelectionPoint?
    private var hasAppliedStagedCommand = false
    private var hasReportedFirstOutputChunk = false
    private var hasReceivedFirstSurfaceUpdate = false
    private var hasRenderedFirstInteractiveFrame = false
    var hasReportedFirstSurfaceUpdate = false

    var surfaceState: GhosttyTerminalSurfaceState
    var frameProjection: GhosttyTerminalFrameProjection

    init(
        session: GhosttyTerminalSession,
        socketPath: String,
        appearance: GhosttyTerminalAppearance,
        performanceObserver: TerminalOpenPerformanceObserver? = nil,
        preferredViewportSize: HostedTerminalViewportSize? = nil,
        scrollbackMax: Int = 100_000
    ) {
        let normalizedCols = max(1, min(preferredViewportSize?.cols ?? 1, 400))
        let normalizedRows = max(1, min(preferredViewportSize?.rows ?? 1, 200))
        self.session = session
        self.socketPath = socketPath
        self.scrollbackMax = scrollbackMax
        self.appearance = appearance
        self.performanceObserver = performanceObserver
        self.surfaceState = GhosttyTerminalSurfaceState(cols: normalizedCols, rows: normalizedRows)
        self.frameProjection = GhosttyTerminalFrameProjection.empty(
            cols: normalizedCols,
            rows: normalizedRows
        )
    }

    deinit {
        MainActor.assumeIsolated {
            attachTask?.cancel()
            readTask?.cancel()
            cancelViewportWaiters()
            if let connection {
                try? TerminalHostSocketIO.writeFrame(type: .close, payload: Data(), to: connection.handle)
                try? connection.handle.close()
            }
        }
    }

    func attachIfNeeded() {
        guard session.startupPhase != .startingHost,
              session.startupPhase != .awaitingViewport,
              session.startupPhase != .failed else {
            return
        }
        guard connection == nil, readTask == nil, attachTask == nil else { return }
        guard let measuredViewport else { return }

        let sessionID = session.id
        let cols = measuredViewport.size.cols
        let rows = measuredViewport.size.rows
        let socketPath = self.socketPath
        let replayBudget = attachReplayBudget()
        let replayContext = attachReplayContext(for: replayBudget, viewport: measuredViewport)
        report(.attachStart, context: replayContext)
        attachTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let handle = try Self.makeAttachedHandle(
                    sessionID: sessionID,
                    socketPath: socketPath,
                    cols: cols,
                    rows: rows,
                    replayBudget: replayBudget
                )
                await self.finishAttach(with: handle, replayContext: replayContext)
            } catch {
                await self.failAttach(error)
            }
        }
    }

    func detach() {
        attachTask?.cancel()
        attachTask = nil
        readTask?.cancel()
        readTask = nil
        cancelViewportWaiters()

        if let connection {
            try? TerminalHostSocketIO.writeFrame(type: .close, payload: Data(), to: connection.handle)
            try? connection.handle.close()
        }

        connection = nil
    }

    func awaitInitialViewport() async -> HostedTerminalViewport? {
        if let measuredViewport {
            return measuredViewport
        }

        return await withCheckedContinuation { continuation in
            viewportContinuations.append(continuation)
        }
    }

    func hasMeasuredViewport() -> Bool {
        measuredViewport != nil
    }

    func updateViewport(
        cols: Int,
        rows: Int,
        cellWidthPx: Int,
        cellHeightPx: Int
    ) {
        let normalizedViewport = HostedTerminalViewport(
            cols: max(20, min(cols, 400)),
            rows: max(5, min(rows, 200)),
            cellWidthPx: max(1, cellWidthPx),
            cellHeightPx: max(1, cellHeightPx)
        )
        let previousViewport = measuredViewport
        guard previousViewport != normalizedViewport else { return }

        measuredViewport = normalizedViewport
        report(
            .viewportMeasured,
            context: viewportContext(for: normalizedViewport)
        )
        applyLocalViewportDimensions(normalizedViewport.size)
        guard initializeRuntimeIfNeeded(for: normalizedViewport) else { return }
        report(
            .viewportApplied,
            context: viewportContext(for: normalizedViewport)
        )
        resumeViewportContinuations(with: normalizedViewport)

        guard previousViewport != nil else {
            attachIfNeeded()
            return
        }

        guard let runtime else {
            attachIfNeeded()
            return
        }

        Task {
            let update = await runtime.resize(
                cols: normalizedViewport.size.cols,
                rows: normalizedViewport.size.rows,
                cellWidthPx: normalizedViewport.cellWidthPx,
                cellHeightPx: normalizedViewport.cellHeightPx
            )
            await MainActor.run {
                apply(update: update, advancesStartup: false)
                self.sendViewportResizeIfPossible(normalizedViewport.size)
            }
        }
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        attachIfNeeded()
        sendOrQueueFrame(type: .input, payload: Data(text.utf8))
    }

    func sendSpecialKey(_ key: GhosttyTerminalSpecialKey) {
        attachIfNeeded()
        guard let runtime else { return }
        Task {
            let data = await runtime.specialKeyData(
                for: key,
                appCursorMode: surfaceState.appCursorMode
            )
            self.sendOrQueueFrame(type: .input, payload: data)
        }
    }

    func sendControlCharacter(_ character: Character) {
        attachIfNeeded()
        guard let runtime else { return }
        Task {
            guard let data = await runtime.controlCharacter(for: character) else { return }
            self.sendOrQueueFrame(type: .input, payload: data)
        }
    }

    func sendAltText(_ text: String) {
        guard !text.isEmpty else { return }
        attachIfNeeded()
        var bytes = Data([0x1B])
        bytes.append(contentsOf: text.utf8)
        sendOrQueueFrame(type: .input, payload: bytes)
    }

    func pasteText(_ text: String) {
        guard !text.isEmpty else { return }
        attachIfNeeded()
        guard let runtime else { return }
        Task {
            let data = await runtime.pasteData(for: text)
            self.sendOrQueueFrame(type: .input, payload: data)
        }
    }

    func scrollViewport(lines: Int) {
        guard lines != 0 else { return }
        guard let runtime else { return }
        Task {
            let update = await runtime.scrollViewport(by: lines)
            await MainActor.run {
                apply(update: update, advancesStartup: false)
            }
        }
    }

    func beginSelection(row: Int, col: Int) {
        let point = GhosttyTerminalSelectionPoint(row: row, col: col)
        selectionAnchor = point
        applySelection(GhosttyTerminalSelectionRange(start: point, end: point))
    }

    func updateSelection(row: Int, col: Int) {
        guard let selectionAnchor else { return }
        applySelection(
            GhosttyTerminalSelectionRange(
                start: selectionAnchor,
                end: GhosttyTerminalSelectionPoint(row: row, col: col)
            )
        )
    }

    func finishSelection() {}

    func clearSelection() {
        selectionAnchor = nil
        applySelection(nil)
    }

    func selectWord(row: Int, col: Int) {
        guard let selection = frameProjection.wordSelection(atRow: row, col: col) else { return }
        selectionAnchor = selection.start
        applySelection(selection)
    }

    func selectionText() -> String? {
        frameProjection.text(in: surfaceState.selectionRange)
    }

    func screenText() async -> String {
        guard let runtime else { return "" }
        return await runtime.screenText()
    }

    func updateAppearance(_ appearance: GhosttyTerminalAppearance) {
        guard self.appearance != appearance else { return }
        self.appearance = appearance
        guard let runtime else { return }
        Task {
            let update = await runtime.updateAppearance(appearance)
            await MainActor.run {
                self.apply(update: update, advancesStartup: false)
            }
        }
    }

    func updatePerformanceObserver(_ performanceObserver: TerminalOpenPerformanceObserver?) {
        self.performanceObserver = performanceObserver
    }

    func noteFirstInteractiveFrame() {
        guard hasRenderedFirstInteractiveFrame == false else { return }

        hasRenderedFirstInteractiveFrame = true
        refreshStartupPresentationState()
        applyStagedCommandIfNeeded()
    }

    func failStartup(message: String) {
        let alreadyFailed = session.startupPhase == .failed &&
            session.lastErrorDescription == message
        if alreadyFailed { return }

        session.lastErrorDescription = message
        session.isRunning = false
        session.startupPhase = .failed
        pendingFrames.removeAll(keepingCapacity: false)
        attachTask?.cancel()
        attachTask = nil
        readTask?.cancel()
        readTask = nil
        cancelViewportWaiters()

        if let connection {
            try? TerminalHostSocketIO.writeFrame(type: .close, payload: Data(), to: connection.handle)
            try? connection.handle.close()
            self.connection = nil
        }
    }
}

private extension HostedLocalTerminalController {
    @MainActor
    func finishAttach(
        with handle: FileHandle,
        replayContext: [String: String]
    ) {
        attachTask = nil
        guard connection == nil, readTask == nil else {
            try? handle.close()
            return
        }

        let connection = SocketConnection(handle: handle)
        self.connection = connection
        report(.attachAck, context: replayContext)
        session.lastErrorDescription = nil
        session.isRunning = true
        flushPendingFrames()

        readTask = Task.detached(priority: .userInitiated) { [weak self, connection] in
            guard let self else { return }
            do {
                while !Task.isCancelled {
                    let (type, payload) = try TerminalHostSocketIO.readFrame(from: connection.handle)
                    switch type {
                    case .output:
                        await self.handleOutput(payload)
                    case .close:
                        await self.handleClose(payload)
                        return
                    case .input, .resize:
                        continue
                    }
                }
            } catch {
                await self.handleFailure(error)
            }
        }
    }

    @MainActor
    func failAttach(_ error: Error) {
        guard attachTask != nil else { return }
        attachTask = nil
        failStartup(message: error.localizedDescription)
    }

    func handleOutput(_ data: Data) async {
        if !data.isEmpty, hasReportedFirstOutputChunk == false {
            hasReportedFirstOutputChunk = true
            report(
                .firstOutputChunk,
                context: ["output_bytes": String(data.count)]
            )
        }
        guard let runtime else { return }
        let result = await runtime.write(data)
        for outboundWrite in result.outboundWrites {
            await MainActor.run {
                self.sendOrQueueFrame(type: .input, payload: outboundWrite)
            }
        }

        apply(update: result.surfaceUpdate, advancesStartup: true)
        session.tabTitle = result.title
        session.currentDirectory = result.workingDirectory.map { URL(fileURLWithPath: $0).standardizedFileURL }
        session.bellCount += result.bellCountDelta
        session.lastErrorDescription = nil
        session.isRunning = true
    }

    func handleClose(_ payload: Data) async {
        let exitFrame = try? JSONDecoder().decode(TerminalHostExitFrame.self, from: payload)
        session.isRunning = false
        session.lastErrorDescription = TerminalSessionStartupLifecycle.closeDescription(
            exitCode: exitFrame?.exitCode,
            signal: exitFrame?.signal,
            startupPhase: session.startupPhase
        )
        session.startupPhase = TerminalSessionStartupLifecycle.phaseAfterClose(
            from: session.startupPhase
        )
        detach()
    }

    func handleFailure(_ error: Error) async {
        guard Task.isCancelled == false else { return }
        if session.startupPhase != .ready {
            failStartup(message: error.localizedDescription)
            return
        }
        session.lastErrorDescription = error.localizedDescription
        session.isRunning = false
        detach()
    }

    func writeFrame(
        type: TerminalHostStreamFrameType,
        payload: Data
    ) throws {
        guard let connection else { return }
        try TerminalHostSocketIO.writeFrame(type: type, payload: payload, to: connection.handle)
    }

    func sendOrQueueFrame(
        type: TerminalHostStreamFrameType,
        payload: Data
    ) {
        if connection == nil {
            pendingFrames.append(PendingFrame(type: type, payload: payload))
            attachIfNeeded()
            return
        }

        do {
            try writeFrame(type: type, payload: payload)
        } catch {
            pendingFrames.append(PendingFrame(type: type, payload: payload))
            session.lastErrorDescription = error.localizedDescription
            session.isRunning = false
            detach()
            attachIfNeeded()
        }
    }

    func flushPendingFrames() {
        guard !pendingFrames.isEmpty else { return }
        let frames = pendingFrames
        pendingFrames.removeAll(keepingCapacity: true)
        for (index, frame) in frames.enumerated() {
            do {
                try writeFrame(type: frame.type, payload: frame.payload)
            } catch {
                pendingFrames.insert(contentsOf: frames[index...], at: 0)
                session.lastErrorDescription = error.localizedDescription
                session.isRunning = false
                detach()
                attachIfNeeded()
                return
            }
        }
    }

    func applyStagedCommandIfNeeded() {
        guard hasAppliedStagedCommand == false,
              hasReceivedFirstSurfaceUpdate,
              hasRenderedFirstInteractiveFrame,
              let stagedCommand = session.stagedCommand,
              stagedCommand.isEmpty == false
        else {
            return
        }

        hasAppliedStagedCommand = true
        session.stagedCommand = nil
        pasteText(stagedCommand)
    }

    func apply(update: GhosttyTerminalSurfaceUpdate, advancesStartup: Bool) {
        if advancesStartup, hasReportedFirstSurfaceUpdate == false {
            hasReportedFirstSurfaceUpdate = true
            hasReceivedFirstSurfaceUpdate = true
            report(
                .firstSurfaceUpdate,
                context: [
                    "dirty_kind": dirtyKindName(update.frameProjection.dirtyState.kind),
                    "projected_rows": String(update.frameProjection.rowsByIndex.count)
                ]
            )
        }
        if advancesStartup {
            session.startupPhase = TerminalSessionStartupLifecycle.phaseAfterFirstSurfaceUpdate(
                from: session.startupPhase
            )
        }
        let selectionRange = surfaceState.selectionRange
        surfaceState = update.surfaceState.withSelection(selectionRange)
        frameProjection = projectionBuilder.merge(
            current: frameProjection,
            update: update.frameProjection.withSelection(selectionRange)
        )
        refreshStartupPresentationState()
        applyStagedCommandIfNeeded()
    }

    func sendViewportResizeIfPossible(_ size: HostedTerminalViewportSize) {
        let payload = terminalHostResizePayload(for: size)
        if let payload {
            sendOrQueueFrame(type: .resize, payload: payload)
        }
    }

    func refreshStartupPresentationState() {
        session.startupPhase = TerminalSessionStartupLifecycle.phaseAfterFirstRenderableFrame(
            from: session.startupPhase,
            hasSurfaceUpdate: hasReceivedFirstSurfaceUpdate,
            hasInteractiveFrame: hasRenderedFirstInteractiveFrame,
            hasOutputChunk: hasReportedFirstOutputChunk
        )
    }
}
