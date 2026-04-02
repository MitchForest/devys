import Foundation
import Observation
import ServerProtocol
import TerminalCore

@MainActor
@Observable
public final class SSHTerminalSession {
    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case running
        case reconnecting
        case failed(String)
        case closed
    }

    public typealias HostKeyValidator = @MainActor @Sendable (
        SSHHostKeyValidationContext
    ) async -> SSHHostKeyValidationDecision

    public private(set) var state: State = .idle
    public private(set) var sessionID: String?
    public private(set) var terminalID: String = "shell"
    public private(set) var cols: Int
    public private(set) var rows: Int
    public private(set) var latestRenderUpdate: TerminalRenderUpdate?
    public private(set) var renderState: TerminalRenderState
    public private(set) var outputPreview = ""
    public private(set) var title = "Terminal"
    public private(set) var currentDirectory: String?
    public private(set) var bellCount = 0
    public private(set) var lastError: String?
    public private(set) var telemetry = RemoteTerminalTelemetry()
    public private(set) var lastExitStatus: Int?

    public var maxOutputPreviewCharacters: Int = 6_000

    private let scrollbackMax: Int
    private let processBridge: ProcessInputBridge
    private let client = SSHInteractiveClient()
    private var attachStartedAt: Date?
    private var attachedAt: Date?
    private var activeConnectionToken = UUID()
    private var configuration: SSHConnectionConfiguration?
    private var hostKeyValidator: HostKeyValidator?

    let model: TerminalModel

    public init(
        cols: Int = 120,
        rows: Int = 40,
        scrollbackMax: Int = 100_000
    ) {
        let normalizedCols = max(20, min(cols, 400))
        let normalizedRows = max(5, min(rows, 200))
        self.cols = normalizedCols
        self.rows = normalizedRows
        self.scrollbackMax = max(1, scrollbackMax)
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
        configuration: SSHConnectionConfiguration,
        cols: Int? = nil,
        rows: Int? = nil,
        hostKeyValidator: HostKeyValidator? = nil
    ) async throws {
        try await connectInternal(
            configuration: configuration,
            cols: cols ?? self.cols,
            rows: rows ?? self.rows,
            hostKeyValidator: hostKeyValidator,
            isReconnect: false
        )
    }

    public func reconnect() async throws {
        guard let configuration else {
            throw SSHTerminalError.notConnected
        }

        telemetry.reconnectCount += 1
        try await connectInternal(
            configuration: configuration,
            cols: cols,
            rows: rows,
            hostKeyValidator: hostKeyValidator,
            isReconnect: true
        )
    }

    public func resumeIfNeeded() async throws {
        guard state != .running else { return }
        try await reconnect()
    }

    public func suspend() {
        Task {
            await client.disconnect()
        }
        if state == .running {
            state = .reconnecting
        }
    }

    public func disconnect() {
        Task {
            await client.disconnect()
        }
        state = .closed
    }

    public func sendText(_ text: String, source: TerminalInputSource = .keyboard) async throws {
        try await sendInput(.text(text), source: source)
    }

    public func sendPasteText(_ text: String) async throws {
        try await sendInput(.paste(text: text, bracketed: bracketedPasteMode), source: .paste)
    }

    public func sendInput(_ input: TerminalInput, source: TerminalInputSource = .keyboard) async throws {
        guard let bytes = input.encode(), !bytes.isEmpty else { return }
        try await sendBytes(Data(bytes), source: source)
    }

    public func sendBytes(_ data: Data, source _: TerminalInputSource = .keyboard) async throws {
        guard !data.isEmpty else { return }
        try await client.send(data: data)
    }

    public func resize(
        cols: Int,
        rows: Int,
        source _: TerminalResizeSource = .window
    ) async throws {
        let dimensions = try Self.normalizedDimensions(cols: cols, rows: rows)
        self.cols = dimensions.cols
        self.rows = dimensions.rows

        let localUpdate = await model.resize(cols: dimensions.cols, rows: dimensions.rows)
        applyRenderUpdate(localUpdate)

        try await client.resize(cols: dimensions.cols, rows: dimensions.rows)
    }

    public func clearOutputPreview() {
        outputPreview = ""
    }
}

public extension SSHTerminalSession {
    var appCursorMode: Bool {
        latestRenderUpdate?.appCursorMode ?? false
    }

    var bracketedPasteMode: Bool {
        latestRenderUpdate?.bracketedPasteMode ?? false
    }

    var chromeState: RemoteTerminalChromeState {
        let connectionStatus: RemoteTerminalConnectionStatus
        let statusText: String

        switch state {
        case .idle:
            connectionStatus = .offline
            statusText = connectionStatus.label
        case .connecting:
            connectionStatus = .connecting
            statusText = connectionStatus.label
        case .running:
            connectionStatus = .connected
            statusText = connectionStatus.label
        case .reconnecting:
            connectionStatus = .reconnecting
            statusText = connectionStatus.label
        case .failed(let message):
            connectionStatus = .failed
            statusText = "\(connectionStatus.label): \(message)"
        case .closed:
            connectionStatus = .offline
            statusText = "Closed"
        }

        let subtitle = "session: \(sessionID ?? "none")  terminal: \(terminalID)  size: \(cols)x\(rows)"
        let canAttach: Bool
        let canReconnect: Bool
        let canSendInput = state == .running
        let canDisconnect = state != .idle && state != .closed

        switch state {
        case .idle, .closed, .failed:
            canAttach = true
        case .connecting, .running, .reconnecting:
            canAttach = false
        }

        switch state {
        case .running, .closed, .failed:
            canReconnect = true
        case .idle, .connecting, .reconnecting:
            canReconnect = false
        }

        return RemoteTerminalChromeState(
            title: title,
            subtitle: subtitle,
            connectionStatus: connectionStatus,
            statusText: statusText,
            canAttach: canAttach,
            canReconnect: canReconnect,
            canSendInput: canSendInput,
            canDisconnect: canDisconnect,
            canClearOutput: !outputPreview.isEmpty,
            lastError: lastError
        )
    }
}

