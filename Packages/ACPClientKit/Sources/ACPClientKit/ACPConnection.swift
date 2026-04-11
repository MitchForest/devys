// periphery:ignore:all - JSON-RPC envelope types are consumed through Codable and async stream integration
@preconcurrency import Foundation

public struct ACPProcessTermination: Sendable, Equatable {
    public enum Reason: String, Sendable {
        case exit
        case uncaughtSignal
        case eof
    }

    public var reason: Reason
    public var exitCode: Int32?

    public init(reason: Reason, exitCode: Int32? = nil) {
        self.reason = reason
        self.exitCode = exitCode
    }
}

public enum ACPTransportError: Error, Sendable, Equatable {
    case invalidMessageFraming
    case invalidMessage(String)
    case processSpawnFailed(String)
    case processTerminated(ACPProcessTermination)
    case connectionClosed
}

public enum ACPConnectionEvent: Sendable, Equatable {
    case notification(ACPNotification)
    case request(ACPIncomingRequest)
    case stderr(String)
    case terminated(ACPProcessTermination)
}

public enum ACPTransportEvent: Sendable, Equatable {
    case message(Data)
    case stderr(String)
    case terminated(ACPProcessTermination)
}

private struct ACPJSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: ACPRequestID
    let method: String
    let params: Params?
}

private struct ACPJSONRPCNotification<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params?
}

private struct ACPJSONRPCResult<Payload: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: ACPRequestID
    let result: Payload?
}

private struct ACPJSONRPCError: Encodable {
    let jsonrpc = "2.0"
    let id: ACPRequestID
    let error: ACPRemoteError
}

private struct ACPInboundEnvelope: Decodable {
    let jsonrpc: String
    let id: ACPRequestID?
    let method: String?
    let params: ACPValue?
    let result: ACPValue?
    let error: ACPRemoteError?
}

private final class ACPLineAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(chunk)
        var lines: [Data] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newlineIndex)
            lines.append(Data(line))
            buffer.removeSubrange(...newlineIndex)
        }
        return lines
    }

    func finish() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        guard !buffer.isEmpty else { return nil }
        let remainder = buffer
        buffer.removeAll(keepingCapacity: false)
        return remainder
    }
}

private func makeAsyncStream<Element>() -> (AsyncStream<Element>, AsyncStream<Element>.Continuation) {
    var capturedContinuation: AsyncStream<Element>.Continuation?
    let stream = AsyncStream<Element> { continuation in
        capturedContinuation = continuation
    }

    guard let continuation = capturedContinuation else {
        preconditionFailure("Failed to create async stream continuation.")
    }

    return (stream, continuation)
}

public final class ACPTransportStdio: @unchecked Sendable {
    public nonisolated let events: AsyncStream<ACPTransportEvent>

    private let eventsContinuation: AsyncStream<ACPTransportEvent>.Continuation
    private let process: Process
    private let stdinHandle: FileHandle
    private let stateLock = NSLock()
    private var hasFinished = false

    public static func launch(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectoryURL: URL? = nil
    ) throws -> ACPTransportStdio {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectoryURL
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw ACPTransportError.processSpawnFailed(String(describing: error))
        }

