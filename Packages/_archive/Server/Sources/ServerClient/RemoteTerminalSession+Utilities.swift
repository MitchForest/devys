import Foundation

extension RemoteTerminalSession {
    static func shouldRecoverFromCursorError(_ error: Error) -> Bool {
        guard let clientError = error as? ServerClientError else { return false }
        if case .badStatus(let statusCode) = clientError {
            return statusCode == 409
        }
        return false
    }

    static func normalizedDimensions(cols: Int, rows: Int) throws -> (cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else {
            throw RemoteTerminalSessionError.invalidTerminalDimensions
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

final class ProcessInputBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable (Data) -> Void)?

    func setHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func send(_ data: Data) {
        lock.lock()
        let callback = handler
        lock.unlock()
        callback?(data)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
