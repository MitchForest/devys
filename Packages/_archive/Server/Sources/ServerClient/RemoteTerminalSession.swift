import Foundation
import Observation
import ServerProtocol
import TerminalCore

@MainActor
@Observable
public final class RemoteTerminalSession {
    public enum State: Sendable, Equatable {
        case idle
        case attaching
        case running
        case reconnecting
        case failed(String)
        case closed
    }

    public private(set) var state: State = .idle
    public private(set) var sessionID: String?
    public private(set) var terminalID: String = "main"
    public private(set) var cols: Int
    public private(set) var rows: Int
    public private(set) var cursor: UInt64 = 0
    public private(set) var descriptor: TerminalDescriptor?
    public private(set) var latestRenderUpdate: TerminalRenderUpdate?
    public private(set) var renderState: TerminalRenderState
    public private(set) var outputPreview = ""
    public private(set) var recentEvents: [StreamEventEnvelope] = []
    public private(set) var title = "Terminal"
    public private(set) var currentDirectory: String?
    public private(set) var bellCount = 0
    public private(set) var lastError: String?
    public private(set) var telemetry = RemoteTerminalTelemetry()

    public var maxOutputPreviewCharacters: Int = 6_000
    public var maxRecentEvents: Int = 200

    private let transport: any RemoteTerminalTransport
    private let scrollbackMax: Int
    private let pollIntervalNanoseconds: UInt64
    private let processBridge: ProcessInputBridge
    let model: TerminalModel

    private var endpoint: URL?
    private var pollTask: Task<Void, Never>?
    private var attachStartedAt: Date?
    private var attachedAt: Date?

