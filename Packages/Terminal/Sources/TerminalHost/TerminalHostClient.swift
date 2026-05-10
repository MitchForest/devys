import Foundation

#if os(macOS)
import Darwin
#endif

public struct TerminalSessionHandle: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID

    public init(id: UUID) {
        self.id = id
    }
}

public struct TerminalHostSize: Codable, Equatable, Sendable {
    public var cols: Int
    public var rows: Int

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = max(1, cols)
        self.rows = max(1, rows)
    }
}

public struct TerminalLaunchProfile: Codable, Equatable, Sendable {
    public var executablePath: String
    public var arguments: [String]

    public init(executablePath: String, arguments: [String]) {
        self.executablePath = executablePath
        self.arguments = arguments
    }

    public static func userShell(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TerminalLaunchProfile {
        let executablePath = resolvedShellPath(environment: environment)
        let shellName = executablePath.split(separator: "/").last.map(String.init) ?? executablePath
        return TerminalLaunchProfile(executablePath: executablePath, arguments: [shellName, "-i", "-l"])
    }

    private static func resolvedShellPath(environment: [String: String]) -> String {
        guard let shellPath = environment["SHELL"],
              shellPath.hasPrefix("/"),
              !shellPath.isEmpty
        else {
            return "/bin/zsh"
        }
        return shellPath
    }
}

public enum TerminalHostEvent: Equatable, Sendable {
    case output(Data)
    case exited(TerminalHostExit)
}

public struct TerminalHostExit: Codable, Equatable, Sendable {
    public var exitCode: Int?
    public var signal: Int?

    public init(exitCode: Int?, signal: Int?) {
        self.exitCode = exitCode
        self.signal = signal
    }
}

public enum TerminalHostError: LocalizedError, Sendable {
    case unsupportedPlatform
    case failedToCreatePTY
    case sessionNotFound(UUID)
    case writeFailed(Int32)
    case resizeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            "Local PTY sessions are only supported on macOS."
        case .failedToCreatePTY:
            "Could not create a local PTY session."
        case .sessionNotFound(let id):
            "Terminal session \(id.uuidString) was not found."
        case .writeFailed(let code):
            "Could not write terminal input (\(code))."
        case .resizeFailed(let code):
            "Could not resize terminal session (\(code))."
        }
    }
}

