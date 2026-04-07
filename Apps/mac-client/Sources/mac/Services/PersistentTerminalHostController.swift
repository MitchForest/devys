// PersistentTerminalHostController.swift
// Devys - Client bridge for the detached terminal host process.

import Foundation
import Workspace

actor PersistentTerminalHostController {
    private let fileManager: FileManager
    private let socketPath: String
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
        self.executablePathProvider = executablePathProvider
    }

    func isAvailable() -> Bool {
        if case .pong = try? send(.ping) {
            return true
        }
        return false
    }

    func ensureRunning() async throws {
        if isAvailable() {
            return
        }

        let socketURL = URL(fileURLWithPath: socketPath)
        try fileManager.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard let executablePath = executablePathProvider() else {
            throw NSError(
                domain: "PersistentTerminalHostController",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Devys executable path is unavailable."]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["--terminal-host", "--socket", socketPath]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        for _ in 0..<60 {
            if isAvailable() {
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw NSError(
            domain: "PersistentTerminalHostController",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the terminal host to start."]
        )
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
        launchCommand: String?
    ) async throws -> HostedTerminalSessionRecord {
        try await ensureRunning()
        switch try send(
            .createSession(
                id: id,
                workspaceID: workspaceID,
                workingDirectoryPath: workingDirectory?.path,
                launchCommand: launchCommand
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

    func attachCommand(for sessionID: UUID) -> String {
        let executablePath = executablePathProvider() ?? ""
        return [
            shellEscape(executablePath),
            "--terminal-attach",
            "--socket",
            shellEscape(socketPath),
            "--session-id",
            shellEscape(sessionID.uuidString)
        ].joined(separator: " ")
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
        let requestData = try jsonEncoder.encode(request)
        try TerminalHostSocketIO.writeLine(requestData, to: handle)
        let responseData = try TerminalHostSocketIO.readLine(from: handle)
        return try jsonDecoder.decode(TerminalHostControlResponse.self, from: responseData)
    }

    private func hostFailure(_ message: String) -> NSError {
        NSError(
            domain: "PersistentTerminalHostController",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
private func shellEscape(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }
    if value.unicodeScalars.allSatisfy({ scalar in
        CharacterSet.alphanumerics.contains(scalar) || "/-._:".unicodeScalars.contains(scalar)
    }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
