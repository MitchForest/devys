import DevysClient
import Foundation
import TerminalCore
import TerminalSurfaceCore

/// What a terminal window shows above the grid.
struct RemoteTerminalState: Equatable, Sendable {
    var connected = false
    /// This device types; otherwise it watches until it takes control.
    var typing = false
    var exitCode: Int??
    var problem: String?
}

/// The terminal surface's PTY, as a session on the owner's Mac reached over a WebSocket. Output
/// arrives as binary frames and events as JSON text frames; keystrokes leave as binary. A
/// dropped connection reconnects from the last byte seen. Closing the window only detaches: the
/// session keeps running on the Mac until it exits or is ended.
actor RemoteTerminalPTY: TerminalSurfacePTYClient {
    private let businessID: String
    private let terminalID: String
    private let socketRequest: @Sendable (Int) async throws -> URLRequest
    private let report: @Sendable (RemoteTerminalState) -> Void
    private var task: URLSessionWebSocketTask?
    private var offset = 0
    private var client = ""
    private var state = RemoteTerminalState()
    private var ended = false
    private var size = TerminalViewportSize()

    init(
        businessID: String,
        terminalID: String,
        socketRequest: @escaping @Sendable (Int) async throws -> URLRequest,
        report: @escaping @Sendable (RemoteTerminalState) -> Void
    ) {
        self.businessID = businessID
        self.terminalID = terminalID
        self.socketRequest = socketRequest
        self.report = report
    }

    /// The session already exists on the Mac; the surface only learns its handle.
    func create(descriptor: TerminalLaunchDescriptor, size: TerminalViewportSize) async throws -> TerminalSessionHandle {
        self.size = size
        return TerminalSessionHandle(id: UUID(uuidString: terminalID) ?? UUID())
    }

    func attach(_ handle: TerminalSessionHandle) async throws -> AsyncStream<TerminalPTYEvent> {
        let (stream, continuation) = AsyncStream<TerminalPTYEvent>.makeStream()
        Task { await run(continuation) }
        return stream
    }

    private func run(_ continuation: AsyncStream<TerminalPTYEvent>.Continuation) async {
        var attempts = 0
        while !ended, !Task.isCancelled {
            do {
                let task = URLSession.shared.webSocketTask(with: try await socketRequest(offset))
                self.task = task
                task.resume()
                while !ended {
                    switch try await task.receive() {
                    case .data(let data):
                        offset += data.count
                        continuation.yield(.output(data))
                    case .string(let text):
                        attempts = 0
                        handle(event: text, continuation)
                    @unknown default:
                        break
                    }
                }
            } catch {
                update { $0.connected = false }
            }
            if ended { break }
            attempts += 1
            try? await Task.sleep(for: .milliseconds(min(10_000, 500 * (1 << min(attempts, 5)))))
        }
        continuation.finish()
    }

    private func handle(event text: String, _ continuation: AsyncStream<TerminalPTYEvent>.Continuation) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else { return }
        switch type {
        case "attached":
            client = event["client"] as? String ?? ""
            offset = event["offset"] as? Int ?? offset
            let writer = (event["session"] as? [String: Any])?["writer"] as? String
            update { $0.connected = true; $0.typing = writer == self.client; $0.problem = nil }
            Task { await sendResize() }
        case "writer":
            let writer = event["writer"] as? String
            update { $0.typing = writer == self.client }
        case "exit":
            ended = true
            let code = event["code"] as? Int
            update { $0.exitCode = .some(code); $0.typing = false }
            continuation.yield(.exited(TerminalExit(exitCode: code, signal: nil)))
            task?.cancel(with: .normalClosure, reason: nil)
        case "error":
            update { $0.problem = event["message"] as? String }
        default:
            break
        }
    }

    private func update(_ change: (inout RemoteTerminalState) -> Void) {
        change(&state)
        report(state)
    }

    func send(_ data: Data, to handle: TerminalSessionHandle) async throws {
        try await task?.send(.data(data))
    }

    func resize(_ handle: TerminalSessionHandle, size: TerminalViewportSize) async throws {
        self.size = size
        await sendResize()
    }

    private func sendResize() async {
        try? await task?.send(.string("{\"type\":\"resize\",\"cols\":\(size.cols),\"rows\":\(size.rows)}"))
    }

    /// Takes the keyboard from whichever device has it.
    func takeControl() async {
        try? await task?.send(.string("{\"type\":\"takeControl\"}"))
    }

    func currentWorkingDirectory(_ handle: TerminalSessionHandle) async -> URL? { nil }

    func processSnapshot(_ handle: TerminalSessionHandle) async -> TerminalProcessSnapshot { TerminalProcessSnapshot() }

    /// Detaches this device; the session itself stays on the Mac.
    func terminate(_ handle: TerminalSessionHandle) async {
        ended = true
        task?.cancel(with: .goingAway, reason: nil)
    }
}