public actor TerminalHostClient {
    private final class Session {
        let id: UUID
        let pid: Int32
        let primaryFD: Int32
        var continuations: [UUID: AsyncStream<TerminalHostEvent>.Continuation] = [:]
        var outputBuffer = Data()
        var readSource: DispatchSourceRead?
        var didExit = false

        init(id: UUID, pid: Int32, primaryFD: Int32) {
            self.id = id
            self.pid = pid
            self.primaryFD = primaryFD
        }
    }

    private var sessionsByID: [UUID: Session] = [:]
    private let readQueue = DispatchQueue(label: "com.devys.terminal-host-client")

    public init() {}

    public func create(
        profile: TerminalLaunchProfile = .userShell(),
        cwd: URL? = nil,
        env: [String: String] = [:],
        size: TerminalHostSize = TerminalHostSize()
    ) async throws -> TerminalSessionHandle {
        #if os(macOS)
        let id = UUID()
        var winsize = inProcessTerminalWindowSize(cols: size.cols, rows: size.rows)
        var primaryFD: Int32 = -1
        let pid = forkpty(&primaryFD, nil, nil, &winsize)
        guard pid >= 0 else {
            throw TerminalHostError.failedToCreatePTY
        }

        if pid == 0 {
            runTerminalChild(profile: profile, cwd: cwd, env: env)
        }

        let session = Session(id: id, pid: pid, primaryFD: primaryFD)
        sessionsByID[id] = session
        setNonBlocking(primaryFD)
        configureReadSource(for: session)
        return TerminalSessionHandle(id: id)
        #else
        throw TerminalHostError.unsupportedPlatform
        #endif
    }

    public func attach(
        _ handle: TerminalSessionHandle
    ) async throws -> AsyncStream<TerminalHostEvent> {
        let session = try session(for: handle)
        let attachmentID = UUID()

        return AsyncStream { continuation in
            session.continuations[attachmentID] = continuation
            if !session.outputBuffer.isEmpty {
                continuation.yield(.output(session.outputBuffer))
            }
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.detach(attachmentID: attachmentID, from: handle.id)
                }
            }
        }
    }

    public func resize(
        _ handle: TerminalSessionHandle,
        cols: Int,
        rows: Int
    ) async throws {
        #if os(macOS)
        let session = try session(for: handle)
        var size = inProcessTerminalWindowSize(cols: cols, rows: rows)
        let result = withUnsafeMutablePointer(to: &size) { pointer in
            ioctl(session.primaryFD, TIOCSWINSZ, pointer)
        }
        guard result == 0 else {
            throw TerminalHostError.resizeFailed(errno)
        }
        Darwin.kill(session.pid, SIGWINCH)
        #else
        throw TerminalHostError.unsupportedPlatform
        #endif
    }

    public func sendText(
        _ text: String,
        to handle: TerminalSessionHandle
    ) async throws {
        try await send(Data(text.utf8), to: handle)
    }

    public func pasteText(
        _ text: String,
        to handle: TerminalSessionHandle
    ) async throws {
        try await sendText(text, to: handle)
    }

    public func send(
        _ data: Data,
        to handle: TerminalSessionHandle
    ) async throws {
        #if os(macOS)
        let session = try session(for: handle)
        try write(data, to: session.primaryFD)
        #else
        throw TerminalHostError.unsupportedPlatform
        #endif
    }

    /// Resolves the foreground process group of a session's PTY into a
    /// `TerminalForegroundProcess`. Returns `nil` if the session is unknown, the pgid
    /// can't be read, or the process has exited.
    public func foregroundProcess(
        _ handle: TerminalSessionHandle
    ) async -> TerminalForegroundProcess? {
        #if os(macOS)
        guard let session = sessionsByID[handle.id], !session.didExit else { return nil }
        return TerminalForegroundProcessProbe.probe(primaryFD: session.primaryFD)
        #else
        return nil
        #endif
    }

    /// Resolves the current working directory of the session's login shell process.
    ///
    /// This is a metadata probe for app shell features such as project auto-detection.
    /// It intentionally stays in `TerminalHost` so app-domain code never owns process
    /// handles or platform-specific proc APIs.
    public func currentWorkingDirectory(
        _ handle: TerminalSessionHandle
    ) async -> URL? {
        #if os(macOS)
        guard let session = sessionsByID[handle.id], !session.didExit else { return nil }
        return processCurrentWorkingDirectory(pid: session.pid)
        #else
        return nil
        #endif
    }

    public func terminate(_ handle: TerminalSessionHandle) async {
        #if os(macOS)
        guard let session = sessionsByID[handle.id] else { return }
        session.readSource?.cancel()
        session.readSource = nil
        Darwin.kill(session.pid, SIGTERM)
        finish(sessionID: handle.id, exit: TerminalHostExit(exitCode: nil, signal: Int(SIGTERM)))
        #endif
    }

    private func session(for handle: TerminalSessionHandle) throws -> Session {
        guard let session = sessionsByID[handle.id] else {
            throw TerminalHostError.sessionNotFound(handle.id)
        }
        return session
    }

    private func detach(attachmentID: UUID, from sessionID: UUID) {
        sessionsByID[sessionID]?.continuations.removeValue(forKey: attachmentID)
    }

    private func emit(_ event: TerminalHostEvent, for sessionID: UUID) {
        guard let session = sessionsByID[sessionID] else { return }
        if case .output(let data) = event {
            session.outputBuffer.append(data)
            let limit = 512 * 1024
            if session.outputBuffer.count > limit {
                session.outputBuffer.removeFirst(session.outputBuffer.count - limit)
            }
        }
        for continuation in session.continuations.values {
            continuation.yield(event)
        }
    }

    private func finish(sessionID: UUID, exit: TerminalHostExit) {
        guard let session = sessionsByID.removeValue(forKey: sessionID) else { return }
        session.didExit = true
        session.readSource?.cancel()
        session.readSource = nil
        for continuation in session.continuations.values {
            continuation.yield(.exited(exit))
            continuation.finish()
        }
        session.continuations.removeAll()
    }

    #if os(macOS)
    private func configureReadSource(for session: Session) {
        let source = DispatchSource.makeReadSource(fileDescriptor: session.primaryFD, queue: readQueue)
        let sessionID = session.id
        source.setEventHandler { [weak self] in
            Task { [weak self] in
                guard let self else { return }
                await self.drainOutput(sessionID: sessionID)
            }
        }
        source.setCancelHandler { [primaryFD = session.primaryFD] in
            Darwin.close(primaryFD)
        }
        session.readSource = source
        source.resume()
    }

    private func drainOutput(sessionID: UUID) {
        guard let session = sessionsByID[sessionID] else { return }
        do {
            let read = try readAvailableBytes(from: session.primaryFD)
            if !read.data.isEmpty {
                emit(.output(read.data), for: sessionID)
            }
            if read.reachedEOF {
                finishExitedSession(session)
            }
        } catch {
            finishExitedSession(session)
        }
    }

    private func finishExitedSession(_ session: Session) {
        var status: Int32 = 0
        let result = waitpid(session.pid, &status, WNOHANG)
        if result == session.pid {
            finish(sessionID: session.id, exit: terminalExit(from: status))
        } else if result < 0 {
            finish(sessionID: session.id, exit: TerminalHostExit(exitCode: nil, signal: nil))
        } else {
            let sessionID = session.id
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(20))
                await self?.drainOutput(sessionID: sessionID)
            }
        }
    }

    private func write(_ data: Data, to fd: Int32) throws {
        var remaining = data[...]
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { pointer in
                Darwin.write(fd, pointer.baseAddress, remaining.count)
            }
            guard written >= 0 else {
                if errno == EINTR { continue }
                throw TerminalHostError.writeFailed(errno)
            }
            remaining = remaining.dropFirst(Int(written))
        }
    }

    private func readAvailableBytes(from fd: Int32) throws -> InProcessTerminalHostStreamRead {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(Int(count)))
                continue
            }
            if count == 0 {
                return InProcessTerminalHostStreamRead(data: data, reachedEOF: true)
            }
            if errno == EWOULDBLOCK || errno == EAGAIN {
                return InProcessTerminalHostStreamRead(data: data, reachedEOF: false)
            }
            if errno == EINTR {
                continue
            }
            return InProcessTerminalHostStreamRead(data: data, reachedEOF: true)
        }
    }
    #endif
}

