// PersistentTerminalHostDaemon.swift
// Devys - Detached terminal host that owns persistent PTYs.

import Foundation
import Darwin

final class PersistentTerminalHostDaemon: @unchecked Sendable {
    private final class HostedSession {
        let record: HostedTerminalSessionRecord
        let pid: pid_t
        let primaryFD: Int32
        let persistOnDisconnect: Bool
        var outputBuffer = Data()
        var readSource: DispatchSourceRead?
        var clients: [Int32: HostAttachedClient] = [:]
        var isRunning = true
        var exitFrame = TerminalHostExitFrame(exitCode: nil, signal: nil)
        var cleanupWorkItem: DispatchWorkItem?

        init(
            record: HostedTerminalSessionRecord,
            pid: pid_t,
            primaryFD: Int32,
            persistOnDisconnect: Bool
        ) {
            self.record = record
            self.pid = pid
            self.primaryFD = primaryFD
            self.persistOnDisconnect = persistOnDisconnect
        }
    }

    private final class HostAttachedClient {
        let fileHandle: FileHandle
        var readSource: DispatchSourceRead?
        var inputBuffer = Data()

        init(fileHandle: FileHandle) {
            self.fileHandle = fileHandle
        }
    }

    private let socketPath: String
    private let metadataPath: String
    private let queue = DispatchQueue(label: "com.devys.terminal-host")

    private var listenerFD: Int32 = -1
    private var sessionsByID: [UUID: HostedSession] = [:]

    init(socketPath: String) {
        self.socketPath = socketPath
        self.metadataPath = terminalHostMetadataPath(for: socketPath)
    }

    func run() throws -> Never {
        listenerFD = try TerminalHostSocketIO.bindAndListen(at: socketPath)
        setNonBlocking(listenerFD)
        writeDaemonMetadata()

        let source = DispatchSource.makeReadSource(fileDescriptor: listenerFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.setCancelHandler { [listenerFD] in
            if listenerFD >= 0 {
                Darwin.close(listenerFD)
            }
        }
        source.resume()

        withExtendedLifetime(source) {
            dispatchMain()
        }
    }
}

private extension PersistentTerminalHostDaemon {
    struct CreateSessionRequest {
        let id: UUID
        let workspaceID: String
        let workingDirectoryPath: String?
        let launchCommand: String?
        let initialSize: HostedTerminalViewportSize?
        let launchProfile: TerminalSessionLaunchProfile
        let persistOnDisconnect: Bool
    }

    struct AttachRequest {
        let sessionID: UUID
        let cols: Int
        let rows: Int
        let replayBudget: TerminalHostAttachReplayBudget
        let handle: FileHandle
        let fd: Int32
    }

    private func acceptPendingConnections() {
        while true {
            let acceptedFD: Int32
            do {
                acceptedFD = try TerminalHostSocketIO.accept(on: listenerFD)
            } catch TerminalHostSocketError.acceptFailed(let code) where code == EWOULDBLOCK || code == EAGAIN {
                return
            } catch {
                return
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else {
                    Darwin.close(acceptedFD)
                    return
                }

                let handle = FileHandle(fileDescriptor: acceptedFD, closeOnDealloc: true)
                do {
                    let line = try TerminalHostSocketIO.readLine(from: handle)
                    let request = try JSONDecoder().decode(TerminalHostControlRequest.self, from: line)
                    self.queue.async {
                        self.handleInitialRequest(request, handle: handle, fd: acceptedFD)
                    }
                } catch {
                    try? handle.close()
                }
            }
        }
    }

