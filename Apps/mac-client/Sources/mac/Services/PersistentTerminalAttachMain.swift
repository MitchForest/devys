// PersistentTerminalAttachMain.swift
// Devys - Attach bridge for persistent terminal host sessions.

import Foundation
import Darwin

enum PersistentTerminalAttachMain {
    static func run(arguments: [String]) -> Never {
        do {
            let config = try parse(arguments: arguments)
            try runAttach(config: config)
        } catch {
            let message = error.localizedDescription + "\n"
            _ = message.withCString { pointer in
                Darwin.write(STDERR_FILENO, pointer, strlen(pointer))
            }
            exit(1)
        }
    }

    private struct Config {
        let socketPath: String
        let sessionID: UUID
    }

    private static func parse(arguments: [String]) throws -> Config {
        var socketPath: String?
        var sessionID: UUID?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--socket":
                index += 1
                socketPath = index < arguments.count ? arguments[index] : nil
            case "--session-id":
                index += 1
                sessionID = index < arguments.count ? UUID(uuidString: arguments[index]) : nil
            default:
                break
            }
            index += 1
        }

        guard let socketPath, let sessionID else {
            throw NSError(
                domain: "PersistentTerminalAttachMain",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing terminal attach arguments."]
            )
        }
        return Config(socketPath: socketPath, sessionID: sessionID)
    }

    private static func runAttach(config: Config) throws -> Never {
        let fd = try TerminalHostSocketIO.connect(to: config.socketPath)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)

        try sendAttachHandshake(config: config, handle: handle)

        let terminalMode = try RawTerminalMode()
        _ = terminalMode

        signal(SIGPIPE, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let socketReadQueue = DispatchQueue(label: "com.devys.terminal-attach.socket")
        let stdinReadQueue = DispatchQueue(label: "com.devys.terminal-attach.stdin")

        let socketSource = makeSocketSource(fd: fd, handle: handle, queue: socketReadQueue)
        socketSource.resume()

        let stdinSource = makeStdinSource(handle: handle, queue: stdinReadQueue)
        stdinSource.resume()

        let winchSource = makeWinchSource(handle: handle, queue: socketReadQueue)
        winchSource.resume()

        dispatchMain()
    }

    private static func sendAttachHandshake(
        config: Config,
        handle: FileHandle
    ) throws {
        let size = currentTerminalSize()
        let request = TerminalHostControlRequest.attach(
            sessionID: config.sessionID,
            cols: size.cols,
            rows: size.rows
        )
        let requestData = try JSONEncoder().encode(request)
        try TerminalHostSocketIO.writeLine(requestData, to: handle)

        let responseData = try TerminalHostSocketIO.readLine(from: handle)
        let response = try JSONDecoder().decode(TerminalHostControlResponse.self, from: responseData)
        switch response {
        case .attached:
            return
        case .failure(let message):
            throw NSError(
                domain: "PersistentTerminalAttachMain",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        default:
            throw TerminalHostSocketError.invalidResponse
        }
    }

    private static func makeSocketSource(
        fd: Int32,
        handle: FileHandle,
        queue: DispatchQueue
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            do {
                while true {
                    let (type, payload) = try TerminalHostSocketIO.readFrame(from: handle)
                    if handleSocketFrame(type: type, payload: payload) {
                        return
                    }
                }
            } catch {
                exit(0)
            }
        }
        return source
    }

    private static func handleSocketFrame(
        type: TerminalHostStreamFrameType,
        payload: Data
    ) -> Bool {
        switch type {
        case .output:
            _ = payload.withUnsafeBytes { pointer in
                Darwin.write(STDOUT_FILENO, pointer.baseAddress, payload.count)
            }
            return false
        case .close:
            exit(0)
        case .input, .resize:
            return false
        }
    }

    private static func makeStdinSource(
        handle: FileHandle,
        queue: DispatchQueue
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: queue)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(STDIN_FILENO, &buffer, buffer.count)
            guard count > 0 else {
                try? TerminalHostSocketIO.writeFrame(type: .close, payload: Data(), to: handle)
                exit(0)
            }

            let data = Data(buffer.prefix(Int(count)))
            try? TerminalHostSocketIO.writeFrame(type: .input, payload: data, to: handle)
        }
        return source
    }

    private static func makeWinchSource(
        handle: FileHandle,
        queue: DispatchQueue
    ) -> DispatchSourceSignal {
        let source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: queue)
        source.setEventHandler {
            let newSize = currentTerminalSize()
            let payload = try? JSONEncoder().encode(
                TerminalHostResizeFrame(cols: newSize.cols, rows: newSize.rows)
            )
            if let payload {
                try? TerminalHostSocketIO.writeFrame(type: .resize, payload: payload, to: handle)
            }
        }
        return source
    }

    private static func currentTerminalSize() -> (cols: Int, rows: Int) {
        let environment = ProcessInfo.processInfo.environment
        let cols = Int(environment["COLUMNS"] ?? "") ?? 120
        let rows = Int(environment["LINES"] ?? "") ?? 40
        return (cols: max(cols, 1), rows: max(rows, 1))
    }
}

private final class RawTerminalMode {
    private var original = termios()
    private let enabled: Bool

    init() throws {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            enabled = false
            return
        }

        var raw = original
        cfmakeraw(&raw)
        enabled = tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0
    }

    deinit {
        guard enabled else { return }
        var restored = original
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &restored)
    }
}