    public init(
        transport: any RemoteTerminalTransport = ServerClient(),
        cols: Int = 120,
        rows: Int = 40,
        scrollbackMax: Int = 100_000,
        pollIntervalNanoseconds: UInt64 = 120_000_000
    ) {
        let normalizedCols = max(20, min(cols, 400))
        let normalizedRows = max(5, min(rows, 200))
        self.transport = transport
        self.scrollbackMax = max(1, scrollbackMax)
        self.pollIntervalNanoseconds = max(25_000_000, pollIntervalNanoseconds)
        self.cols = normalizedCols
        self.rows = normalizedRows
        self.renderState = TerminalRenderState(cols: normalizedCols, rows: normalizedRows)
        self.processBridge = ProcessInputBridge()
        self.model = TerminalModel(
            cols: normalizedCols,
            rows: normalizedRows,
            scrollbackMax: self.scrollbackMax
        ) { [bridge = processBridge] data in
            bridge.send(data)
        }

        processBridge.setHandler { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await self.sendBytes(data, source: .programmatic)
            }
        }
    }

    public func connect(
        baseURL: URL,
        workspacePath: String? = nil,
        sessionID: String? = nil,
        terminalID: String = "main",
        cols: Int? = nil,
        rows: Int? = nil
    ) async throws {
        let dimensions = try Self.normalizedDimensions(cols: cols ?? self.cols, rows: rows ?? self.rows)
        self.cols = dimensions.cols
        self.rows = dimensions.rows
        self.terminalID = terminalID
        self.endpoint = baseURL
        self.lastError = nil
        self.attachStartedAt = Date()
        stopPollingLoop()

        state = .attaching
        let initialSessionID: String
        if let sessionID {
            initialSessionID = sessionID
        } else {
            let created = try await transport.createSession(baseURL: baseURL, workspacePath: workspacePath)
            initialSessionID = created.session.id
        }

        let isNewIdentity = self.sessionID != initialSessionID
        if isNewIdentity {
            cursor = 0
            outputPreview = ""
            telemetry.firstByteLatencyMs = nil
        }

        let attached = try await transport.terminalAttach(
            baseURL: baseURL,
            sessionID: initialSessionID,
            cols: dimensions.cols,
            rows: dimensions.rows,
            terminalID: terminalID,
            resumeCursor: cursor == 0 ? nil : cursor
        )

        if isNewIdentity || cursor == 0 {
            let update = await model.reset(
                cols: attached.terminal.cols,
                rows: attached.terminal.rows,
                scrollbackMax: scrollbackMax
            )
            applyRenderUpdate(update)
        } else {
            let update = await model.resize(cols: attached.terminal.cols, rows: attached.terminal.rows)
            applyRenderUpdate(update)
        }
        applyAttachResponse(attached)
        startPollingLoop(baseURL: baseURL, sessionID: initialSessionID)
    }

    public func reconnect() async throws {
        guard let baseURL = endpoint else {
            throw RemoteTerminalSessionError.notConnected
        }
        guard let sessionID else {
            throw RemoteTerminalSessionError.missingSessionIdentity
        }
        telemetry.reconnectCount += 1
        state = .reconnecting
        try await connect(
            baseURL: baseURL,
            workspacePath: nil,
            sessionID: sessionID,
            terminalID: terminalID,
            cols: cols,
            rows: rows
        )
    }

    public func disconnect() {
        stopPollingLoop()
        if state == .idle {
            return
        }
        state = .closed
    }

    public func restore(
        baseURL: URL,
        sessionID: String,
        terminalID: String = "main",
        cols: Int,
        rows: Int,
        cursor: UInt64 = 0
    ) throws {
        let dimensions = try Self.normalizedDimensions(cols: cols, rows: rows)
        stopPollingLoop()

        endpoint = baseURL
        self.sessionID = sessionID
        self.terminalID = terminalID
        self.cols = dimensions.cols
        self.rows = dimensions.rows
        self.cursor = cursor

        descriptor = nil
        latestRenderUpdate = nil
        renderState = TerminalRenderState(cols: dimensions.cols, rows: dimensions.rows)
        outputPreview = ""
        recentEvents = []
        title = "Terminal"
        currentDirectory = nil
        bellCount = 0
        lastError = nil
        attachedAt = nil
        attachStartedAt = nil
        telemetry.firstByteLatencyMs = nil
        state = .closed
    }

    public func suspend() {
        stopPollingLoop()
        if state == .running {
            state = .reconnecting
        }
    }

    public func resumeIfNeeded() async throws {
        guard let baseURL = endpoint else {
            throw RemoteTerminalSessionError.notConnected
        }
        guard let sessionID else {
            throw RemoteTerminalSessionError.missingSessionIdentity
        }
        guard pollTask == nil || state != .running else { return }
        state = .reconnecting
        try await connect(
            baseURL: baseURL,
            workspacePath: nil,
            sessionID: sessionID,
            terminalID: terminalID,
            cols: cols,
            rows: rows
        )
    }

    public func sendText(_ text: String, source: TerminalInputSource = .keyboard) async throws {
        try await sendInput(.text(text), source: source)
    }

    public func sendPasteText(_ text: String) async throws {
        try await sendInput(
            .paste(text: text, bracketed: bracketedPasteMode),
            source: .paste
        )
    }

    public func sendInput(_ input: TerminalInput, source: TerminalInputSource = .keyboard) async throws {
        guard let bytes = input.encode(), !bytes.isEmpty else { return }
        try await sendBytes(Data(bytes), source: source)
    }

    public func sendBytes(_ data: Data, source: TerminalInputSource = .keyboard) async throws {
        guard !data.isEmpty else { return }
        guard let baseURL = endpoint, let sessionID else {
            throw RemoteTerminalSessionError.notConnected
        }
        _ = try await transport.terminalInputBytes(
            baseURL: baseURL,
            sessionID: sessionID,
            data: data,
            source: source
        )
    }

    public func resize(
        cols: Int,
        rows: Int,
        source: TerminalResizeSource = .window
    ) async throws {
        let dimensions = try Self.normalizedDimensions(cols: cols, rows: rows)
        self.cols = dimensions.cols
        self.rows = dimensions.rows

        let localUpdate = await model.resize(cols: dimensions.cols, rows: dimensions.rows)
        applyRenderUpdate(localUpdate)

        guard let baseURL = endpoint, let sessionID else { return }
        let response = try await transport.terminalResize(
            baseURL: baseURL,
            sessionID: sessionID,
            cols: dimensions.cols,
            rows: dimensions.rows,
            source: source
        )
        descriptor = response.terminal
    }
    
    func clearOutputPreviewState() {
        outputPreview = ""
    }
}