    private func handleInitialRequest(
        _ request: TerminalHostControlRequest,
        handle: FileHandle,
        fd: Int32
    ) {
        switch request {
        case .ping:
            sendControlResponse(.pong, to: handle)
            try? handle.close()
        case .listSessions:
            respondWithSessions(to: handle)
        case .createSession(
            let id,
            let workspaceID,
            let workingDirectoryPath,
            let launchCommand,
            let initialSize,
            let launchProfile,
            let persistOnDisconnect
        ):
            handleCreateSession(
                request: CreateSessionRequest(
                    id: id,
                    workspaceID: workspaceID,
                    workingDirectoryPath: workingDirectoryPath,
                    launchCommand: launchCommand,
                    initialSize: initialSize,
                    launchProfile: launchProfile,
                    persistOnDisconnect: persistOnDisconnect
                ),
                handle: handle
            )
        case .terminateSession(let id):
            handleTerminateSession(id: id, handle: handle)
        case .attach(let sessionID, let cols, let rows, let replayBudget):
            handleAttach(
                request: AttachRequest(
                    sessionID: sessionID,
                    cols: cols,
                    rows: rows,
                    replayBudget: replayBudget,
                    handle: handle,
                    fd: fd
                )
            )
        }
    }

    private func createSession(
        request: CreateSessionRequest
    ) throws -> HostedTerminalSessionRecord {
        let initialSize = request.initialSize ?? HostedTerminalViewportSize(cols: 120, rows: 40)
        let launchContext = try makeTerminalSessionLaunchContext(
            launchProfile: request.launchProfile,
            launchCommand: request.launchCommand
        )
        let spawnedProcess = try spawnTerminalProcess(
            initialSize: initialSize,
            workingDirectoryPath: request.workingDirectoryPath,
            launchContext: launchContext
        )

        let record = HostedTerminalSessionRecord(
            id: request.id,
            workspaceID: request.workspaceID,
            workingDirectory: request.workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            launchCommand: request.launchCommand,
            viewportSize: HostedTerminalViewportSizeRecord(
                cols: initialSize.cols,
                rows: initialSize.rows
            ),
            processID: Int32(spawnedProcess.pid),
            createdAt: Date()
        )
        let session = HostedSession(
            record: record,
            pid: spawnedProcess.pid,
            primaryFD: spawnedProcess.primaryFD,
            persistOnDisconnect: request.persistOnDisconnect
        )
        sessionsByID[request.id] = session

        configureSessionReadSource(for: session, sessionID: request.id)
        return record
    }

    private func spawnTerminalProcess(
        initialSize: HostedTerminalViewportSize,
        workingDirectoryPath: String?,
        launchContext: TerminalSessionLaunchContext
    ) throws -> (pid: pid_t, primaryFD: Int32) {
        var winsize = terminalWindowSize(cols: initialSize.cols, rows: initialSize.rows)
        var primaryFD: Int32 = -1
        let pid = forkpty(&primaryFD, nil, nil, &winsize)
        guard pid >= 0 else {
            throw NSError(
                domain: "PersistentTerminalHostDaemon",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create a persistent PTY session."]
            )
        }

        if pid == 0 {
            runTerminalSessionChild(
                workingDirectoryPath: workingDirectoryPath,
                launchContext: launchContext
            )
        }

        setNonBlocking(primaryFD)
        return (pid, primaryFD)
    }

    private func configureSessionReadSource(
        for session: HostedSession,
        sessionID: UUID
    ) {
        let source = DispatchSource.makeReadSource(fileDescriptor: session.primaryFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainOutput(for: sessionID)
        }
        source.setCancelHandler { [primaryFD = session.primaryFD] in
            Darwin.close(primaryFD)
        }
        session.readSource = source
        source.resume()
    }

    private func drainOutput(for sessionID: UUID) {
        guard let session = sessionsByID[sessionID] else { return }

        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(session.primaryFD, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer.prefix(Int(count)))
                session.outputBuffer.append(data)
                trimOutputBuffer(for: session)
                broadcast(type: .output, payload: data, in: session)
                continue
            }

            if count == 0 {
                finishSession(sessionID)
                return
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            }