private struct InProcessTerminalHostStreamRead: Sendable {
    var data: Data
    var reachedEOF: Bool
}

#if os(macOS)
private func inProcessTerminalWindowSize(cols: Int, rows: Int) -> winsize {
    winsize(
        ws_row: UInt16(clamping: max(rows, 1)),
        ws_col: UInt16(clamping: max(cols, 1)),
        ws_xpixel: 0,
        ws_ypixel: 0
    )
}

private func terminalExit(from status: Int32) -> TerminalHostExit {
    let terminationStatus = Int(status) & 0o177
    if terminationStatus == 0 {
        return TerminalHostExit(exitCode: (Int(status) >> 8) & 0xFF, signal: nil)
    }
    if terminationStatus != 0o177 {
        return TerminalHostExit(exitCode: nil, signal: terminationStatus)
    }
    return TerminalHostExit(exitCode: nil, signal: nil)
}

private func setNonBlocking(_ fd: Int32) {
    let flags = fcntl(fd, F_GETFL)
    guard flags >= 0 else { return }
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
}

private func processCurrentWorkingDirectory(pid: Int32) -> URL? {
    var info = proc_vnodepathinfo()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<proc_vnodepathinfo>.size) {
            proc_pidinfo(
                Int32(pid),
                PROC_PIDVNODEPATHINFO,
                0,
                $0,
                Int32(MemoryLayout<proc_vnodepathinfo>.size)
            )
        }
    }
    guard result == Int32(MemoryLayout<proc_vnodepathinfo>.size) else { return nil }

    let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { rawBuffer in
        let bytes = Array(rawBuffer)
        let nullIndex = bytes.firstIndex(of: 0) ?? bytes.count
        guard nullIndex > 0 else { return nil as String? }
        return String(bytes: bytes[..<nullIndex], encoding: .utf8)
    }

    guard let path, path.hasPrefix("/") else { return nil }
    return URL(fileURLWithPath: path).standardizedFileURL
}

private func runTerminalChild(
    profile: TerminalLaunchProfile,
    cwd: URL?,
    env: [String: String]
) -> Never {
    if let cwd {
        _ = cwd.path.withCString { Darwin.chdir($0) }
    }

    unsetenv("NO_COLOR")
    setenv("COLORTERM", "truecolor", 1)
    // `xterm-ghostty` isn't shipped in the system terminfo database, so zsh's ZLE
    // can't initialize and degrades to a broken cooked-mode echo path (backspace
    // ends up advancing the cursor instead of erasing). `xterm-256color` is
    // universally available and pairs with `COLORTERM=truecolor` to keep 24-bit
    // color support; we'd switch to `xterm-ghostty` once we ship its terminfo.
    setenv("TERM", "xterm-256color", 1)
    setenv("TERM_PROGRAM", "Devys", 1)
    for (key, value) in env {
        setenv(key, value, 1)
    }

    var arguments = profile.arguments
    if arguments.isEmpty {
        arguments = [URL(fileURLWithPath: profile.executablePath).lastPathComponent]
    }
    var cArguments = arguments.map { strdup($0) }
    cArguments.append(nil)

    _ = profile.executablePath.withCString { executable in
        cArguments.withUnsafeMutableBufferPointer { buffer in
            execv(executable, buffer.baseAddress)
        }
    }
    _exit(127)
}
#endif
