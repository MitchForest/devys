import Foundation
import Observation
import SSH

@MainActor
@Observable
public final class GhosttyRemoteTerminalController {
    public private(set) var connectionState: GhosttyRemoteTerminalConnectionState = .idle
    public private(set) var surfaceState: GhosttyTerminalSurfaceState
    public private(set) var frameProjection: GhosttyTerminalFrameProjection
    public private(set) var title = "Terminal"
    public private(set) var currentDirectory: String?
    public private(set) var bellCount = 0
    public private(set) var lastErrorDescription: String?

    private let runtime: GhosttyVTRuntime
    private let client = SSHInteractiveClient()
    private var selectionAnchor: GhosttyTerminalSelectionPoint?
    private var configuration: SSHConnectionConfiguration?
    private var preparedSession: SSHRemotePreparedShellSession?
    private var hostKeyValidator: SSHInteractiveClient.HostKeyValidator?
    private let projectionBuilder = GhosttyTerminalProjectionBuilder()

    public init(
        cols: Int = 120,
        rows: Int = 40,
        scrollbackMax: Int = 100_000
    ) {
        let normalizedCols = max(20, min(cols, 400))
        let normalizedRows = max(5, min(rows, 200))
        do {
            self.runtime = try GhosttyVTRuntime(
                cols: normalizedCols,
                rows: normalizedRows,
                scrollbackMax: scrollbackMax
            )
        } catch {
            fatalError("Failed to initialize Ghostty VT runtime: \(error)")
        }
        self.surfaceState = GhosttyTerminalSurfaceState(
            cols: normalizedCols,
            rows: normalizedRows
        )
        self.frameProjection = GhosttyTerminalFrameProjection.empty(
            cols: normalizedCols,
            rows: normalizedRows
        )
    }

    public func connect(
        configuration: SSHConnectionConfiguration,
        preparedSession: SSHRemotePreparedShellSession,
        hostKeyValidator: SSHInteractiveClient.HostKeyValidator? = nil
    ) {
        self.configuration = configuration
        self.preparedSession = preparedSession
        self.hostKeyValidator = hostKeyValidator
        lastErrorDescription = nil
        connectionState = connectionState == .closed ? .reconnecting : .connecting

        Task {
            do {
                try await client.connect(
                    configuration: configuration,
                    cols: surfaceState.cols,
                    rows: surfaceState.rows,
                    term: "xterm-256color",
                    command: preparedSession.remoteAttachCommand,
                    hostKeyValidator: hostKeyValidator
                ) { [weak self] event in
                    guard let self else { return }
                    Task {
                        await self.handle(event: event)
                    }
                }
            } catch {
                await MainActor.run {
                    self.connectionState = .failed(error.localizedDescription)
                    self.lastErrorDescription = error.localizedDescription
                }
            }
        }
    }

    public func reconnect() {
        guard let configuration, let preparedSession else { return }
        connectionState = .reconnecting
        connect(
            configuration: configuration,
            preparedSession: preparedSession,
            hostKeyValidator: hostKeyValidator
        )
    }

    public func disconnect() {
        connectionState = .closed
        Task {
            await client.disconnect()
        }
    }

    public func resize(
        cols: Int,
        rows: Int,
        cellWidthPx: Int,
        cellHeightPx: Int
    ) {
        Task {
            let update = await runtime.resize(
                cols: cols,
                rows: rows,
                cellWidthPx: cellWidthPx,
                cellHeightPx: cellHeightPx
            )
            await MainActor.run {
                apply(update: update)
            }

            do {
                try await client.resize(cols: cols, rows: rows)
            } catch {
                await MainActor.run {
                    self.lastErrorDescription = error.localizedDescription
                }
            }
        }
    }