            finishSession(sessionID)
            return
        }
    }

    private func readClientFrames(sessionID: UUID, clientFD: Int32) {
        guard let session = sessionsByID[sessionID],
              let client = session.clients[clientFD]
        else { return }

        do {
            let read = try TerminalHostSocketIO.readAvailable(from: clientFD)
            if !read.data.isEmpty {
                client.inputBuffer.append(read.data)
            }

            while let (type, payload) = try TerminalHostSocketIO.parseFrame(from: &client.inputBuffer) {
                switch type {
                case .input:
                    _ = payload.withUnsafeBytes { pointer in
                        Darwin.write(session.primaryFD, pointer.baseAddress, payload.count)
                    }
                case .resize:
                    let size = try JSONDecoder().decode(TerminalHostResizeFrame.self, from: payload)
                    resize(session: session, cols: size.cols, rows: size.rows)
                case .close:
                    detachClient(clientFD, from: sessionID)
                    return
                case .output:
                    break
                }
            }

            if read.reachedEOF {
                detachClient(clientFD, from: sessionID)
            }
        } catch {
            detachClient(clientFD, from: sessionID)
        }
    }

    private func resize(session: HostedSession, cols: Int, rows: Int) {
        var size = terminalWindowSize(cols: cols, rows: rows)
        _ = withUnsafeMutablePointer(to: &size) { pointer in
            ioctl(session.primaryFD, TIOCSWINSZ, pointer)
        }
        if session.isRunning {
            _ = kill(session.pid, SIGWINCH)
        }
    }

    private func terminateSession(id: UUID) {
        guard let session = sessionsByID[id] else { return }
        session.cleanupWorkItem?.cancel()
        session.cleanupWorkItem = nil

        if session.isRunning {
            kill(session.pid, SIGTERM)
        }
        finishSession(id, removeImmediately: true)
    }

    private func finishSession(_ sessionID: UUID, removeImmediately: Bool = false) {
        guard let session = sessionsByID[sessionID] else { return }

        session.cleanupWorkItem?.cancel()
        session.cleanupWorkItem = nil

        if session.isRunning {
            session.isRunning = false
            session.readSource?.cancel()
            session.readSource = nil

            var status: Int32 = 0
            _ = waitpid(session.pid, &status, 0)
            session.exitFrame = decodeExitFrame(from: status)
        }

        let exitPayload = (try? JSONEncoder().encode(session.exitFrame)) ?? Data()
        for client in session.clients.values {
            try? TerminalHostSocketIO.writeFrame(
                type: .close,
                payload: exitPayload,
                to: client.fileHandle
            )
            client.readSource?.cancel()
            try? client.fileHandle.close()
        }
        session.clients.removeAll()

        if removeImmediately {
            removeSession(id: sessionID)
            return
        }

        scheduleFinishedSessionCleanup(for: sessionID)
    }

    private func detachClient(_ clientFD: Int32, from sessionID: UUID) {
        guard let session = sessionsByID[sessionID],
              let client = session.clients.removeValue(forKey: clientFD)
        else { return }
        client.readSource?.cancel()
        try? client.fileHandle.close()

        guard session.clients.isEmpty else { return }

        if session.isRunning == false {
            removeSession(id: sessionID)
            return
        }

        if session.persistOnDisconnect == false {
            terminateSession(id: sessionID)
        }
    }

    private func broadcast(
        type: TerminalHostStreamFrameType,
        payload: Data,
        in session: HostedSession
    ) {
        for (clientFD, client) in session.clients {
            do {
                try TerminalHostSocketIO.writeFrame(type: type, payload: payload, to: client.fileHandle)
            } catch {
                detachClient(clientFD, from: session.record.id)
            }
        }
    }

    private func trimOutputBuffer(for session: HostedSession) {
        let maxBytes = TerminalHostAttachReplayBudget.retainedOutputLimitBytes
        guard session.outputBuffer.count > maxBytes else { return }
        session.outputBuffer.removeFirst(session.outputBuffer.count - maxBytes)
    }

    private func sendControlResponse(_ response: TerminalHostControlResponse, to handle: FileHandle) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        try? TerminalHostSocketIO.writeLine(data, to: handle)
    }

    private func respondWithSessions(to handle: FileHandle) {
        let records = sessionsByID.values.map(\.record).sorted { $0.createdAt < $1.createdAt }
        sendControlResponse(.sessions(records), to: handle)
        try? handle.close()
    }

    private func handleCreateSession(
        request: CreateSessionRequest,
        handle: FileHandle
    ) {
        do {
            let record = try createSession(request: request)
            sendControlResponse(.created(record), to: handle)
        } catch {
            sendControlResponse(.failure(error.localizedDescription), to: handle)
        }
        try? handle.close()
    }

    private func handleTerminateSession(id: UUID, handle: FileHandle) {
        terminateSession(id: id)
        sendControlResponse(.terminated, to: handle)
        try? handle.close()
    }

    private func handleAttach(request: AttachRequest) {
        guard let session = sessionsByID[request.sessionID] else {
            sendControlResponse(
                .failure("Terminal session \(request.sessionID.uuidString) was not found."),
                to: request.handle
            )
            try? request.handle.close()
            return
        }

        session.cleanupWorkItem?.cancel()
        session.cleanupWorkItem = nil
        resize(session: session, cols: request.cols, rows: request.rows)
        let client = HostAttachedClient(fileHandle: request.handle)
        session.clients[request.fd] = client
        sendControlResponse(.attached, to: request.handle)

        let replayPayload = request.replayBudget.replayPayload(from: session.outputBuffer)
        if !replayPayload.isEmpty {
            try? TerminalHostSocketIO.writeFrame(type: .output, payload: replayPayload, to: request.handle)
        }
        if !session.isRunning {
            let exitPayload = (try? JSONEncoder().encode(session.exitFrame)) ?? Data()
            try? TerminalHostSocketIO.writeFrame(type: .close, payload: exitPayload, to: request.handle)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: request.fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readClientFrames(sessionID: request.sessionID, clientFD: request.fd)
        }
        source.setCancelHandler { [weak self] in
            guard let self,
                  let session = self.sessionsByID[request.sessionID]
            else { return }

            session.clients.removeValue(forKey: request.fd)
            if session.clients.isEmpty, session.isRunning == false {
                self.removeSession(id: request.sessionID)
            }
        }
        client.readSource = source
        source.resume()
    }

    private func scheduleFinishedSessionCleanup(for sessionID: UUID) {
        guard let session = sessionsByID[sessionID],
              session.persistOnDisconnect == false,
              session.clients.isEmpty
        else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  let session = self.sessionsByID[sessionID],
                  session.clients.isEmpty,
                  session.isRunning == false
            else { return }
            self.removeSession(id: sessionID)
        }

        session.cleanupWorkItem = workItem
        queue.asyncAfter(deadline: .now() + .seconds(30), execute: workItem)
    }

    private func removeSession(id: UUID) {
        guard let session = sessionsByID.removeValue(forKey: id) else { return }
        session.cleanupWorkItem?.cancel()
        session.cleanupWorkItem = nil
        session.readSource?.cancel()
        session.readSource = nil
        session.clients.removeAll()
    }

    private func decodeExitFrame(from status: Int32) -> TerminalHostExitFrame {
        let terminationStatus = Int(status) & 0o177
        if terminationStatus == 0 {
            return TerminalHostExitFrame(
                exitCode: (Int(status) >> 8) & 0xFF,
                signal: nil
            )
        }

        if terminationStatus != 0o177 {
            return TerminalHostExitFrame(
                exitCode: nil,
                signal: String(terminationStatus)
            )
        }

        return TerminalHostExitFrame(exitCode: nil, signal: nil)
    }

    private func writeDaemonMetadata() {
        guard let executablePath = terminalHostCurrentExecutablePath() else { return }
        let metadata = TerminalHostDaemonMetadata(
            executablePath: executablePath,
            executableFingerprint: terminalHostExecutableFingerprint(at: executablePath)
        )

        guard let data = try? JSONEncoder().encode(metadata) else { return }
        FileManager.default.createFile(atPath: metadataPath, contents: data)
    }
}

private func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0 else { return }
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
}

func terminalWindowSize(cols: Int, rows: Int) -> winsize {
    winsize(
        ws_row: UInt16(clamping: max(rows, 1)),
        ws_col: UInt16(clamping: max(cols, 1)),
        ws_xpixel: 0,
        ws_ypixel: 0
    )
}