public extension SSHTerminalSession {
    func scrollViewUp(_ lines: Int, allowAltScreen: Bool = true) async {
        let update = await model.scrollViewUp(lines, allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func scrollViewDown(_ lines: Int, allowAltScreen: Bool = true) async {
        let update = await model.scrollViewDown(lines, allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func scrollToTop(allowAltScreen: Bool = true) async {
        let update = await model.scrollToTop(allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func scrollToBottom(allowAltScreen: Bool = true) async {
        let update = await model.scrollToBottom(allowAltScreen: allowAltScreen)
        applyRenderUpdate(update)
    }

    func beginSelection(row: Int, col: Int) async {
        let update = await model.beginSelection(row: row, col: col)
        applyRenderUpdate(update)
    }

    func updateSelection(row: Int, col: Int) async {
        let update = await model.updateSelection(row: row, col: col)
        applyRenderUpdate(update)
    }

    func finishSelection() async {
        let update = await model.finishSelection()
        applyRenderUpdate(update)
    }

    func clearSelection() async {
        let update = await model.clearSelection()
        applyRenderUpdate(update)
    }

    func selectWord(row: Int, col: Int) async {
        guard let update = await model.selectWord(row: row, col: col) else { return }
        applyRenderUpdate(update)
    }

    func selectionText() async -> String? {
        await model.selectionText()
    }

    func screenText() async -> String {
        await model.screenText()
    }
}

private extension SSHTerminalSession {
    func connectInternal(
        configuration: SSHConnectionConfiguration,
        cols: Int,
        rows: Int,
        hostKeyValidator: HostKeyValidator?,
        isReconnect: Bool
    ) async throws {
        let dimensions = try Self.normalizedDimensions(cols: cols, rows: rows)
        self.cols = dimensions.cols
        self.rows = dimensions.rows
        self.configuration = configuration
        if hostKeyValidator != nil {
            self.hostKeyValidator = hostKeyValidator
        }
        lastError = nil
        attachStartedAt = Date()
        activeConnectionToken = UUID()
        let connectionToken = activeConnectionToken

        if isReconnect {
            state = .reconnecting
        } else {
            state = .connecting
            telemetry.firstByteLatencyMs = nil
            lastExitStatus = nil
            outputPreview = ""
            let resetUpdate = await model.reset(
                cols: dimensions.cols,
                rows: dimensions.rows,
                scrollbackMax: scrollbackMax
            )
            applyRenderUpdate(resetUpdate)
        }

        do {
            try await client.connect(
                configuration: configuration,
                cols: dimensions.cols,
                rows: dimensions.rows,
                hostKeyValidator: self.hostKeyValidator
            ) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.activeConnectionToken == connectionToken else { return }
                    await self.handle(event: event)
                }
            }

            applyConnectionSuccess(configuration: configuration, cols: dimensions.cols, rows: dimensions.rows)
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }
    }

    func applyConnectionSuccess(configuration: SSHConnectionConfiguration, cols: Int, rows: Int) {
        if let attachStartedAt {
            telemetry.lastAttachLatencyMs = Self.elapsedMilliseconds(since: attachStartedAt)
        }
        attachedAt = Date()
        telemetry.attachCount += 1
        sessionID = "\(configuration.username)@\(configuration.host):\(configuration.port)"
        terminalID = "shell"
        self.cols = cols
        self.rows = rows
        state = .running
        lastError = nil
    }

    func handle(event: SSHInteractiveClientEvent) async {
        switch event {
        case .output(let chunk):
            await processOutputChunk(chunk)
        case .stderr(let chunk):
            await processOutputChunk(chunk)
        case .exitStatus(let status):
            lastExitStatus = status
            if status != 0 {
                lastError = "Terminal exited with code \(status)"
            }
        case .disconnected:
            if state == .running || state == .reconnecting || state == .connecting {
                state = .closed
            }
        case .failure(let message):
            state = .failed(message)
            lastError = message
        }
    }

    func processOutputChunk(_ chunk: Data) async {
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

    func appendOutputPreview(_ text: String) {
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

    static func normalizedDimensions(cols: Int, rows: Int) throws -> (cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else {
            throw SSHTerminalError.invalidTerminalDimensions
        }
        return (
            cols: min(max(cols, 20), 400),
            rows: min(max(rows, 5), 200)
        )
    }

    static func elapsedMilliseconds(since start: Date) -> Int {
        Int(max(0, Date().timeIntervalSince(start) * 1000))
    }
}
