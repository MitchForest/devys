// PersistentTerminalHostDaemon.swift
// Devys - Detached terminal host that owns persistent PTYs.

import Foundation
import Darwin

final class PersistentTerminalHostDaemon: @unchecked Sendable {
    private final class HostedSession {
        let record: HostedTerminalSessionRecord
        let pid: pid_t
        let primaryFD: Int32
        var outputBuffer = Data()
        var readSource: DispatchSourceRead?
        var clients: [Int32: HostAttachedClient] = [:]
        var isRunning = true
        var exitFrame = TerminalHostExitFrame(exitCode: nil, signal: nil)

        init(record: HostedTerminalSessionRecord, pid: pid_t, primaryFD: Int32) {
            self.record = record
            self.pid = pid
            self.primaryFD = primaryFD
        }
    }

    private final class HostAttachedClient {
        let fileHandle: FileHandle
        var readSource: DispatchSourceRead?

        init(fileHandle: FileHandle) {
            self.fileHandle = fileHandle
        }
    }

    private let socketPath: String
    private let queue = DispatchQueue(label: "com.devys.terminal-host")

    private var listenerFD: Int32 = -1
    private var sessionsByID: [UUID: HostedSession] = [:]

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func run() throws -> Never {
        listenerFD = try TerminalHostSocketIO.bindAndListen(at: socketPath)
        setNonBlocking(listenerFD)

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
        case .createSession(let id, let workspaceID, let workingDirectoryPath, let launchCommand):
            handleCreateSession(
                id: id,
                workspaceID: workspaceID,
                workingDirectoryPath: workingDirectoryPath,
                launchCommand: launchCommand,
                handle: handle
            )
        case .terminateSession(let id):
            handleTerminateSession(id: id, handle: handle)
        case .attach(let sessionID, let cols, let rows):
            handleAttach(sessionID: sessionID, cols: cols, rows: rows, handle: handle, fd: fd)
        }
    }

    private func createSession(
        id: UUID,
        workspaceID: String,
        workingDirectoryPath: String?,
        launchCommand: String?
    ) throws -> HostedTerminalSessionRecord {
        var winsize = Darwin.winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
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
            if let workingDirectoryPath {
                _ = workingDirectoryPath.withCString { Darwin.chdir($0) }
            }
            applyTerminalSessionEnvironment()
            execShell(launchCommand: launchCommand)
        }

        setNonBlocking(primaryFD)

        let record = HostedTerminalSessionRecord(
            id: id,
            workspaceID: workspaceID,
            workingDirectory: workingDirectoryPath.map { URL(fileURLWithPath: $0) },
            launchCommand: launchCommand,
            processID: Int32(pid),
            createdAt: Date()
        )
        let session = HostedSession(record: record, pid: pid, primaryFD: primaryFD)
        sessionsByID[id] = session

        let source = DispatchSource.makeReadSource(fileDescriptor: primaryFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.drainOutput(for: id)
        }
        source.setCancelHandler { [primaryFD] in
            Darwin.close(primaryFD)
        }
        session.readSource = source
        source.resume()

        return record
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
            while true {
                let (type, payload) = try TerminalHostSocketIO.readFrame(from: client.fileHandle)
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
        } catch {
            detachClient(clientFD, from: sessionID)
        }
    }

    private func resize(session: HostedSession, cols: Int, rows: Int) {
        _ = session
        _ = cols
        _ = rows
    }

    private func terminateSession(id: UUID) {
        guard let session = sessionsByID[id] else { return }
        kill(session.pid, SIGTERM)
        finishSession(id)
    }

    private func finishSession(_ sessionID: UUID) {
        guard let session = sessionsByID.removeValue(forKey: sessionID) else { return }

        session.isRunning = false
        session.readSource?.cancel()
        session.readSource = nil

        var status: Int32 = 0
        _ = waitpid(session.pid, &status, 0)
        session.exitFrame = decodeExitFrame(from: status)

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
    }

    private func detachClient(_ clientFD: Int32, from sessionID: UUID) {
        guard let session = sessionsByID[sessionID],
              let client = session.clients.removeValue(forKey: clientFD)
        else { return }
        client.readSource?.cancel()
        try? client.fileHandle.close()
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
        let maxBytes = 512 * 1024
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
        id: UUID,
        workspaceID: String,
        workingDirectoryPath: String?,
        launchCommand: String?,
        handle: FileHandle
    ) {
        do {
            let record = try createSession(
                id: id,
                workspaceID: workspaceID,
                workingDirectoryPath: workingDirectoryPath,
                launchCommand: launchCommand
            )
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

    private func handleAttach(
        sessionID: UUID,
        cols: Int,
        rows: Int,
        handle: FileHandle,
        fd: Int32
    ) {
        guard let session = sessionsByID[sessionID] else {
            sendControlResponse(.failure("Terminal session \(sessionID.uuidString) was not found."), to: handle)
            try? handle.close()
            return
        }

        resize(session: session, cols: cols, rows: rows)
        let client = HostAttachedClient(fileHandle: handle)
        session.clients[fd] = client
        sendControlResponse(.attached, to: handle)

        if !session.outputBuffer.isEmpty {
            try? TerminalHostSocketIO.writeFrame(type: .output, payload: session.outputBuffer, to: handle)
        }
        if !session.isRunning {
            let exitPayload = (try? JSONEncoder().encode(session.exitFrame)) ?? Data()
            try? TerminalHostSocketIO.writeFrame(type: .close, payload: exitPayload, to: handle)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readClientFrames(sessionID: sessionID, clientFD: fd)
        }
        source.setCancelHandler { [weak self] in
            self?.sessionsByID[sessionID]?.clients.removeValue(forKey: fd)
        }
        client.readSource = source
        source.resume()
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
}

private func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0 else { return }
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
}

func terminalSessionEnvironmentAssignments() -> [String: String] {
    var assignments = [
        "COLORTERM": "truecolor",
        "COLORFGBG": terminalSessionColorFgBg(),
        "TERM": "xterm-256color",
        "TERM_PROGRAM": "ghostty",
    ]

    if let termProgramVersion = terminalSessionTermProgramVersion() {
        assignments["TERM_PROGRAM_VERSION"] = termProgramVersion
    }

    return assignments
}

func terminalSessionEnvironmentKeysToUnset() -> [String] {
    colorSuppressingEnvironmentKeysList()
}

func terminalSessionTermProgramVersion() -> String? {
    let infoDictionary = Bundle.main.infoDictionary
    let shortVersion = infoDictionary?["CFBundleShortVersionString"] as? String
    if let shortVersion,
       !shortVersion.isEmpty {
        return shortVersion
    }

    let bundleVersion = infoDictionary?["CFBundleVersion"] as? String
    if let bundleVersion,
       !bundleVersion.isEmpty {
        return bundleVersion
    }

    return nil
}

func terminalSessionColorFgBg() -> String {
    let environment = ProcessInfo.processInfo.environment
    if let colorFgBg = environment["COLORFGBG"],
       !colorFgBg.isEmpty {
        return colorFgBg
    }

    return "15;0"
}

func resolvedTerminalShellPath(
    environment: [String: String]
) -> String {
    guard let shellPath = environment["SHELL"],
          shellPath.hasPrefix("/"),
          !shellPath.isEmpty
    else {
        return "/bin/zsh"
    }
    return shellPath
}

func terminalShellLaunchConfiguration(
    launchCommand: String?,
    environment: [String: String]
) -> (executablePath: String, arguments: [String]) {
    let executablePath = resolvedTerminalShellPath(environment: environment)
    let shellName = URL(fileURLWithPath: executablePath).lastPathComponent

    if let launchCommand,
       !launchCommand.isEmpty {
        return (
            executablePath,
            [shellName, "-i", "-l", "-c", launchCommand]
        )
    }

    return (
        executablePath,
        [shellName, "-i", "-l"]
    )
}

private func applyTerminalSessionEnvironment() {
    for key in terminalSessionEnvironmentKeysToUnset() {
        unsetenv(key)
    }
    for (key, value) in terminalSessionEnvironmentAssignments() {
        setenv(key, value, 1)
    }
}

private func execShell(launchCommand: String?) -> Never {
    let configuration = terminalShellLaunchConfiguration(
        launchCommand: launchCommand,
        environment: ProcessInfo.processInfo.environment
    )
    let arguments = configuration.arguments

    var cArguments = arguments.map { strdup($0) }
    cArguments.append(nil)
    defer {
        for pointer in cArguments {
            free(pointer)
        }
    }

    _ = configuration.executablePath.withCString { executable in
        cArguments.withUnsafeMutableBufferPointer { buffer in
            execv(executable, buffer.baseAddress)
        }
    }
    _exit(127)
}