extension RemoteTerminalSession {
    private func startPollingLoop(baseURL: URL, sessionID: String) {
        stopPollingLoop()
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.pollEvents(baseURL: baseURL, sessionID: sessionID)
        }
    }

    private func stopPollingLoop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollEvents(baseURL: URL, sessionID: String) async {
        while !Task.isCancelled {
            do {
                let response = try await transport.terminalEvents(
                    baseURL: baseURL,
                    sessionID: sessionID,
                    cursor: cursor
                )
                if response.events.isEmpty {
                    try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                    continue
                }

                for event in response.events {
                    await consume(event)
                }
                cursor = max(cursor, response.nextCursor)
            } catch {
                if Task.isCancelled { return }

                if Self.shouldRecoverFromCursorError(error) {
                    do {
                        try await recoverFromStaleCursor(baseURL: baseURL, sessionID: sessionID)
                        continue
                    } catch {
                        state = .failed("Reconnect failed: \(error.localizedDescription)")
                        lastError = "Reconnect failed: \(error.localizedDescription)"
                        return
                    }
                }

                state = .failed("Terminal stream failed: \(error.localizedDescription)")
                lastError = "Terminal stream failed: \(error.localizedDescription)"
                return
            }
        }
    }

    private func recoverFromStaleCursor(baseURL: URL, sessionID: String) async throws {
        telemetry.staleCursorRecoveryCount += 1
        attachStartedAt = Date()
        state = .reconnecting
        let attached = try await transport.terminalAttach(
            baseURL: baseURL,
            sessionID: sessionID,
            cols: cols,
            rows: rows,
            terminalID: terminalID,
            resumeCursor: nil
        )
        let update = await model.reset(
            cols: attached.terminal.cols,
            rows: attached.terminal.rows,
            scrollbackMax: scrollbackMax
        )
        outputPreview = ""
        applyRenderUpdate(update)
        applyAttachResponse(attached)
    }

    private func applyAttachResponse(_ response: TerminalAttachResponse) {
        if let attachStartedAt {
            telemetry.lastAttachLatencyMs = Self.elapsedMilliseconds(since: attachStartedAt)
        }
        attachedAt = Date()
        telemetry.attachCount += 1

        sessionID = response.session.id
        terminalID = response.terminal.terminalID
        cols = response.terminal.cols
        rows = response.terminal.rows
        descriptor = response.terminal
        cursor = max(cursor, response.nextCursor)
        state = .running
        lastError = nil
    }

    private func consume(_ event: StreamEventEnvelope) async {
        updateCursorAndRecentEvents(with: event)

        switch event.type {
        case .terminalOutput:
            await handleTerminalOutput(event)
        case .terminalOpened:
            await handleTerminalOpened(event)
        case .terminalResized:
            await handleTerminalResized(event)
        case .terminalStatus:
            handleTerminalStatus(event)
        case .terminalClosed:
            handleTerminalClosed(event)
        case .terminalExit:
            handleTerminalExit(event)
        case .welcome, .heartbeat, .info, .error:
            break
        }
    }

    private func updateCursorAndRecentEvents(with event: StreamEventEnvelope) {
        if event.seq > cursor {
            cursor = event.seq
        }

        recentEvents.append(event)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }
    }

    private func handleTerminalOutput(_ event: StreamEventEnvelope) async {
        guard let payload = event.terminalOutputPayload else { return }
        guard let chunk = Data(base64Encoded: payload.chunk) else { return }
        await processOutputChunk(chunk)
    }

    private func handleTerminalOpened(_ event: StreamEventEnvelope) async {
        guard let payload = event.terminalOpenedPayload else { return }
        terminalID = payload.terminalID
        cols = payload.cols
        rows = payload.rows
        descriptor = TerminalDescriptor(
            terminalID: payload.terminalID,
            cols: payload.cols,
            rows: payload.rows,
            status: payload.status
        )
        let update = await model.resize(cols: payload.cols, rows: payload.rows)
        applyRenderUpdate(update)
    }

    private func handleTerminalResized(_ event: StreamEventEnvelope) async {
        guard let payload = event.terminalResizedPayload else { return }
        cols = payload.cols
        rows = payload.rows
        descriptor = TerminalDescriptor(
            terminalID: payload.terminalID,
            cols: payload.cols,
            rows: payload.rows,
            status: descriptor?.status ?? .running
        )
        let update = await model.resize(cols: payload.cols, rows: payload.rows)
        applyRenderUpdate(update)
    }

    private func handleTerminalStatus(_ event: StreamEventEnvelope) {
        guard let payload = event.terminalStatusPayload else { return }
        guard let descriptor else { return }
        self.descriptor = TerminalDescriptor(
            terminalID: descriptor.terminalID,
            cols: descriptor.cols,
            rows: descriptor.rows,
            status: payload.status
        )
    }

    private func handleTerminalClosed(_ event: StreamEventEnvelope) {
        if let payload = event.terminalClosedPayload, let descriptor {
            self.descriptor = TerminalDescriptor(
                terminalID: descriptor.terminalID,
                cols: descriptor.cols,
                rows: descriptor.rows,
                status: .exited
            )
            if let exitCode = payload.exitCode, exitCode != 0 {
                lastError = "Terminal exited with code \(exitCode)"
            }
        }
        state = .closed
    }

    private func handleTerminalExit(_ event: StreamEventEnvelope) {
        if let exitCode = event.terminalExitPayload?.exitCode, exitCode != 0 {
            lastError = "Terminal exited with code \(exitCode)"
        }
    }

    private func processOutputChunk(_ chunk: Data) async {
        guard !chunk.isEmpty else { return }
        if telemetry.firstByteLatencyMs == nil, let attachedAt {
            telemetry.firstByteLatencyMs = Self.elapsedMilliseconds(since: attachedAt)
        }
        if let previewText = String(data: chunk, encoding: .utf8) {
            appendOutputPreview(previewText)
        }
        let update = await model.processOutput(chunk)
        applyRenderUpdate(update)
    }

    private func appendOutputPreview(_ text: String) {
        guard !text.isEmpty else { return }
        outputPreview.append(text)
        if outputPreview.count > maxOutputPreviewCharacters {
            outputPreview.removeFirst(outputPreview.count - maxOutputPreviewCharacters)
        }
    }

    func applyRenderUpdate(_ update: TerminalRenderUpdate) {
        latestRenderUpdate = update
        renderState.apply(update: update)
        title = update.title?.nilIfEmpty ?? title
        currentDirectory = update.currentDirectory
        bellCount = update.bellCount
    }
}