        return ACPTransportStdio(
            process: process,
            stdinHandle: stdinPipe.fileHandleForWriting,
            stdoutHandle: stdoutPipe.fileHandleForReading,
            stderrHandle: stderrPipe.fileHandleForReading
        )
    }

    public init(
        process: Process,
        stdinHandle: FileHandle,
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle
    ) {
        let (events, continuation) = makeAsyncStream() as (
            AsyncStream<ACPTransportEvent>,
            AsyncStream<ACPTransportEvent>.Continuation
        )
        self.events = events
        self.eventsContinuation = continuation
        self.process = process
        self.stdinHandle = stdinHandle

        installReadabilityHandlers(
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle
        )
    }

    public func send<Payload: Encodable>(_ payload: Payload) throws {
        let encoded = try JSONEncoder().encode(payload)
        try sendEncodedMessage(encoded)
    }

    public func sendEncodedMessage(_ encoded: Data) throws {
        guard !isFinished else {
            throw ACPTransportError.connectionClosed
        }
        guard !encoded.contains(0x0A),
              !encoded.contains(0x0D) else {
            throw ACPTransportError.invalidMessageFraming
        }

        var framed = encoded
        framed.append(0x0A)

        do {
            try stdinHandle.write(contentsOf: framed)
        } catch {
            throw ACPTransportError.processTerminated(
                ACPProcessTermination(reason: .eof)
            )
        }
    }

    public func close(terminateProcess: Bool = true) {
        guard !isFinished else { return }

        stdinHandle.closeFile()
        if terminateProcess, process.isRunning {
            process.terminate()
        } else {
            emitTerminationIfNeeded(
                with: ACPProcessTermination(reason: .eof)
            )
        }
    }

    private func installReadabilityHandlers(
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle
    ) {
        let stdoutAccumulator = ACPLineAccumulator()
        let stderrAccumulator = ACPLineAccumulator()

        installStdoutHandler(
            on: stdoutHandle,
            stderrHandle: stderrHandle,
            accumulator: stdoutAccumulator
        )
        installStderrHandler(
            on: stderrHandle,
            stdoutHandle: stdoutHandle,
            accumulator: stderrAccumulator
        )
        installTerminationHandler(
            stdoutHandle: stdoutHandle,
            stderrHandle: stderrHandle
        )
    }

    private func installStdoutHandler(
        on stdoutHandle: FileHandle,
        stderrHandle: FileHandle,
        accumulator: ACPLineAccumulator
    ) {
        stdoutHandle.readabilityHandler = { [weak process] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if process?.isRunning != true {
                    stderrHandle.readabilityHandler = nil
                }
                Task {
                    self.handleEOF(
                        remainder: accumulator.finish(),
                        isStdErr: false
                    )
                }
                return
            }

            accumulator.append(chunk).forEach {
                self.eventsContinuation.yield(.message($0))
            }
        }
    }

    private func installStderrHandler(
        on stderrHandle: FileHandle,
        stdoutHandle: FileHandle,
        accumulator: ACPLineAccumulator
    ) {
        stderrHandle.readabilityHandler = { [weak process] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                if process?.isRunning != true {
                    stdoutHandle.readabilityHandler = nil
                }
                Task {
                    self.handleEOF(
                        remainder: accumulator.finish(),
                        isStdErr: true
                    )
                }
                return
            }

            accumulator.append(chunk).forEach {
                self.eventsContinuation.yield(.stderr(self.decodeUTF8($0)))
            }
        }
    }

    private func installTerminationHandler(
        stdoutHandle: FileHandle,
        stderrHandle: FileHandle
    ) {
        process.terminationHandler = { terminatedProcess in
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil

            let reason: ACPProcessTermination.Reason = switch terminatedProcess.terminationReason {
            case .exit:
                .exit
            case .uncaughtSignal:
                .uncaughtSignal
            @unknown default:
                .exit
            }

            self.emitTerminationIfNeeded(
                with: ACPProcessTermination(
                    reason: reason,
                    exitCode: terminatedProcess.terminationStatus
                )
            )
        }
    }

    private func handleEOF(remainder: Data?, isStdErr: Bool) {
        guard let remainder,
              !remainder.isEmpty else {
            emitTerminationIfNeeded(with: ACPProcessTermination(reason: .eof))
            return
        }

        if isStdErr {
            eventsContinuation.yield(
                .stderr(decodeUTF8(remainder))
            )
        } else {
            eventsContinuation.yield(.message(remainder))
        }

        emitTerminationIfNeeded(with: ACPProcessTermination(reason: .eof))
    }

    private func emitTerminationIfNeeded(with termination: ACPProcessTermination) {
        guard markFinishedIfNeeded() else { return }
        eventsContinuation.yield(.terminated(termination))
        eventsContinuation.finish()
    }

    private var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return hasFinished
    }

    private func markFinishedIfNeeded() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !hasFinished else { return false }
        hasFinished = true
        return true
    }

    private func decodeUTF8(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }
}

