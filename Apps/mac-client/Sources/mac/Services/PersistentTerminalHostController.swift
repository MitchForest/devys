// PersistentTerminalHostController.swift
// Devys - Client bridge for the detached terminal host process.

import Foundation
import Workspace

enum PersistentTerminalHostStartupMode: String, Sendable {
    case warm
    case cold
}

actor PersistentTerminalHostController {
    private let fileManager: FileManager
    nonisolated let socketPath: String
    private let metadataPath: String
    private let executablePathProvider: @Sendable () -> String?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        socketPath: String = PersistentTerminalHostController.defaultSocketPath(),
        executablePathProvider: @escaping @Sendable () -> String? = {
            Bundle.main.executableURL?.path
        }
    ) {
        self.fileManager = fileManager
        self.socketPath = socketPath
        self.metadataPath = terminalHostMetadataPath(for: socketPath)
        self.executablePathProvider = executablePathProvider
    }

    func isAvailable() -> Bool {
        if case .pong = try? send(.ping) {
            return true
        }
        return false
    }

    func ensureRunning() async throws -> PersistentTerminalHostStartupMode {
        guard let executablePath = executablePathProvider() else {
            throw NSError(
                domain: "PersistentTerminalHostController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Devys executable path is unavailable."]
            )
        }

        let expectedFingerprint = terminalHostExecutableFingerprint(at: executablePath)
        if daemonIsCompatible(
            executablePath: executablePath,
            executableFingerprint: expectedFingerprint
        ) {
            return .warm
        }

        // Unix domain socket paths have a small fixed limit. Fail fast here so callers
        // see the real startup problem instead of a generic timeout from the child process.
        _ = try TerminalHostSocketIO.makeSocketAddress(for: socketPath)

        let socketURL = URL(fileURLWithPath: socketPath)
        try fileManager.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        clearStaleHostRegistration()

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--terminal-host", "--socket", socketPath]
        process.environment = sanitizedHostEnvironment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()

        for _ in 0..<60 {
            if isAvailable() {
                return .cold
            }
            if !process.isRunning {
                throw startupFailure(process: process, errorPipe: errorPipe)
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw startupTimeout(errorPipe: errorPipe)
    }

    func listSessions() throws -> [HostedTerminalSessionRecord] {
        switch try send(.listSessions) {
        case .sessions(let sessions):
            return sessions
        case .failure(let message):
            throw hostFailure(message)
        default:
            throw TerminalHostSocketError.invalidResponse
        }
    }

    func createSession(
        id: UUID = UUID(),
        workspaceID: Workspace.ID,
        workingDirectory: URL?,
        launchCommand: String?,
        initialSize: HostedTerminalViewportSize? = nil,
        launchProfile: TerminalSessionLaunchProfile = .compatibilityShell,
        persistOnDisconnect: Bool,
        skipEnsureRunning: Bool = false
    ) async throws -> HostedTerminalSessionRecord {
        if !skipEnsureRunning {
            _ = try await ensureRunning()
        }
        switch try send(
            .createSession(
                id: id,
                workspaceID: workspaceID,
                workingDirectoryPath: workingDirectory?.path,
                launchCommand: launchCommand,
                initialSize: initialSize,
                launchProfile: launchProfile,
                persistOnDisconnect: persistOnDisconnect
            )
        ) {
        case .created(let record):
            return record
        case .failure(let message):
            throw hostFailure(message)
        default:
            throw TerminalHostSocketError.invalidResponse
        }
    }

    func terminateSession(id: UUID) throws {
        guard isAvailable() else { return }
        switch try send(.terminateSession(id: id)) {
        case .terminated:
            return
        case .failure(let message):
            throw hostFailure(message)
        default:
            throw TerminalHostSocketError.invalidResponse
        }
    }

    static func defaultSocketPath() -> String {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Devys", isDirectory: true)
            .appendingPathComponent("TerminalHost", isDirectory: true)

        return (baseURL ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("terminal-host.sock", isDirectory: false)
            .path
    }

    private func send(_ request: TerminalHostControlRequest) throws -> TerminalHostControlResponse {
        let fd = try TerminalHostSocketIO.connect(to: socketPath)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        return try TerminalHostSocketIO.withResponseTimeout(fileDescriptor: fd) {
            let requestData = try jsonEncoder.encode(request)
            try TerminalHostSocketIO.writeLine(requestData, to: handle)
            let responseData = try TerminalHostSocketIO.readLine(from: handle)
            return try jsonDecoder.decode(TerminalHostControlResponse.self, from: responseData)
        }
    }

    private func hostFailure(_ message: String) -> NSError {
        NSError(
            domain: "PersistentTerminalHostController",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func startupFailure(process: Process, errorPipe: Pipe) -> NSError {
        let details = readStartupDiagnostics(from: errorPipe)
        var message = "The terminal host exited before it became available."
        if !details.isEmpty {
            message += " \(details)"
        } else {
            message += " Exit status: \(process.terminationStatus)."
        }
        return NSError(
            domain: "PersistentTerminalHostController",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func startupTimeout(errorPipe: Pipe) -> NSError {
        let details = readStartupDiagnostics(from: errorPipe)
        var message = "Timed out waiting for the terminal host to start."
        if !details.isEmpty {
            message += " \(details)"
        }
        return NSError(
            domain: "PersistentTerminalHostController",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private func readStartupDiagnostics(from errorPipe: Pipe) -> String {
        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return ""
        }
        return "Host output: \(text)"
    }

    private func sanitizedHostEnvironment() -> [String: String] {
        var environment = colorCapableEnvironment(ProcessInfo.processInfo.environment)
        for key in environment.keys where
            key.hasPrefix("XCTest")
            || key.hasPrefix("XCInject")
            || key == "DYLD_INSERT_LIBRARIES" {
            environment.removeValue(forKey: key)
        }
        if let resourcePath = Bundle.main.resourceURL?.path(percentEncoded: false),
           !resourcePath.isEmpty {
            environment["DEVYS_RESOURCE_DIR"] = resourcePath
        }
        return environment
    }

    private func daemonIsCompatible(
        executablePath: String,
        executableFingerprint: String?
    ) -> Bool {
        guard isAvailable(), let metadata = loadDaemonMetadata() else {
            return false
        }

        return metadata.matches(
            executablePath: executablePath,
            executableFingerprint: executableFingerprint
        )
    }

    private func loadDaemonMetadata() -> TerminalHostDaemonMetadata? {
        guard let data = fileManager.contents(atPath: metadataPath) else {
            return nil
        }
        return try? jsonDecoder.decode(TerminalHostDaemonMetadata.self, from: data)
    }

    private func clearStaleHostRegistration() {
        if fileManager.fileExists(atPath: socketPath) {
            try? fileManager.removeItem(atPath: socketPath)
        }
        if fileManager.fileExists(atPath: metadataPath) {
            try? fileManager.removeItem(atPath: metadataPath)
        }
    }
}