    public func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        send(data: Data(text.utf8))
    }

    public func sendSpecialKey(_ key: GhosttyTerminalSpecialKey) {
        Task {
            let data = await runtime.specialKeyData(
                for: key,
                appCursorMode: surfaceState.appCursorMode
            )
            send(data: data)
        }
    }

    public func sendControlCharacter(_ character: Character) {
        Task {
            guard let data = await runtime.controlCharacter(for: character) else { return }
            send(data: data)
        }
    }

    public func sendAltText(_ text: String) {
        guard !text.isEmpty else { return }
        var bytes = Data([0x1B])
        bytes.append(contentsOf: text.utf8)
        send(data: bytes)
    }

    public func pasteText(_ text: String) {
        guard !text.isEmpty else { return }
        Task {
            let data = await runtime.pasteData(for: text)
            send(data: data)
        }
    }

    public func scrollViewport(lines: Int) {
        guard lines != 0 else { return }
        Task {
            let update = await runtime.scrollViewport(by: lines)
            await MainActor.run {
                apply(update: update)
            }
        }
    }

    public func beginSelection(row: Int, col: Int) {
        let point = GhosttyTerminalSelectionPoint(row: row, col: col)
        selectionAnchor = point
        applySelection(
            GhosttyTerminalSelectionRange(start: point, end: point)
        )
    }

    public func updateSelection(row: Int, col: Int) {
        guard let selectionAnchor else { return }
        applySelection(
            GhosttyTerminalSelectionRange(
                start: selectionAnchor,
                end: GhosttyTerminalSelectionPoint(row: row, col: col)
            )
        )
    }

    public func finishSelection() {}

    public func clearSelection() {
        selectionAnchor = nil
        applySelection(nil)
    }

    public func selectWord(row: Int, col: Int) {
        guard let selection = frameProjection.wordSelection(atRow: row, col: col) else { return }
        selectionAnchor = selection.start
        applySelection(selection)
    }

    public func selectionText() -> String? {
        frameProjection.text(in: surfaceState.selectionRange)
    }

    public func screenText() async -> String {
        await runtime.screenText()
    }
}

private extension GhosttyRemoteTerminalController {
    func handle(event: SSHInteractiveClientEvent) async {
        switch event {
        case .output(let data):
            let result = await runtime.write(data)
            for outboundWrite in result.outboundWrites {
                try? await client.send(data: outboundWrite)
            }
            await MainActor.run {
                apply(update: result.surfaceUpdate)
                self.title = result.title
                self.currentDirectory = result.workingDirectory
                self.bellCount += result.bellCountDelta
                self.connectionState = .connected
                self.lastErrorDescription = nil
            }
        case .stderr(let data):
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let message, !message.isEmpty else { return }
            await MainActor.run {
                self.lastErrorDescription = message
            }
        case .exitStatus(let status):
            await MainActor.run {
                self.connectionState = .closed
                self.lastErrorDescription = status == 0 ? nil : "Shell exited with status \(status)."
            }
        case .disconnected:
            await MainActor.run {
                if case .closed = self.connectionState {
                    return
                }
                self.connectionState = .closed
            }
        case .failure(let message):
            await MainActor.run {
                self.connectionState = .failed(message)
                self.lastErrorDescription = message
            }
        }
    }

    func send(data: Data) {
        guard !data.isEmpty else { return }
        Task {
            do {
                try await client.send(data: data)
            } catch {
                await MainActor.run {
                    self.connectionState = .failed(error.localizedDescription)
                    self.lastErrorDescription = error.localizedDescription
                }
            }
        }
    }

    func apply(update: GhosttyTerminalSurfaceUpdate) {
        let selectionRange = surfaceState.selectionRange
        surfaceState = update.surfaceState.withSelection(selectionRange)
        frameProjection = projectionBuilder.merge(
            current: frameProjection,
            update: update.frameProjection.withSelection(selectionRange)
        )
    }

    func applySelection(_ selectionRange: GhosttyTerminalSelectionRange?) {
        surfaceState = surfaceState.withSelection(selectionRange)
        frameProjection = projectionBuilder.applySelection(selectionRange, to: frameProjection)
    }
}