public actor ACPConnection {
    public nonisolated let events: AsyncStream<ACPConnectionEvent>

    private let transport: ACPTransportStdio
    private let eventsContinuation: AsyncStream<ACPConnectionEvent>.Continuation
    private var requestCounter = 0
    private var pendingRequests: [ACPRequestID: CheckedContinuation<ACPValue?, Error>] = [:]
    private var terminalError: ACPTransportError?
    private(set) var negotiatedCapabilities = ACPServerCapabilities()
    // periphery:ignore - negotiated initialize metadata is surfaced to app integration even before UI lands
    private(set) var serverInfo: ACPImplementationInfo?

    public init(transport: ACPTransportStdio) {
        let (events, continuation) = makeAsyncStream() as (
            AsyncStream<ACPConnectionEvent>,
            AsyncStream<ACPConnectionEvent>.Continuation
        )
        self.events = events
        self.eventsContinuation = continuation
        self.transport = transport

        Task {
            for await event in transport.events {
                await self.handleTransportEvent(event)
            }
        }
    }

    public func initialize(
        clientInfo: ACPImplementationInfo,
        capabilities: ACPClientCapabilities = ACPClientCapabilities(),
        protocolVersion: ACPProtocolVersion = ACPProtocolVersion.current
    ) async throws -> ACPInitializeResult {
        let params = ACPInitializeParams(
            protocolVersion: protocolVersion,
            clientInfo: clientInfo,
            clientCapabilities: capabilities
        )
        let response = try await sendRequest(method: "initialize", params: params)
        let result = try ACPValue.decode(ACPInitializeResult.self, from: response)
        negotiatedCapabilities = result.capabilities
        serverInfo = result.serverInfo
        return result
    }

    public func sendRequest<Response: Decodable, Params: Encodable>(
        method: String,
        params: Params? = nil,
        as responseType: Response.Type
    ) async throws -> Response {
        let response = try await sendRequest(method: method, params: params)
        return try ACPValue.decode(Response.self, from: response)
    }

    public func sendRequest<Params: Encodable>(
        method: String,
        params: Params? = nil
    ) async throws -> ACPValue? {
        if let terminalError {
            throw terminalError
        }

        requestCounter += 1
        let requestID = ACPRequestID(rawValue: "acp-\(requestCounter)")
        let payload = ACPJSONRPCRequest(
            id: requestID,
            method: method,
            params: params
        )

        try transport.send(payload)

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = continuation
        }
    }

    public func sendNotification<Params: Encodable>(
        method: String,
        params: Params? = nil
    ) throws {
        if let terminalError {
            throw terminalError
        }

        let payload = ACPJSONRPCNotification(
            method: method,
            params: params
        )
        try transport.send(payload)
    }

    public func respond<Payload: Encodable>(
        to requestID: ACPRequestID,
        result: Payload? = nil
    ) throws {
        if let terminalError {
            throw terminalError
        }

        let payload = ACPJSONRPCResult(
            id: requestID,
            result: result
        )
        try transport.send(payload)
    }

    public func respondError(
        to requestID: ACPRequestID,
        error: ACPRemoteError
    ) throws {
        if let terminalError {
            throw terminalError
        }

        try transport.send(
            ACPJSONRPCError(
                id: requestID,
                error: error
            )
        )
    }

    public func shutdown(terminateProcess: Bool = true) async {
        transport.close(terminateProcess: terminateProcess)
    }

    private func handleTransportEvent(_ event: ACPTransportEvent) {
        switch event {
        case .message(let data):
            handleMessageData(data)
        case .stderr(let text):
            eventsContinuation.yield(.stderr(text))
        case .terminated(let termination):
            let error = ACPTransportError.processTerminated(termination)
            terminalError = error
            let continuations = pendingRequests.values
            pendingRequests.removeAll()
            continuations.forEach { $0.resume(throwing: error) }
            eventsContinuation.yield(.terminated(termination))
            eventsContinuation.finish()
        }
    }

    // swiftlint:disable:next function_body_length
    private func handleMessageData(_ data: Data) {
        do {
            let envelope = try JSONDecoder().decode(ACPInboundEnvelope.self, from: data)
            guard envelope.jsonrpc == "2.0" else {
                throw ACPTransportError.invalidMessage("Expected JSON-RPC 2.0 envelope.")
            }

            if let method = envelope.method, envelope.id == nil {
                eventsContinuation.yield(
                    .notification(
                        ACPNotification(
                            method: method,
                            params: envelope.params
                        )
                    )
                )
                return
            }

            if let method = envelope.method,
               let requestID = envelope.id {
                eventsContinuation.yield(
                    .request(
                        ACPIncomingRequest(
                            id: requestID,
                            method: method,
                            params: envelope.params
                        )
                    )
                )
                return
            }

            guard let responseID = envelope.id else {
                throw ACPTransportError.invalidMessage("Missing response identifier.")
            }

            guard let continuation = pendingRequests.removeValue(forKey: responseID) else {
                return
            }

            if let error = envelope.error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: envelope.result)
            }
        } catch let error as ACPTransportError {
            terminalError = error
            let continuations = pendingRequests.values
            pendingRequests.removeAll()
            continuations.forEach { $0.resume(throwing: error) }
        } catch {
            let transportError = ACPTransportError.invalidMessage(String(describing: error))
            terminalError = transportError
            let continuations = pendingRequests.values
            pendingRequests.removeAll()
            continuations.forEach { $0.resume(throwing: transportError) }
        }
    }
}
